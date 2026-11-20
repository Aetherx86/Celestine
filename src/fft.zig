const std = @import("std");

pub const FFT_SIZE: usize = 1024;
pub const NUM_BINS: usize = FFT_SIZE / 2;
const FFT_LOG2: u6 = 10;

pub const WindowType = enum(u32) {
    hann = 0,
    hamming = 1,
    blackman_harris = 2,
    rectangular = 3,

    pub fn fromU32(val: u32) WindowType {
        return switch (val) {
            0 => .hann,
            1 => .hamming,
            2 => .blackman_harris,
            3 => .rectangular,
            else => .hann,
        };
    }
};

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

    pub inline fn conj(self: Complex) Complex {
        return .{ .r = self.r, .i = -self.i };
    }

    pub inline fn magSquared(self: Complex) f32 {
        return (self.r * self.r) + (self.i * self.i);
    }

    pub inline fn magnitude(self: Complex) f32 {
        return @sqrt(self.magSquared());
    }
};

pub const SpectralMetrics = struct {
    peak_bin: usize,
    peak_magnitude: f32,
    peak_freq_hz: f32,
    centroid_hz: f32,
    rolloff_85_hz: f32,
    flatness: f32,
    rms: f32,
    peak_amplitude: f32,
    peak_dbfs: f32,
    crest_factor: f32,
    zero_crossing_hz: f32,
};

pub const FftAnalyzer = struct {
    // Active window weights (field name retained for backward compatibility)
    hann_window: [FFT_SIZE]f32,
    // Precomputed exact twiddle factors W_N^k = exp(-i * 2*pi*k / N) for k in 0..N/2
    twiddles: [NUM_BINS]Complex,
    // Precomputed bit-reversal permutation table
    bit_rev: [FFT_SIZE]u16,
    window_type: WindowType = .hann,

    pub fn init() FftAnalyzer {
        var analyzer: FftAnalyzer = undefined;
        analyzer.initInPlace(.hann);
        return analyzer;
    }

    pub fn initWithWindow(wt: WindowType) FftAnalyzer {
        var analyzer: FftAnalyzer = undefined;
        analyzer.initInPlace(wt);
        return analyzer;
    }

    pub fn initInPlace(self: *FftAnalyzer, wt: WindowType) void {
        self.window_type = wt;
        self.populateWindow(wt);

        for (0..FFT_SIZE) |n| {
            self.bit_rev[n] = @intCast(bitReverse(n, FFT_LOG2));
        }

        const inv_n = -2.0 * std.math.pi / @as(f32, @floatFromInt(FFT_SIZE));
        for (0..NUM_BINS) |k| {
            const angle = inv_n * @as(f32, @floatFromInt(k));
            self.twiddles[k] = .{ .r = @cos(angle), .i = @sin(angle) };
        }
    }

    pub fn setWindow(self: *FftAnalyzer, wt: WindowType) void {
        if (self.window_type == wt) return;
        self.window_type = wt;
        self.populateWindow(wt);
    }

    fn populateWindow(self: *FftAnalyzer, wt: WindowType) void {
        const denom = @as(f32, @floatFromInt(FFT_SIZE - 1));
        for (0..FFT_SIZE) |n| {
            const x = @as(f32, @floatFromInt(n)) / denom;
            const a = 2.0 * std.math.pi * x;
            self.hann_window[n] = switch (wt) {
                .hann => 0.5 * (1.0 - @cos(a)),
                .hamming => 0.54 - (0.46 * @cos(a)),
                .blackman_harris => 0.35875 - (0.48829 * @cos(a)) + (0.14128 * @cos(2.0 * a)) - (0.01168 * @cos(3.0 * a)),
                .rectangular => 1.0,
            };
        }
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

    /// Execute in-place Radix-2 Cooley-Tukey FFT using precomputed twiddle and bit-reversal LUTs.
    pub fn computeComplexFft(
        self: *const FftAnalyzer,
        samples: *const [FFT_SIZE]f32,
        apply_window: bool,
        out_complex: *[FFT_SIZE]Complex,
    ) void {
        if (apply_window) {
            for (0..FFT_SIZE) |n| {
                const s = if (std.math.isFinite(samples[n])) samples[n] else 0.0;
                out_complex[self.bit_rev[n]] = .{
                    .r = s * self.hann_window[n],
                    .i = 0.0,
                };
            }
        } else {
            for (0..FFT_SIZE) |n| {
                const s = if (std.math.isFinite(samples[n])) samples[n] else 0.0;
                out_complex[self.bit_rev[n]] = .{
                    .r = s,
                    .i = 0.0,
                };
            }
        }

        var len: usize = 2;
        while (len <= FFT_SIZE) : (len <<= 1) {
            const half_len = len >> 1;
            const twiddle_step = FFT_SIZE / len;

            var i: usize = 0;
            while (i < FFT_SIZE) : (i += len) {
                var j: usize = 0;
                while (j < half_len) : (j += 1) {
                    const w = self.twiddles[j * twiddle_step];
                    const u = out_complex[i + j];
                    const v = out_complex[i + j + half_len].mul(w);

                    out_complex[i + j] = u.add(v);
                    out_complex[i + j + half_len] = u.sub(v);
                }
            }
        }
    }

    pub fn computeSpectrum(self: *const FftAnalyzer, samples: *const [FFT_SIZE]f32, out_bins: *[NUM_BINS]f32) void {
        var buffer: [FFT_SIZE]Complex = undefined;
        self.computeComplexFft(samples, true, &buffer);

        const scale = 2.0 / @as(f32, @floatFromInt(FFT_SIZE));
        for (0..NUM_BINS) |k| {
            out_bins[k] = buffer[k].magnitude() * scale;
        }
    }

    pub fn computeSpectrumDb(
        self: *const FftAnalyzer,
        samples: *const [FFT_SIZE]f32,
        out_db: *[NUM_BINS]f32,
        floor_db: f32,
    ) void {
        var bins: [NUM_BINS]f32 = undefined;
        self.computeSpectrum(samples, &bins);
        const safe_floor = if (std.math.isFinite(floor_db) and floor_db < 0.0) floor_db else -120.0;
        for (0..NUM_BINS) |k| {
            if (bins[k] <= 1.0e-12) {
                out_db[k] = safe_floor;
            } else {
                const db = 20.0 * @log10(bins[k]);
                out_db[k] = @max(safe_floor, db);
            }
        }
    }

    /// Compute full time-domain and spectral telemetry, including sub-bin parabolic
    /// peak frequency estimation, spectral centroid, 85% rolloff, and Wiener flatness.
    pub fn analyze(self: *const FftAnalyzer, samples: *const [FFT_SIZE]f32, sample_rate: f32) SpectralMetrics {
        const sr = if (std.math.isFinite(sample_rate) and sample_rate >= 1.0) sample_rate else 44100.0;

        // Time-domain metrics: RMS, peak, crest factor, zero-crossing rate
        var sum_sq: f64 = 0.0;
        var peak_amp: f32 = 0.0;
        var zc_count: usize = 0;
        var prev: f32 = 0.0;
        for (0..FFT_SIZE) |n| {
            const s = if (std.math.isFinite(samples[n])) samples[n] else 0.0;
            sum_sq += @as(f64, s) * @as(f64, s);
            const a = @abs(s);
            if (a > peak_amp) peak_amp = a;
            if (n > 0 and ((prev < 0.0 and s >= 0.0) or (prev >= 0.0 and s < 0.0))) {
                zc_count += 1;
            }
            prev = s;
        }
        const rms: f32 = @floatCast(@sqrt(sum_sq / @as(f64, @floatFromInt(FFT_SIZE))));
        const peak_dbfs: f32 = if (peak_amp <= 1.0e-12) -120.0 else @max(-120.0, 20.0 * @log10(peak_amp));
        const crest_factor: f32 = if (rms > 1.0e-9) peak_amp / rms else 0.0;
        // Two zero crossings per cycle
        const zc_hz: f32 = (@as(f32, @floatFromInt(zc_count)) * sr) / (2.0 * @as(f32, @floatFromInt(FFT_SIZE - 1)));

        var bins: [NUM_BINS]f32 = undefined;
        self.computeSpectrum(samples, &bins);

        const bin_hz = sr / @as(f32, @floatFromInt(FFT_SIZE));

        // Find dominant AC bin (skip DC bin 0 unless all AC bins are zero)
        var peak_bin: usize = 0;
        var peak_mag: f32 = 0.0;
        for (1..NUM_BINS) |k| {
            if (bins[k] > peak_mag) {
                peak_mag = bins[k];
                peak_bin = k;
            }
        }

        // Quadratic (parabolic) interpolation in log-magnitude domain for sub-bin accuracy
        var peak_freq_hz: f32 = 0.0;
        if (peak_mag > 1.0e-9) {
            var delta: f32 = 0.0;
            if (peak_bin > 1 and peak_bin + 1 < NUM_BINS) {
                const alpha = @log(@max(bins[peak_bin - 1], 1.0e-12));
                const beta = @log(@max(bins[peak_bin], 1.0e-12));
                const gamma = @log(@max(bins[peak_bin + 1], 1.0e-12));
                const denom = alpha - (2.0 * beta) + gamma;
                if (@abs(denom) > 1.0e-9) {
                    delta = std.math.clamp(0.5 * (alpha - gamma) / denom, -0.5, 0.5);
                }
            }
            peak_freq_hz = (@as(f32, @floatFromInt(peak_bin)) + delta) * bin_hz;
        }

        // Spectral centroid, 85% energy rolloff, and Wiener spectral flatness
        var mag_sum: f64 = 0.0;
        var weighted_freq_sum: f64 = 0.0;
        var power_sum: f64 = 0.0;
        var log_power_sum: f64 = 0.0;
        const ac_bins: f64 = @floatFromInt(NUM_BINS - 1);

        for (1..NUM_BINS) |k| {
            const m: f64 = @floatCast(bins[k]);
            const p: f64 = m * m;
            const freq: f64 = @as(f64, @floatFromInt(k)) * @as(f64, bin_hz);
            mag_sum += m;
            weighted_freq_sum += m * freq;
            power_sum += p;
            log_power_sum += @log(@max(p, 1.0e-24));
        }

        const centroid_hz: f32 = if (mag_sum > 1.0e-12) @floatCast(weighted_freq_sum / mag_sum) else 0.0;

        var rolloff_85_hz: f32 = 0.0;
        if (power_sum > 1.0e-18) {
            const target_energy = power_sum * 0.85;
            var cum_energy: f64 = 0.0;
            for (1..NUM_BINS) |k| {
                const m: f64 = @floatCast(bins[k]);
                cum_energy += m * m;
                if (cum_energy >= target_energy) {
                    rolloff_85_hz = @as(f32, @floatFromInt(k)) * bin_hz;
                    break;
                }
            }
        }

        var flatness: f32 = 0.0;
        if (power_sum > 1.0e-18) {
            const arith_mean = power_sum / ac_bins;
            const geom_mean = @exp(log_power_sum / ac_bins);
            flatness = @floatCast(std.math.clamp(geom_mean / arith_mean, 0.0, 1.0));
        }

        return .{
            .peak_bin = peak_bin,
            .peak_magnitude = peak_mag,
            .peak_freq_hz = peak_freq_hz,
            .centroid_hz = centroid_hz,
            .rolloff_85_hz = rolloff_85_hz,
            .flatness = flatness,
            .rms = rms,
            .peak_amplitude = peak_amp,
            .peak_dbfs = peak_dbfs,
            .crest_factor = crest_factor,
            .zero_crossing_hz = zc_hz,
        };
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

test "FFT obeys Parseval energy conservation theorem" {
    const analyzer = FftAnalyzer.init();
    var samples: [FFT_SIZE]f32 = undefined;

    var time_energy: f64 = 0.0;
    for (0..FFT_SIZE) |n| {
        const t = @as(f32, @floatFromInt(n)) / 44100.0;
        const x = (0.6 * @sin(2.0 * std.math.pi * 330.0 * t)) +
            (0.35 * @cos(2.0 * std.math.pi * 1470.0 * t)) +
            (0.15 * @sin(2.0 * std.math.pi * 5120.0 * t));
        samples[n] = x;
        time_energy += @as(f64, x) * @as(f64, x);
    }

    var complex_out: [FFT_SIZE]Complex = undefined;
    analyzer.computeComplexFft(&samples, false, &complex_out);

    var freq_energy: f64 = 0.0;
    for (complex_out) |c| {
        freq_energy += @as(f64, c.magSquared());
    }
    freq_energy /= @as(f64, @floatFromInt(FFT_SIZE));

    try std.testing.expectApproxEqRel(time_energy, freq_energy, 1.0e-4);
}

test "FFT parabolic interpolation recovers sub-bin frequency and spectral metrics" {
    const analyzer = FftAnalyzer.init();
    const sr: f32 = 44100.0;
    var samples: [FFT_SIZE]f32 = undefined;

    // 440 Hz sits between bin 10 (430.66 Hz) and bin 11 (473.73 Hz)
    for (0..FFT_SIZE) |n| {
        const t = @as(f32, @floatFromInt(n)) / sr;
        samples[n] = @sin(2.0 * std.math.pi * 440.0 * t);
    }

    const tone_metrics = analyzer.analyze(&samples, sr);
    try std.testing.expectApproxEqAbs(@as(f32, 440.0), tone_metrics.peak_freq_hz, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7071), tone_metrics.rms, 0.02);
    try std.testing.expect(tone_metrics.flatness < 0.05);
    try std.testing.expect(tone_metrics.centroid_hz > 350.0 and tone_metrics.centroid_hz < 600.0);

    // Compare against broadband white noise: much higher flatness & centroid
    var seed: u32 = 0xCAFEBABE;
    for (0..FFT_SIZE) |n| {
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
        samples[n] = (@as(f32, @floatFromInt(seed & 0xFFFF)) / 32768.0) - 1.0;
    }
    const noise_metrics = analyzer.analyze(&samples, sr);
    try std.testing.expect(noise_metrics.flatness > 0.35);
    try std.testing.expect(noise_metrics.centroid_hz > 8000.0);
}

test "FFT Blackman-Harris window reduces spectral leakage vs rectangular" {
    const sr: f32 = 44100.0;
    var samples: [FFT_SIZE]f32 = undefined;
    // Non-bin-centered tone (bin 20.5 -> ~882.86 Hz) maximizes rectangular leakage
    const freq = 20.5 * (sr / @as(f32, @floatFromInt(FFT_SIZE)));
    for (0..FFT_SIZE) |n| {
        const t = @as(f32, @floatFromInt(n)) / sr;
        samples[n] = @sin(2.0 * std.math.pi * freq * t);
    }

    const rect = FftAnalyzer.initWithWindow(.rectangular);
    const bh = FftAnalyzer.initWithWindow(.blackman_harris);

    var bins_rect: [NUM_BINS]f32 = undefined;
    var bins_bh: [NUM_BINS]f32 = undefined;
    rect.computeSpectrum(&samples, &bins_rect);
    bh.computeSpectrum(&samples, &bins_bh);

    // Far sidelobe at bin 100 should be orders of magnitude lower with Blackman-Harris
    try std.testing.expect(bins_bh[100] < bins_rect[100] * 0.05);
}
