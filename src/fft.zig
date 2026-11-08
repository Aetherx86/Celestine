const std = @import("std");

pub const FFT_SIZE: usize = 1024;
pub const NUM_BINS: usize = FFT_SIZE / 2;

pub const Complex = struct {
    r: f32,
    i: f32,

    pub inline fn add(a: Complex, b: Complex) Complex {
        return .{ .r = a.r + b.r, .i = a.i + b.i };
    }

    pub inline fn sub(a: Complex, b: Complex) Complex {
        return .{ .r = a.r - b.r, .i = a.i - b.i };
    }

    pub inline fn mul(a: Complex, b: Complex) Complex {
        return .{
            .r = (a.r * b.r) - (a.i * b.i),
            .i = (a.r * b.i) + (a.i * b.r),
        };
    }

    pub inline fn magnitude(self: Complex) f32 {
        return @sqrt((self.r * self.r) + (self.i * self.i));
    }
};

pub const FftAnalyzer = struct {
    hann_window: [FFT_SIZE]f32,

    pub fn init() FftAnalyzer {
        var analyzer = FftAnalyzer{
            .hann_window = undefined,
        };
        for (0..FFT_SIZE) |n| {
            const angle = 2.0 * std.math.pi * @as(f32, @floatFromInt(n)) / @as(f32, @floatFromInt(FFT_SIZE - 1));
            analyzer.hann_window[n] = 0.5 * (1.0 - @cos(angle));
        }
        return analyzer;
    }

    fn bitReverse(x_in: usize, bits: u6) usize {
        var x = x_in;
        var rev: usize = 0;
        var i: usize = 0;
        while (i < bits) : (i += 1) {
            rev = (rev << 1) | (x & 1);
            x >>= 1;
        }
        return rev;
    }

    pub fn computeSpectrum(self: *const FftAnalyzer, samples: *const [FFT_SIZE]f32, out_bins: *[NUM_BINS]f32) void {
        var buffer: [FFT_SIZE]Complex = undefined;

        // Apply Hann window and bit-reversal permutation
        for (0..FFT_SIZE) |n| {
            const rev = bitReverse(n, 10); // 2^10 = 1024
            buffer[rev] = Complex{
                .r = samples[n] * self.hann_window[n],
                .i = 0.0,
            };
        }

        // Cooley-Tukey Radix-2 in-place FFT
        var len: usize = 2;
        while (len <= FFT_SIZE) : (len <<= 1) {
            const half_len = len >> 1;
            const angle_step = -2.0 * std.math.pi / @as(f32, @floatFromInt(len));
            const w_step = Complex{ .r = @cos(angle_step), .i = @sin(angle_step) };

            var i: usize = 0;
            while (i < FFT_SIZE) : (i += len) {
                var w = Complex{ .r = 1.0, .i = 0.0 };
                var j: usize = 0;
                while (j < half_len) : (j += 1) {
                    const u = buffer[i + j];
                    const v = buffer[i + j + half_len].mul(w);

                    buffer[i + j] = u.add(v);
                    buffer[i + j + half_len] = u.sub(v);

                    w = w.mul(w_step);
                }
            }
        }

        // Compute normalized magnitude spectrum
        const scale = 2.0 / @as(f32, @floatFromInt(FFT_SIZE));
        for (0..NUM_BINS) |k| {
            out_bins[k] = buffer[k].magnitude() * scale;
        }
    }
};

test "FFT pure sine peak detection" {
    const analyzer = FftAnalyzer.init();

    // Generate 440 Hz sine at 44100 Hz
    var samples: [FFT_SIZE]f32 = undefined;
    const freq: f32 = 440.0;
    const sr: f32 = 44100.0;
    for (0..FFT_SIZE) |n| {
        const t = @as(f32, @floatFromInt(n)) / sr;
        samples[n] = @sin(2.0 * std.math.pi * freq * t);
    }

    var bins: [NUM_BINS]f32 = undefined;
    analyzer.computeSpectrum(&samples, &bins);

    // Expected peak bin: round(440 * 1024 / 44100) = 10
    const expected_bin: usize = 10;
    var max_bin: usize = 0;
    var max_val: f32 = -1.0;

    for (0..NUM_BINS) |k| {
        if (bins[k] > max_val) {
            max_val = bins[k];
            max_bin = k;
        }
    }

    try std.testing.expectEqual(expected_bin, max_bin);
    try std.testing.expect(max_val > 0.4);
}
