const std = @import("std");

pub const AdsrState = enum {
    idle,
    attack,
    decay,
    sustain,
    release,
};

pub const EnvelopeCurve = enum(u32) {
    linear = 0,
    exponential = 1,

    pub fn fromU32(val: u32) EnvelopeCurve {
        return switch (val) {
            0 => .linear,
            1 => .exponential,
            else => .linear,
        };
    }
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

    attack_sec: f32 = 0.01,
    decay_sec: f32 = 0.1,
    release_sec: f32 = 0.2,
    release_samples: f32 = 8820.0,

    curve: EnvelopeCurve = .linear,
    attack_coef: f32 = 0.0,
    attack_base: f32 = 0.0,
    decay_coef: f32 = 0.0,
    decay_base: f32 = 0.0,
    release_coef: f32 = 0.0,
    release_base: f32 = 0.0,

    const TARGET_RATIO_ATTACK: f32 = 0.3;
    const TARGET_RATIO_DECAY_RELEASE: f32 = 0.001;

    pub fn init(sample_rate: f32) Adsr {
        const sr = if (std.math.isFinite(sample_rate) and sample_rate >= 1.0) sample_rate else 44100.0;
        var adsr = Adsr{
            .sample_rate = sr,
        };
        adsr.setParameters(0.01, 0.1, 0.7, 0.2); // 10ms attack, 100ms decay, 0.7 sustain, 200ms release
        return adsr;
    }

    inline fn calcExpCoef(samples: f32, target_ratio: f32) f32 {
        if (samples <= 1.0) return 0.0;
        return @exp(-@log((1.0 + target_ratio) / target_ratio) / samples);
    }

    pub fn setParameters(self: *Adsr, attack_sec: f32, decay_sec: f32, sustain: f32, release_sec: f32) void {
        const sr = if (self.sample_rate >= 1.0) self.sample_rate else 44100.0;
        const safe_a = if (std.math.isFinite(attack_sec)) @max(0.0, attack_sec) else self.attack_sec;
        const safe_d = if (std.math.isFinite(decay_sec)) @max(0.0, decay_sec) else self.decay_sec;
        const safe_s = if (std.math.isFinite(sustain)) std.math.clamp(sustain, 0.0, 1.0) else self.sustain_level;
        const safe_r = if (std.math.isFinite(release_sec)) @max(0.0, release_sec) else self.release_sec;

        self.attack_sec = safe_a;
        self.decay_sec = safe_d;
        self.sustain_level = safe_s;
        self.release_sec = safe_r;

        const a_samples = @max(1.0, safe_a * sr);
        const d_samples = @max(1.0, safe_d * sr);
        const r_samples = @max(1.0, safe_r * sr);
        self.release_samples = r_samples;

        self.attack_rate = 1.0 / a_samples;
        self.decay_rate = (1.0 - safe_s) / d_samples;
        // Guard against zero release_rate when sustain == 0.0
        const nominal_release_start = @max(safe_s, 1.0e-3);
        self.release_rate = nominal_release_start / r_samples;

        // Precompute analog RC exponential coefficients
        self.attack_coef = calcExpCoef(a_samples, TARGET_RATIO_ATTACK);
        self.attack_base = (1.0 + TARGET_RATIO_ATTACK) * (1.0 - self.attack_coef);

        self.decay_coef = calcExpCoef(d_samples, TARGET_RATIO_DECAY_RELEASE);
        self.decay_base = (safe_s - TARGET_RATIO_DECAY_RELEASE) * (1.0 - self.decay_coef);

        self.release_coef = calcExpCoef(r_samples, TARGET_RATIO_DECAY_RELEASE);
        self.release_base = -TARGET_RATIO_DECAY_RELEASE * (1.0 - self.release_coef);
    }

    pub fn setAttack(self: *Adsr, sec: f32) void {
        self.setParameters(sec, self.decay_sec, self.sustain_level, self.release_sec);
    }

    pub fn setDecay(self: *Adsr, sec: f32) void {
        self.setParameters(self.attack_sec, sec, self.sustain_level, self.release_sec);
    }

    pub fn setSustain(self: *Adsr, level: f32) void {
        self.setParameters(self.attack_sec, self.decay_sec, level, self.release_sec);
    }

    pub fn setRelease(self: *Adsr, sec: f32) void {
        self.setParameters(self.attack_sec, self.decay_sec, self.sustain_level, sec);
    }

    pub fn setCurve(self: *Adsr, curve: EnvelopeCurve) void {
        self.curve = curve;
    }

    pub fn isActive(self: *const Adsr) bool {
        return self.state != .idle;
    }

    pub fn reset(self: *Adsr) void {
        self.state = .idle;
        self.current_value = 0.0;
    }

    pub fn gateOn(self: *Adsr, vel: f32) void {
        const safe_vel = if (std.math.isFinite(vel)) std.math.clamp(vel, 0.0, 1.0) else 1.0;
        self.velocity = safe_vel;
        self.state = .attack;
    }

    pub fn gateOff(self: *Adsr) void {
        if (self.state == .idle) {
            self.current_value = 0.0;
            return;
        }
        self.state = .release;
        // Scale linear release slope from actual current_value so release duration is
        // accurate from any stage (attack, decay, or sustain) and never stalls at 0.
        const r_samples = @max(1.0, self.release_samples);
        self.release_rate = @max(self.current_value, 1.0e-4) / r_samples;
    }

    pub fn nextSample(self: *Adsr) f32 {
        switch (self.state) {
            .idle => {
                self.current_value = 0.0;
            },
            .attack => {
                if (self.curve == .exponential) {
                    self.current_value = self.attack_base + (self.current_value * self.attack_coef);
                } else {
                    self.current_value += self.attack_rate;
                }
                if (self.current_value >= 1.0) {
                    self.current_value = 1.0;
                    self.state = .decay;
                }
            },
            .decay => {
                if (self.curve == .exponential) {
                    self.current_value = self.decay_base + (self.current_value * self.decay_coef);
                } else {
                    self.current_value -= self.decay_rate;
                }
                if (self.current_value <= self.sustain_level) {
                    self.current_value = self.sustain_level;
                    self.state = .sustain;
                }
            },
            .sustain => {
                self.current_value = self.sustain_level;
            },
            .release => {
                if (self.curve == .exponential) {
                    self.current_value = self.release_base + (self.current_value * self.release_coef);
                } else {
                    self.current_value -= self.release_rate;
                }
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

test "ADSR zero sustain percussive release never stalls" {
    var adsr = Adsr.init(1000.0);
    adsr.setParameters(0.02, 0.05, 0.0, 0.01); // sustain = 0.0

    adsr.gateOn(1.0);
    // Interrupt halfway through attack
    for (0..10) |_| {
        _ = adsr.nextSample();
    }
    try std.testing.expect(adsr.current_value > 0.4);

    adsr.gateOff();
    for (0..15) |_| {
        _ = adsr.nextSample();
    }
    try std.testing.expectEqual(AdsrState.idle, adsr.state);
    try std.testing.expectEqual(@as(f32, 0.0), adsr.current_value);
}

test "ADSR exponential curve shapes attack, decay, and release" {
    var adsr = Adsr.init(1000.0);
    adsr.setCurve(.exponential);
    adsr.setParameters(0.05, 0.10, 0.25, 0.05); // 50, 100, 50 samples

    adsr.gateOn(1.0);
    // Mid-attack (sample 25) should be convex (above linear 0.5)
    for (0..25) |_| {
        _ = adsr.nextSample();
    }
    try std.testing.expect(adsr.current_value > 0.55);

    // Finish attack
    for (0..30) |_| {
        _ = adsr.nextSample();
    }
    try std.testing.expect(adsr.state == .decay or adsr.state == .sustain);

    // Wait through decay into sustain
    for (0..110) |_| {
        _ = adsr.nextSample();
    }
    try std.testing.expectEqual(AdsrState.sustain, adsr.state);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), adsr.current_value, 1.0e-4);

    // Release should finish cleanly within bounded samples
    adsr.gateOff();
    for (0..60) |_| {
        _ = adsr.nextSample();
    }
    try std.testing.expectEqual(AdsrState.idle, adsr.state);
    try std.testing.expectEqual(@as(f32, 0.0), adsr.current_value);
}
