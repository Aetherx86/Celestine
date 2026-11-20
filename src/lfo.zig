const std = @import("std");

pub const LfoWaveform = enum(u32) {
    sine = 0,
    triangle = 1,
    saw_up = 2,
    saw_down = 3,
    square = 4,
    sample_and_hold = 5,

    pub fn fromU32(val: u32) LfoWaveform {
        return switch (val) {
            0 => .sine,
            1 => .triangle,
            2 => .saw_up,
            3 => .saw_down,
            4 => .square,
            5 => .sample_and_hold,
            else => .sine,
        };
    }
};

pub const LfoTarget = enum(u32) {
    none = 0,
    pitch = 1,
    filter_cutoff = 2,
    amplitude = 3,
    pulse_width = 4,
    fm_depth = 5,

    pub fn fromU32(val: u32) LfoTarget {
        return switch (val) {
            0 => .none,
            1 => .pitch,
            2 => .filter_cutoff,
            3 => .amplitude,
            4 => .pulse_width,
            5 => .fm_depth,
            else => .none,
        };
    }
};

/// Zero-allocation Low-Frequency Oscillator for cyclic and stepped modulation routing.
pub const Lfo = struct {
    sample_rate: f32 = 44100.0,
    rate_hz: f32 = 2.0,
    depth: f32 = 0.0,
    waveform: LfoWaveform = .sine,
    target: LfoTarget = .none,

    phase: f32 = 0.0,
    sh_seed: u32 = 0x5EED1234,
    sh_value: f32 = 0.0,

    pub fn init(sample_rate: f32) Lfo {
        const sr = if (std.math.isFinite(sample_rate) and sample_rate >= 1.0) sample_rate else 44100.0;
        var lfo = Lfo{
            .sample_rate = sr,
        };
        lfo.sh_value = lfo.nextRandom();
        return lfo;
    }

    pub fn setRate(self: *Lfo, hz: f32) void {
        if (!std.math.isFinite(hz)) return;
        self.rate_hz = std.math.clamp(hz, 0.05, 50.0);
    }

    pub fn setDepth(self: *Lfo, depth: f32) void {
        if (!std.math.isFinite(depth)) return;
        self.depth = std.math.clamp(depth, 0.0, 1.0);
    }

    pub fn setWaveform(self: *Lfo, wf: LfoWaveform) void {
        self.waveform = wf;
    }

    pub fn setTarget(self: *Lfo, target: LfoTarget) void {
        self.target = target;
    }

    pub fn reset(self: *Lfo) void {
        self.phase = 0.0;
        self.sh_seed = 0x5EED1234;
        self.sh_value = self.nextRandom();
    }

    fn nextRandom(self: *Lfo) f32 {
        var x = if (self.sh_seed == 0) @as(u32, 0x5EED1234) else self.sh_seed;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.sh_seed = x;
        return (@as(f32, @floatFromInt(x & 0xFFFF)) / 32768.0) - 1.0;
    }

    /// Advance LFO by one sample and return unscaled bipolar signal in [-1, 1].
    pub fn nextRaw(self: *Lfo) f32 {
        const raw: f32 = switch (self.waveform) {
            .sine => @sin(2.0 * std.math.pi * self.phase),
            .triangle => 1.0 - (4.0 * @abs(self.phase - 0.5)),
            .saw_up => (2.0 * self.phase) - 1.0,
            .saw_down => 1.0 - (2.0 * self.phase),
            .square => if (self.phase < 0.5) 1.0 else -1.0,
            .sample_and_hold => self.sh_value,
        };

        const sr = if (self.sample_rate >= 1.0) self.sample_rate else 44100.0;
        self.phase += self.rate_hz / sr;
        if (self.phase >= 1.0) {
            self.phase -= @floor(self.phase);
            self.sh_value = self.nextRandom();
        }
        return raw;
    }

    /// Advance LFO by one sample and return depth-scaled modulation in [-depth, +depth].
    pub fn nextSample(self: *Lfo) f32 {
        return self.nextRaw() * self.depth;
    }
};

test "LFO waveforms stay bounded and step properly" {
    var lfo = Lfo.init(1000.0);
    lfo.setRate(10.0); // 100 samples per cycle
    lfo.setDepth(0.5);

    const wfs = [_]LfoWaveform{ .sine, .triangle, .saw_up, .saw_down, .square, .sample_and_hold };
    for (wfs) |wf| {
        lfo.reset();
        lfo.setWaveform(wf);
        for (0..250) |_| {
            const v = lfo.nextSample();
            try std.testing.expect(std.math.isFinite(v));
            try std.testing.expect(v >= -0.501 and v <= 0.501);
        }
    }

    // Verify Sample & Hold stays constant within one cycle and updates on wrap
    lfo.reset();
    lfo.setWaveform(.sample_and_hold);
    lfo.setDepth(1.0);
    const first = lfo.nextSample();
    for (0..98) |_| {
        try std.testing.expectEqual(first, lfo.nextSample());
    }
    // Advance across cycle boundary (allowing f32 rounding on 100 * 0.01)
    _ = lfo.nextSample();
    _ = lfo.nextSample();
    const second = lfo.nextSample();
    try std.testing.expect(second != first);
}
