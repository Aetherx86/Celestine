const std = @import("std");

pub const Waveform = enum(u32) {
    sine = 0,
    saw = 1,
    square = 2,
    triangle = 3,
    noise = 4,
};

pub const Oscillator = struct {
    phase: f32 = 0.0,
    frequency: f32 = 440.0,
    sample_rate: f32 = 44100.0,
    waveform: Waveform = .sine,
    pulse_width: f32 = 0.5,
    noise_seed: u32 = 0x12345678,

    pub fn init(sample_rate: f32) Oscillator {
        return .{
            .phase = 0.0,
            .frequency = 440.0,
            .sample_rate = sample_rate,
            .waveform = .sine,
            .pulse_width = 0.5,
            .noise_seed = 0x12345678,
        };
    }

    pub fn setFrequency(self: *Oscillator, freq: f32) void {
        self.frequency = freq;
    }

    pub fn setWaveform(self: *Oscillator, wf: Waveform) void {
        self.waveform = wf;
    }

    inline fn polyBlep(t: f32, dt: f32) f32 {
        if (t < dt) {
            const tau = t / dt;
            return (tau + tau) - (tau * tau) - 1.0;
        } else if (t > 1.0 - dt) {
            const tau = (t - 1.0) / dt;
            return (tau * tau) + (tau + tau) + 1.0;
        }
        return 0.0;
    }

    pub fn nextSample(self: *Oscillator, phase_mod: f32) f32 {
        const dt = self.frequency / self.sample_rate;
        var mod_phase = self.phase + phase_mod;
        while (mod_phase >= 1.0) mod_phase -= 1.0;
        while (mod_phase < 0.0) mod_phase += 1.0;

        var sample: f32 = 0.0;
        switch (self.waveform) {
            .sine => {
                sample = @sin(2.0 * std.math.pi * mod_phase);
            },
            .saw => {
                // Naive saw: 2 * t - 1
                sample = (2.0 * mod_phase) - 1.0;
                // Subtract polyBlep discontinuity
                sample -= polyBlep(mod_phase, dt);
            },
            .square => {
                const naive = if (mod_phase < self.pulse_width) @as(f32, 1.0) else @as(f32, -1.0);
                var shift_phase = mod_phase + (1.0 - self.pulse_width);
                if (shift_phase >= 1.0) shift_phase -= 1.0;

                sample = naive + polyBlep(mod_phase, dt) - polyBlep(shift_phase, dt);
            },
            .triangle => {
                // Derived from integrated square wave
                var naive = (4.0 * mod_phase) - 2.0;
                if (naive < 0.0) naive = -naive;
                sample = (2.0 * naive) - 1.0;
            },
            .noise => {
                // Xorshift32 PRNG
                var x = self.noise_seed;
                x ^= x << 13;
                x ^= x >> 17;
                x ^= x << 5;
                self.noise_seed = x;
                sample = (@as(f32, @floatFromInt(x & 0xFFFF)) / 32768.0) - 1.0;
            },
        }

        self.phase += dt;
        if (self.phase >= 1.0) {
            self.phase -= 1.0;
        }

        return sample;
    }
};

test "Oscillator range and waveforms" {
    var osc = Oscillator.init(44100.0);
    osc.setFrequency(440.0);

    // Test Sine bounds
    osc.setWaveform(.sine);
    for (0..100) |_| {
        const s = osc.nextSample(0.0);
        try std.testing.expect(s >= -1.05 and s <= 1.05);
    }

    // Test Saw bounds
    osc.setWaveform(.saw);
    for (0..100) |_| {
        const s = osc.nextSample(0.0);
        try std.testing.expect(s >= -1.2 and s <= 1.2);
    }

    // Test Square bounds
    osc.setWaveform(.square);
    for (0..100) |_| {
        const s = osc.nextSample(0.0);
        try std.testing.expect(s >= -1.2 and s <= 1.2);
    }
}
