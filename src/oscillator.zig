const std = @import("std");

pub const Waveform = enum(u32) {
    sine = 0,
    saw = 1,
    square = 2,
    triangle = 3,
    noise = 4,

    pub fn fromU32(val: u32) Waveform {
        return switch (val) {
            0 => .sine,
            1 => .saw,
            2 => .square,
            3 => .triangle,
            4 => .noise,
            else => .sine,
        };
    }
};

pub const Oscillator = struct {
    phase: f32 = 0.0,
    frequency: f32 = 440.0,
    sample_rate: f32 = 44100.0,
    waveform: Waveform = .sine,
    pulse_width: f32 = 0.5,
    noise_seed: u32 = 0x12345678,

    pub fn init(sample_rate: f32) Oscillator {
        const sr = if (std.math.isFinite(sample_rate) and sample_rate >= 1.0) sample_rate else 44100.0;
        return .{
            .phase = 0.0,
            .frequency = 440.0,
            .sample_rate = sr,
            .waveform = .sine,
            .pulse_width = 0.5,
            .noise_seed = 0x12345678,
        };
    }

    pub fn setFrequency(self: *Oscillator, freq: f32) void {
        if (!std.math.isFinite(freq)) return;
        const max_freq = self.sample_rate * 0.49;
        self.frequency = std.math.clamp(freq, 0.0, max_freq);
    }

    pub fn setWaveform(self: *Oscillator, wf: Waveform) void {
        self.waveform = wf;
    }

    pub fn setPulseWidth(self: *Oscillator, pw: f32) void {
        if (!std.math.isFinite(pw)) return;
        self.pulse_width = std.math.clamp(pw, 0.02, 0.98);
    }

    pub fn resetPhase(self: *Oscillator) void {
        self.phase = 0.0;
    }

    pub fn setNoiseSeed(self: *Oscillator, seed: u32) void {
        self.noise_seed = if (seed == 0) 0x12345678 else seed;
    }

    inline fn wrapPhase(p: f32) f32 {
        if (!std.math.isFinite(p)) return 0.0;
        const wrapped = p - @floor(p);
        return if (wrapped >= 1.0 or wrapped < 0.0) 0.0 else wrapped;
    }

    /// 2-point Polynomial Band-Limited Step (PolyBLEP) residual for step size 2.
    inline fn polyBlep(t: f32, dt: f32) f32 {
        if (dt <= 0.0) return 0.0;
        if (t < dt) {
            const tau = t / dt;
            return (tau + tau) - (tau * tau) - 1.0;
        } else if (t > 1.0 - dt) {
            const tau = (t - 1.0) / dt;
            return (tau * tau) + (tau + tau) + 1.0;
        }
        return 0.0;
    }

    /// 2-point Polynomial Band-Limited Ramp (PolyBLAMP) residual for a unit slope corner.
    /// Integrates the linear PolyBLEP kernel to suppress aliasing at triangle slope discontinuities.
    inline fn polyBlamp(t: f32, dt: f32) f32 {
        if (dt <= 0.0) return 0.0;
        if (t < dt) {
            const u = 1.0 - (t / dt);
            return (u * u * u) / 6.0;
        } else if (t > 1.0 - dt) {
            const u = (t - (1.0 - dt)) / dt;
            return (u * u * u) / 6.0;
        }
        return 0.0;
    }

    pub fn nextSample(self: *Oscillator, phase_mod: f32) f32 {
        return self.nextSampleWithPwm(phase_mod, 0.0);
    }

    pub fn nextSampleWithPwm(self: *Oscillator, phase_mod: f32, pw_mod: f32) f32 {
        const sr = if (self.sample_rate >= 1.0) self.sample_rate else 44100.0;
        const dt = std.math.clamp(self.frequency / sr, 0.0, 0.49);
        const safe_mod = if (std.math.isFinite(phase_mod)) phase_mod else 0.0;
        const mod_phase = wrapPhase(self.phase + safe_mod);

        var sample: f32 = 0.0;
        switch (self.waveform) {
            .sine => {
                sample = @sin(2.0 * std.math.pi * mod_phase);
            },
            .saw => {
                // Naive saw: 2*t - 1 in [-1, 1], subtract PolyBLEP at wrap discontinuity
                sample = (2.0 * mod_phase) - 1.0;
                sample -= polyBlep(mod_phase, dt);
            },
            .square => {
                const safe_pw_mod = if (std.math.isFinite(pw_mod)) pw_mod else 0.0;
                const pw = std.math.clamp(self.pulse_width + safe_pw_mod, 0.02, 0.98);
                const naive: f32 = if (mod_phase < pw) 1.0 else -1.0;
                const shift_phase = wrapPhase(mod_phase + (1.0 - pw));
                // Subtract DC offset (zero when pw == 0.5) to prevent PWM DC drift
                const dc_offset = (2.0 * pw) - 1.0;
                sample = naive + polyBlep(mod_phase, dt) - polyBlep(shift_phase, dt) - dc_offset;
            },
            .triangle => {
                // Symmetric triangle in [-1, +1]: valley -1 at t=0, peak +1 at t=0.5.
                // Slope changes +8*dt at t=0 and -8*dt at t=0.5; smooth corners with PolyBLAMP.
                const naive = 1.0 - (4.0 * @abs(mod_phase - 0.5));
                const half_shifted = wrapPhase(mod_phase + 0.5);
                const blamp = (8.0 * dt) * (polyBlamp(mod_phase, dt) - polyBlamp(half_shifted, dt));
                sample = naive + blamp;
            },
            .noise => {
                // Xorshift32 PRNG with zero-seed guard
                var x = if (self.noise_seed == 0) @as(u32, 0x12345678) else self.noise_seed;
                x ^= x << 13;
                x ^= x >> 17;
                x ^= x << 5;
                self.noise_seed = x;
                sample = (@as(f32, @floatFromInt(x & 0xFFFF)) / 32768.0) - 1.0;
            },
        }

        self.phase = wrapPhase(self.phase + dt);
        return sample;
    }
};

test "Oscillator range and all waveforms" {
    var osc = Oscillator.init(44100.0);
    osc.setFrequency(440.0);

    const waveforms = [_]Waveform{ .sine, .saw, .square, .triangle, .noise };
    for (waveforms) |wf| {
        osc.resetPhase();
        osc.setWaveform(wf);
        var min_val: f32 = 100.0;
        var max_val: f32 = -100.0;
        for (0..512) |_| {
            const s = osc.nextSample(0.0);
            try std.testing.expect(std.math.isFinite(s));
            try std.testing.expect(s >= -1.2 and s <= 1.2);
            if (s < min_val) min_val = s;
            if (s > max_val) max_val = s;
        }
        // Every waveform should span both positive and negative polarities
        try std.testing.expect(min_val < -0.5);
        try std.testing.expect(max_val > 0.5);
    }
}

test "Oscillator triangle amplitude symmetry and PolyBLAMP bounds" {
    var osc = Oscillator.init(44100.0);
    osc.setWaveform(.triangle);
    osc.setFrequency(440.0);

    var sum: f32 = 0.0;
    const count: usize = 4410; // exact 44 cycles
    for (0..count) |_| {
        const s = osc.nextSample(0.0);
        try std.testing.expect(s >= -1.01 and s <= 1.01);
        sum += s;
    }
    const dc_mean = sum / @as(f32, @floatFromInt(count));
    try std.testing.expect(@abs(dc_mean) < 0.01);
}

test "Oscillator PWM DC neutrality" {
    var osc = Oscillator.init(44100.0);
    osc.setWaveform(.square);
    osc.setFrequency(441.0); // exact 100 samples/cycle
    osc.setPulseWidth(0.2);

    var sum: f32 = 0.0;
    const count: usize = 1000; // exact 10 cycles
    for (0..count) |_| {
        sum += osc.nextSample(0.0);
    }
    const dc_mean = sum / @as(f32, @floatFromInt(count));
    try std.testing.expect(@abs(dc_mean) < 0.02);
}

test "Oscillator handles extreme phase modulation and zero noise seed safely" {
    var osc = Oscillator.init(44100.0);
    osc.setWaveform(.sine);
    osc.setFrequency(440.0);

    const s_huge = osc.nextSample(1.0e9);
    try std.testing.expect(std.math.isFinite(s_huge));
    const s_neg = osc.nextSample(-1.0e9);
    try std.testing.expect(std.math.isFinite(s_neg));
    const s_nan = osc.nextSample(std.math.nan(f32));
    try std.testing.expect(std.math.isFinite(s_nan));

    osc.setWaveform(.noise);
    osc.noise_seed = 0;
    var non_zero = false;
    for (0..16) |_| {
        if (@abs(osc.nextSample(0.0)) > 0.001) non_zero = true;
    }
    try std.testing.expect(non_zero);
}
