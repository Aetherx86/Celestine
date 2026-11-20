const std = @import("std");

pub const FilterType = enum(u32) {
    lowpass = 0,
    highpass = 1,
    bandpass = 2,
    notch = 3,
    peak = 4,
    allpass = 5,

    pub fn fromU32(val: u32) FilterType {
        return switch (val) {
            0 => .lowpass,
            1 => .highpass,
            2 => .bandpass,
            3 => .notch,
            4 => .peak,
            5 => .allpass,
            else => .lowpass,
        };
    }
};

pub const SvfOutputs = struct {
    low: f32,
    band: f32,
    high: f32,
    notch: f32,
    peak: f32,
    allpass: f32,
};

/// Topology-Preserving Transform (TPT) / Cytomic Zero-Delay Feedback State Variable Filter.
/// Unconditionally stable up to Nyquist across all resonances and audio-rate cutoff modulation.
pub const StateVariableFilter = struct {
    sample_rate: f32 = 44100.0,
    cutoff: f32 = 1000.0,
    resonance: f32 = 1.0,
    filter_type: FilterType = .lowpass,

    // Public state mirrors preserved for backward compatibility
    low: f32 = 0.0,
    band: f32 = 0.0,

    // TPT trapezoidal integrator states
    ic1eq: f32 = 0.0,
    ic2eq: f32 = 0.0,

    // Cached bilinear coefficients
    cached_cutoff: f32 = -1.0,
    cached_resonance: f32 = -1.0,
    k: f32 = 1.0,
    a1: f32 = 0.0,
    a2: f32 = 0.0,
    a3: f32 = 0.0,

    pub fn init(sample_rate: f32) StateVariableFilter {
        const sr = if (std.math.isFinite(sample_rate) and sample_rate >= 1.0) sample_rate else 44100.0;
        var svf = StateVariableFilter{
            .sample_rate = sr,
            .cutoff = 1000.0,
            .resonance = 1.0,
            .filter_type = .lowpass,
            .low = 0.0,
            .band = 0.0,
            .ic1eq = 0.0,
            .ic2eq = 0.0,
        };
        svf.updateCoefficients(svf.cutoff);
        return svf;
    }

    pub fn reset(self: *StateVariableFilter) void {
        self.low = 0.0;
        self.band = 0.0;
        self.ic1eq = 0.0;
        self.ic2eq = 0.0;
    }

    pub fn setCutoff(self: *StateVariableFilter, cutoff_hz: f32) void {
        if (!std.math.isFinite(cutoff_hz)) return;
        const nyquist = self.sample_rate * 0.49;
        self.cutoff = std.math.clamp(cutoff_hz, 20.0, nyquist);
    }

    pub fn setResonance(self: *StateVariableFilter, q: f32) void {
        if (!std.math.isFinite(q)) return;
        self.resonance = std.math.clamp(q, 0.5, 20.0);
    }

    pub fn setFilterType(self: *StateVariableFilter, ft: FilterType) void {
        self.filter_type = ft;
    }

    inline fn updateCoefficients(self: *StateVariableFilter, active_cutoff: f32) void {
        const sr = if (self.sample_rate >= 1.0) self.sample_rate else 44100.0;
        const clamped_fc = std.math.clamp(active_cutoff, 20.0, sr * 0.49);
        const clamped_q = std.math.clamp(self.resonance, 0.5, 20.0);

        if (clamped_fc == self.cached_cutoff and clamped_q == self.cached_resonance) {
            return;
        }

        const g = @tan(std.math.pi * clamped_fc / sr);
        const k = 1.0 / clamped_q;
        const a1 = 1.0 / (1.0 + g * (g + k));
        const a2 = g * a1;
        const a3 = g * a2;

        self.k = k;
        self.a1 = a1;
        self.a2 = a2;
        self.a3 = a3;
        self.cached_cutoff = clamped_fc;
        self.cached_resonance = clamped_q;
    }

    /// Evaluate all six simultaneous SVF outputs at an arbitrary modulated cutoff
    /// without mutating the filter's base `cutoff` parameter.
    pub fn processAll(self: *StateVariableFilter, input: f32, modulated_cutoff: f32) SvfOutputs {
        const safe_in = if (std.math.isFinite(input)) input else 0.0;
        const safe_fc = if (std.math.isFinite(modulated_cutoff)) modulated_cutoff else self.cutoff;
        self.updateCoefficients(safe_fc);

        const v3 = safe_in - self.ic2eq;
        const v1 = (self.a1 * self.ic1eq) + (self.a2 * v3);
        const v2 = self.ic2eq + (self.a2 * self.ic1eq) + (self.a3 * v3);

        self.ic1eq = (2.0 * v1) - self.ic1eq;
        self.ic2eq = (2.0 * v2) - self.ic2eq;

        // Anti-denormal and NaN safety flush
        if (!std.math.isFinite(self.ic1eq) or @abs(self.ic1eq) < 1.0e-18) self.ic1eq = 0.0;
        if (!std.math.isFinite(self.ic2eq) or @abs(self.ic2eq) < 1.0e-18) self.ic2eq = 0.0;

        self.low = v2;
        self.band = v1;

        const high = safe_in - (self.k * v1) - v2;
        const notch = safe_in - (self.k * v1);
        const peak = v2 - high;
        const allpass = safe_in - (2.0 * self.k * v1);

        return .{
            .low = v2,
            .band = v1,
            .high = high,
            .notch = notch,
            .peak = peak,
            .allpass = allpass,
        };
    }

    pub fn processModulated(self: *StateVariableFilter, input: f32, modulated_cutoff: f32) f32 {
        const out = self.processAll(input, modulated_cutoff);
        return switch (self.filter_type) {
            .lowpass => out.low,
            .highpass => out.high,
            .bandpass => out.band,
            .notch => out.notch,
            .peak => out.peak,
            .allpass => out.allpass,
        };
    }

    pub fn process(self: *StateVariableFilter, input: f32) f32 {
        return self.processModulated(input, self.cutoff);
    }
};

test "State Variable Filter stability" {
    var svf = StateVariableFilter.init(44100.0);
    svf.setCutoff(500.0);
    svf.setResonance(2.0);

    // Process 1000 samples of DC step
    for (0..1000) |_| {
        const out = svf.process(1.0);
        try std.testing.expect(!std.math.isNan(out));
        try std.testing.expect(out > -5.0 and out < 5.0);
    }

    // Output should settle near 1.0 for lowpass on DC input
    try std.testing.expect(svf.low > 0.8 and svf.low < 1.2);
}

test "TPT ZDF SVF unconditional stability near Nyquist and high resonance" {
    var svf = StateVariableFilter.init(44100.0);
    svf.setCutoff(20000.0);
    svf.setResonance(20.0);

    // Rapid audio-rate cutoff sweep + impulse train must stay finite and bounded
    for (0..2048) |i| {
        const mod_fc: f32 = if ((i & 1) == 0) 20000.0 else 120.0;
        const x: f32 = if (i % 64 == 0) 1.0 else 0.0;
        const out = svf.processModulated(x, mod_fc);
        try std.testing.expect(std.math.isFinite(out));
        try std.testing.expect(@abs(out) < 50.0);
    }
    // Base cutoff must remain preserved
    try std.testing.expectApproxEqAbs(@as(f32, 20000.0), svf.cutoff, 1.0e-3);
}

test "TPT ZDF SVF frequency selectivity across filter modes" {
    const sr: f32 = 44100.0;
    const fc: f32 = 1000.0;

    // Helper to measure steady-state RMS gain of a sine wave
    const measureGain = struct {
        fn run(ft: FilterType, freq_hz: f32) f32 {
            var svf = StateVariableFilter.init(sr);
            svf.setCutoff(fc);
            svf.setResonance(0.7071); // Butterworth Q
            svf.setFilterType(ft);

            var sum_sq: f32 = 0.0;
            const warmup: usize = 1024;
            const measure: usize = 2048;
            for (0..warmup + measure) |n| {
                const t = @as(f32, @floatFromInt(n)) / sr;
                const x = @sin(2.0 * std.math.pi * freq_hz * t);
                const y = svf.process(x);
                if (n >= warmup) sum_sq += y * y;
            }
            return @sqrt((2.0 * sum_sq) / @as(f32, @floatFromInt(measure)));
        }
    }.run;

    // Lowpass: passes 200 Hz, strongly attenuates 6000 Hz
    try std.testing.expect(measureGain(.lowpass, 200.0) > 0.95);
    try std.testing.expect(measureGain(.lowpass, 6000.0) < 0.05);

    // Highpass: attenuates 200 Hz, passes 6000 Hz
    try std.testing.expect(measureGain(.highpass, 200.0) < 0.06);
    try std.testing.expect(measureGain(.highpass, 6000.0) > 0.95);

    // Notch: rejects cutoff frequency 1000 Hz, passes 200 Hz and 6000 Hz
    try std.testing.expect(measureGain(.notch, 1000.0) < 0.02);
    try std.testing.expect(measureGain(.notch, 200.0) > 0.90);
    try std.testing.expect(measureGain(.notch, 6000.0) > 0.90);

    // Allpass: unity magnitude response across frequencies
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), measureGain(.allpass, 200.0), 0.03);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), measureGain(.allpass, 1000.0), 0.03);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), measureGain(.allpass, 6000.0), 0.03);
}
