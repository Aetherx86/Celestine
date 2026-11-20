const std = @import("std");

pub const DELAY_BUFFER_SIZE: usize = 4096;
const DELAY_MASK: usize = DELAY_BUFFER_SIZE - 1;

/// Zero-allocation fractional feedback delay & modulated chorus processor.
/// Operates entirely on a fixed 4096-sample circular line (16 KB) with one-pole
/// feedback damping for analog-style warmth and guaranteed BIBO stability.
pub const ChorusDelay = struct {
    sample_rate: f32 = 44100.0,
    delay_ms: f32 = 25.0,
    feedback: f32 = 0.25,
    wet_mix: f32 = 0.0,
    damping: f32 = 0.3,

    // Chorus modulation parameters
    mod_rate_hz: f32 = 0.8,
    mod_depth_ms: f32 = 0.0,
    mod_phase: f32 = 0.0,

    // State
    buffer: [DELAY_BUFFER_SIZE]f32 = @splat(0.0),
    write_idx: usize = 0,
    lp_state: f32 = 0.0,

    pub fn init(sample_rate: f32) ChorusDelay {
        var fx: ChorusDelay = undefined;
        fx.initInPlace(sample_rate);
        return fx;
    }

    pub fn initInPlace(self: *ChorusDelay, sample_rate: f32) void {
        const sr = if (std.math.isFinite(sample_rate) and sample_rate >= 1.0) sample_rate else 44100.0;
        self.sample_rate = sr;
        self.delay_ms = 25.0;
        self.feedback = 0.25;
        self.wet_mix = 0.0;
        self.damping = 0.3;
        self.mod_rate_hz = 0.8;
        self.mod_depth_ms = 0.0;
        self.mod_phase = 0.0;
        self.write_idx = 0;
        self.lp_state = 0.0;
        @memset(&self.buffer, 0.0);
    }

    pub fn clear(self: *ChorusDelay) void {
        @memset(&self.buffer, 0.0);
        self.write_idx = 0;
        self.lp_state = 0.0;
        self.mod_phase = 0.0;
    }

    pub fn maxDelayMs(self: *const ChorusDelay) f32 {
        const sr = if (self.sample_rate >= 1.0) self.sample_rate else 44100.0;
        return (@as(f32, @floatFromInt(DELAY_BUFFER_SIZE - 2)) * 1000.0) / sr;
    }

    pub fn setDelayMs(self: *ChorusDelay, ms: f32) void {
        if (!std.math.isFinite(ms)) return;
        const max_ms = self.maxDelayMs();
        self.delay_ms = std.math.clamp(ms, 0.5, max_ms);
    }

    pub fn setFeedback(self: *ChorusDelay, fb: f32) void {
        if (!std.math.isFinite(fb)) return;
        self.feedback = std.math.clamp(fb, 0.0, 0.9);
    }

    pub fn setWetMix(self: *ChorusDelay, mix: f32) void {
        if (!std.math.isFinite(mix)) return;
        self.wet_mix = std.math.clamp(mix, 0.0, 1.0);
    }

    pub fn setDamping(self: *ChorusDelay, damp: f32) void {
        if (!std.math.isFinite(damp)) return;
        self.damping = std.math.clamp(damp, 0.0, 0.95);
    }

    pub fn setChorusMod(self: *ChorusDelay, rate_hz: f32, depth_ms: f32) void {
        if (std.math.isFinite(rate_hz)) {
            self.mod_rate_hz = std.math.clamp(rate_hz, 0.05, 10.0);
        }
        if (std.math.isFinite(depth_ms)) {
            self.mod_depth_ms = std.math.clamp(depth_ms, 0.0, 10.0);
        }
    }

    inline fn readFractional(self: *const ChorusDelay, delay_samples: f32) f32 {
        const clamped = std.math.clamp(delay_samples, 1.0, @as(f32, @floatFromInt(DELAY_BUFFER_SIZE - 2)));
        const int_delay: usize = @intFromFloat(@floor(clamped));
        const frac = clamped - @floor(clamped);

        const idx0 = (self.write_idx + DELAY_BUFFER_SIZE - int_delay) & DELAY_MASK;
        const idx1 = (idx0 + DELAY_BUFFER_SIZE - 1) & DELAY_MASK;

        const s0 = self.buffer[idx0];
        const s1 = self.buffer[idx1];
        return s0 + (frac * (s1 - s0));
    }

    pub fn process(self: *ChorusDelay, input: f32) f32 {
        const safe_in = if (std.math.isFinite(input)) input else 0.0;
        if (self.wet_mix <= 0.0001) {
            return safe_in;
        }

        const sr = if (self.sample_rate >= 1.0) self.sample_rate else 44100.0;
        var mod_ms: f32 = 0.0;
        if (self.mod_depth_ms > 0.0) {
            mod_ms = @sin(2.0 * std.math.pi * self.mod_phase) * self.mod_depth_ms;
            self.mod_phase += self.mod_rate_hz / sr;
            if (self.mod_phase >= 1.0) self.mod_phase -= 1.0;
        }

        const total_ms = std.math.clamp(self.delay_ms + mod_ms, 0.5, self.maxDelayMs());
        const delay_samples = (total_ms * sr) / 1000.0;
        const delayed = self.readFractional(delay_samples);

        // One-pole low-pass damping in feedback loop
        self.lp_state = self.lp_state + ((1.0 - self.damping) * (delayed - self.lp_state));
        if (!std.math.isFinite(self.lp_state) or @abs(self.lp_state) < 1.0e-18) {
            self.lp_state = 0.0;
        }

        self.buffer[self.write_idx] = safe_in + (self.lp_state * self.feedback);
        self.write_idx = (self.write_idx + 1) & DELAY_MASK;

        return (safe_in * (1.0 - self.wet_mix)) + (delayed * self.wet_mix);
    }
};

test "ChorusDelay exact impulse echo timing and feedback decay" {
    var fx = ChorusDelay.init(1000.0); // 1 sample = 1 ms
    fx.setDelayMs(10.0);
    fx.setFeedback(0.5);
    fx.setDamping(0.0); // pure undamped echo for exact ratio check
    fx.setWetMix(0.5);

    var out: [40]f32 = undefined;
    for (0..out.len) |i| {
        const impulse: f32 = if (i == 0) 1.0 else 0.0;
        out[i] = fx.process(impulse);
    }

    // Dry impulse at t=0: 0.5
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), out[0], 1.0e-4);
    // First echo at t=10: wet(0.5) * 1.0 = 0.5
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), out[10], 1.0e-4);
    // Second echo at t=20: wet(0.5) * 0.5 = 0.25
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), out[20], 1.0e-4);
    // Third echo at t=30: wet(0.5) * 0.25 = 0.125
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), out[30], 1.0e-4);
}

test "ChorusDelay bypasses cleanly when wet_mix is zero and stays bounded with chorus" {
    var fx = ChorusDelay.init(44100.0);
    fx.setWetMix(0.0);
    try std.testing.expectEqual(@as(f32, 0.75), fx.process(0.75));

    fx.setDelayMs(12.0);
    fx.setFeedback(0.85);
    fx.setDamping(0.4);
    fx.setChorusMod(1.5, 3.0);
    fx.setWetMix(0.4);

    for (0..4096) |i| {
        const x = @sin(2.0 * std.math.pi * 220.0 * @as(f32, @floatFromInt(i)) / 44100.0);
        const y = fx.process(x);
        try std.testing.expect(std.math.isFinite(y));
        try std.testing.expect(@abs(y) < 10.0);
    }
}
