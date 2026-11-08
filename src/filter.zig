const std = @import("std");

pub const FilterType = enum(u32) {
    lowpass = 0,
    highpass = 1,
    bandpass = 2,
    notch = 3,
};

pub const StateVariableFilter = struct {
    sample_rate: f32 = 44100.0,
    cutoff: f32 = 1000.0,
    resonance: f32 = 1.0,
    filter_type: FilterType = .lowpass,

    low: f32 = 0.0,
    band: f32 = 0.0,

    pub fn init(sample_rate: f32) StateVariableFilter {
        return .{
            .sample_rate = sample_rate,
            .cutoff = 1000.0,
            .resonance = 1.0,
            .filter_type = .lowpass,
            .low = 0.0,
            .band = 0.0,
        };
    }

    pub fn setCutoff(self: *StateVariableFilter, cutoff_hz: f32) void {
        const nyquist = self.sample_rate * 0.49;
        self.cutoff = std.math.clamp(cutoff_hz, 20.0, nyquist);
    }

    pub fn setResonance(self: *StateVariableFilter, q: f32) void {
        self.resonance = std.math.clamp(q, 0.5, 20.0);
    }

    pub fn process(self: *StateVariableFilter, input: f32) f32 {
        var f = 2.0 * @sin(std.math.pi * self.cutoff / self.sample_rate);
        f = std.math.clamp(f, 0.001, 0.95);
        const q = 1.0 / self.resonance;

        self.low += f * self.band;
        const high = input - self.low - (q * self.band);
        self.band += f * high;
        const notch = high + self.low;

        // Anti-denormal flush
        if (@abs(self.low) < 1.0e-15) self.low = 0.0;
        if (@abs(self.band) < 1.0e-15) self.band = 0.0;

        return switch (self.filter_type) {
            .lowpass => self.low,
            .highpass => high,
            .bandpass => self.band,
            .notch => notch,
        };
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
