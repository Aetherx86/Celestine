const std = @import("std");

pub const AdsrState = enum {
    idle,
    attack,
    decay,
    sustain,
    release,
};

pub const Adsr = struct {
    sample_rate: f32 = 44100.0,
    state: AdsrState = .idle,
    current_value: f32 = 0.0,
    velocity: f32 = 1.0,

    attack_rate: f32 = 0.001,
    decay_rate: f32 = 0.001,
    sustain_level: f32 = 0.7,
    release_rate: f32 = 0.001,

    pub fn init(sample_rate: f32) Adsr {
        var adsr = Adsr{
            .sample_rate = sample_rate,
        };
        adsr.setParameters(0.01, 0.1, 0.7, 0.2); // 10ms attack, 100ms decay, 0.7 sustain, 200ms release
        return adsr;
    }

    pub fn setParameters(self: *Adsr, attack_sec: f32, decay_sec: f32, sustain: f32, release_sec: f32) void {
        const a_samples = @max(1.0, attack_sec * self.sample_rate);
        const d_samples = @max(1.0, decay_sec * self.sample_rate);
        const r_samples = @max(1.0, release_sec * self.sample_rate);

        self.attack_rate = 1.0 / a_samples;
        self.decay_rate = (1.0 - sustain) / d_samples;
        self.sustain_level = std.math.clamp(sustain, 0.0, 1.0);
        self.release_rate = self.sustain_level / r_samples;
    }

    pub fn gateOn(self: *Adsr, vel: f32) void {
        self.velocity = std.math.clamp(vel, 0.0, 1.0);
        self.state = .attack;
    }

    pub fn gateOff(self: *Adsr) void {
        self.state = .release;
    }

    pub fn nextSample(self: *Adsr) f32 {
        switch (self.state) {
            .idle => {
                self.current_value = 0.0;
            },
            .attack => {
                self.current_value += self.attack_rate;
                if (self.current_value >= 1.0) {
                    self.current_value = 1.0;
                    self.state = .decay;
                }
            },
            .decay => {
                self.current_value -= self.decay_rate;
                if (self.current_value <= self.sustain_level) {
                    self.current_value = self.sustain_level;
                    self.state = .sustain;
                }
            },
            .sustain => {
                self.current_value = self.sustain_level;
            },
            .release => {
                self.current_value -= self.release_rate;
                if (self.current_value <= 0.0) {
                    self.current_value = 0.0;
                    self.state = .idle;
                }
            },
        }

        return self.current_value * self.velocity;
    }
};

test "ADSR lifecycle" {
    var adsr = Adsr.init(1000.0); // 1000 samples/sec for easy arithmetic
    adsr.setParameters(0.01, 0.01, 0.5, 0.01); // 10 samples each

    adsr.gateOn(1.0);
    try std.testing.expectEqual(AdsrState.attack, adsr.state);

    // Run attack
    for (0..10) |_| {
        _ = adsr.nextSample();
    }
    try std.testing.expect(adsr.current_value >= 0.99);

    // Run decay
    for (0..10) |_| {
        _ = adsr.nextSample();
    }
    try std.testing.expect(adsr.current_value <= 0.51);
    try std.testing.expectEqual(AdsrState.sustain, adsr.state);

    // Release
    adsr.gateOff();
    try std.testing.expectEqual(AdsrState.release, adsr.state);
    for (0..15) |_| {
        _ = adsr.nextSample();
    }
    try std.testing.expectEqual(@as(f32, 0.0), adsr.current_value);
    try std.testing.expectEqual(AdsrState.idle, adsr.state);
}
