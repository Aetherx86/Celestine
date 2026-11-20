const std = @import("std");
pub const osc = @import("oscillator.zig");
pub const filter = @import("filter.zig");
pub const envelope = @import("envelope.zig");
pub const lfo = @import("lfo.zig");
pub const effects = @import("effects.zig");
pub const fft = @import("fft.zig");
pub const synth = @import("synth.zig");
pub const poly = @import("poly.zig");
pub const wav = @import("wav.zig");
pub const wasm = @import("wasm.zig");

const VERSION = "0.2.0";

pub fn main(init: std.process.Init) !void {
    var out_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &out_buf);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};

    var args = init.minimal.args.iterate();
    _ = args.next(); // skip program name

    const cmd = args.next() orelse {
        try printUsage(out);
        return;
    };

    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "help")) {
        try printUsage(out);
        return;
    }

    if (std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "-v") or std.mem.eql(u8, cmd, "version")) {
        try out.print("Celestine v{s} (Audio DSP Modular Synthesizer & Oscilloscope)\n", .{VERSION});
        return;
    }

    if (std.mem.eql(u8, cmd, "render")) {
        try runRenderCmd(init.io, out, &args);
        return;
    }

    if (std.mem.eql(u8, cmd, "chord")) {
        try runChordCmd(init.io, out, &args);
        return;
    }

    if (std.mem.eql(u8, cmd, "analyze")) {
        try runAnalyzeCmd(out, &args);
        return;
    }

    if (std.mem.eql(u8, cmd, "bench")) {
        try runBenchCmd(init.io, out, &args);
        return;
    }

    if (std.mem.eql(u8, cmd, "presets")) {
        var json_mode = false;
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--json")) json_mode = true;
        }
        try runPresetsCmd(out, json_mode);
        return;
    }

    try out.print("Unknown command: {s}\n\n", .{cmd});
    try printUsage(out);
}

fn printUsage(out: *std.Io.Writer) !void {
    try out.writeAll(
        \\Celestine: Audio DSP Modular Synthesizer & Oscilloscope
        \\Usage: celestine <command> [options]
        \\
        \\Commands:
        \\  render [seconds] [opts]   Render mono note, inspect FFT telemetry, optional WAV output
        \\      --note <midi>         MIDI note 0..127 (default: 69 = A4 440 Hz)
        \\      --preset <name>       Patch preset name (default: init_saw)
        \\      --rate <hz>           Sample rate in Hz (default: 44100)
        \\      --out <file.wav>      Write rendered audio to RIFF WAV file
        \\      --float32             Encode WAV as 32-bit IEEE float instead of 16-bit PCM
        \\      --json                Emit machine-readable JSON telemetry
        \\
        \\  chord [seconds] [opts]    Render polyphonic chord via 8-voice PolySynth
        \\      --notes <m1,m2,...>   Comma-separated MIDI notes (default: 60,64,67,72)
        \\      --preset <name>       Patch preset name (default: warm_pad)
        \\      --rate <hz>           Sample rate in Hz (default: 44100)
        \\      --out <file.wav>      Write rendered chord to RIFF WAV file
        \\      --float32             Encode WAV as 32-bit IEEE float instead of 16-bit PCM
        \\      --json                Emit machine-readable JSON telemetry
        \\
        \\  analyze [opts]            Run 1024-point windowed FFT & spectral telemetry on a test tone
        \\      --freq <hz>           Oscillator frequency in Hz (default: 440.0)
        \\      --waveform <name>     sine | saw | square | triangle | noise (default: sine)
        \\      --window <name>       hann | hamming | blackman_harris | rectangular (default: hann)
        \\      --rate <hz>           Sample rate in Hz (default: 44100)
        \\      --json                Emit machine-readable JSON telemetry
        \\
        \\  bench [opts]              Benchmark polyphonic DSP render and 1024-pt FFT throughput
        \\      --frames <n>          Total audio frames to render (default: 441000)
        \\      --voices <1..8>       Active simultaneous voices (default: 4)
        \\      --ffts <n>            Number of 1024-point FFT passes (default: 2000)
        \\      --json                Emit machine-readable JSON metrics
        \\
        \\  presets [--json]          List built-in synthesizer patch presets
        \\  --version, -v             Print engine version
        \\  --help, -h                Print this help message
        \\
    );
}

fn parseWaveformName(str: []const u8) ?osc.Waveform {
    if (std.mem.eql(u8, str, "sine")) return .sine;
    if (std.mem.eql(u8, str, "saw")) return .saw;
    if (std.mem.eql(u8, str, "square")) return .square;
    if (std.mem.eql(u8, str, "triangle") or std.mem.eql(u8, str, "tri")) return .triangle;
    if (std.mem.eql(u8, str, "noise")) return .noise;
    return null;
}

fn parseWindowName(str: []const u8) ?fft.WindowType {
    if (std.mem.eql(u8, str, "hann")) return .hann;
    if (std.mem.eql(u8, str, "hamming")) return .hamming;
    if (std.mem.eql(u8, str, "blackman_harris") or std.mem.eql(u8, str, "bh")) return .blackman_harris;
    if (std.mem.eql(u8, str, "rectangular") or std.mem.eql(u8, str, "rect")) return .rectangular;
    return null;
}

pub fn parseMidiNotesList(csv: []const u8, out_notes: *[poly.MAX_VOICES]u8) usize {
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, csv, ',');
    while (it.next()) |token| {
        if (count >= out_notes.len) break;
        const trimmed = std.mem.trim(u8, token, " \t");
        if (trimmed.len == 0) continue;
        const parsed = std.fmt.parseInt(u8, trimmed, 10) catch continue;
        out_notes[count] = @min(parsed, 127);
        count += 1;
    }
    return count;
}

/// Parses a duration in seconds (fractional allowed) and clamps it to
/// [0.05, 600] so frame counts always fit the u32 WAV header field.
fn parseSeconds(arg: []const u8, fallback: f64) f64 {
    const v = std.fmt.parseFloat(f64, arg) catch return fallback;
    if (!std.math.isFinite(v)) return fallback;
    return std.math.clamp(v, 0.05, 600.0);
}

fn framesFor(seconds: f64, sample_rate: u32) usize {
    const sr: f64 = @floatFromInt(sample_rate);
    return @intFromFloat(@round(seconds * sr));
}

test "parseSeconds accepts fractions and clamps hostile input" {
    try std.testing.expectEqual(@as(f64, 0.25), parseSeconds("0.25", 1.0));
    try std.testing.expectEqual(@as(f64, 600.0), parseSeconds("1e12", 1.0));
    try std.testing.expectEqual(@as(f64, 0.05), parseSeconds("-3", 1.0));
    try std.testing.expectEqual(@as(f64, 1.0), parseSeconds("nan", 1.0));
    try std.testing.expectEqual(@as(f64, 2.0), parseSeconds("abc", 2.0));
    try std.testing.expectEqual(@as(usize, 11025), framesFor(0.25, 44100));
}

fn runRenderCmd(io: std.Io, out: *std.Io.Writer, args: *std.process.Args.Iterator) !void {
    var seconds: f64 = 1.0;
    var midi_note: u8 = 69;
    var preset: synth.PresetId = .init_saw;
    var sample_rate: u32 = 44100;
    var wav_path: ?[]const u8 = null;
    var wav_format: wav.WavFormat = .pcm16;
    var json_mode = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--note")) {
            if (args.next()) |v| {
                const n = std.fmt.parseInt(u8, v, 10) catch 69;
                midi_note = @min(n, 127);
            }
        } else if (std.mem.eql(u8, arg, "--preset")) {
            if (args.next()) |v| {
                preset = synth.PresetId.fromName(v) orelse .init_saw;
            }
        } else if (std.mem.eql(u8, arg, "--rate")) {
            if (args.next()) |v| {
                sample_rate = std.math.clamp(std.fmt.parseInt(u32, v, 10) catch 44100, 8000, 192000);
            }
        } else if (std.mem.eql(u8, arg, "--out")) {
            wav_path = args.next();
        } else if (std.mem.eql(u8, arg, "--float32")) {
            wav_format = .float32;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            seconds = parseSeconds(arg, 1.0);
        }
    }

    const sr_f: f32 = @floatFromInt(sample_rate);
    var engine = synth.Synth.init(sr_f);
    engine.loadPreset(preset);
    engine.noteOn(midi_note, 0.9);

    var buffer: [1024]f32 = undefined;
    const total_blocks = @max(@as(usize, 2), framesFor(seconds, sample_rate) / buffer.len);
    const total_frames: u32 = @intCast(total_blocks * buffer.len);
    const release_block = (total_blocks * 3) / 5;

    var wav_writer: ?wav.StreamWriter = if (wav_path) |p|
        try wav.StreamWriter.create(io, p, sample_rate, total_frames, wav_format)
    else
        null;
    defer if (wav_writer) |*w| w.close();

    var peak_amp: f32 = 0.0;
    var sum_sq: f64 = 0.0;
    var sustain_metrics: fft.SpectralMetrics = undefined;
    var captured_metrics = false;

    for (0..total_blocks) |blk| {
        if (blk == release_block) {
            // Capture FFT spectrum while voice is actively sustaining (before release tail)
            sustain_metrics = engine.getSpectralMetrics();
            captured_metrics = true;
            engine.noteOff();
        }
        engine.render(&buffer);
        if (wav_writer) |*w| {
            try w.writeFrames(&buffer);
        }
        for (buffer) |s| {
            const a = @abs(s);
            if (a > peak_amp) peak_amp = a;
            sum_sq += @as(f64, s) * @as(f64, s);
        }
    }

    if (!captured_metrics) {
        sustain_metrics = engine.getSpectralMetrics();
    }
    const overall_rms: f32 = @floatCast(@sqrt(sum_sq / @as(f64, @floatFromInt(total_frames))));
    const note_freq = synth.midiNoteToFreq(midi_note);

    if (json_mode) {
        try out.print(
            "{{\"command\":\"render\",\"preset\":\"{s}\",\"midi_note\":{d},\"note_freq_hz\":{d:.2},\"sample_rate\":{d},\"seconds\":{d:.3},\"frames\":{d},\"peak_amplitude\":{d:.5},\"rms\":{d:.5},\"sustain_fft\":{{\"peak_bin\":{d},\"peak_freq_hz\":{d:.2},\"peak_magnitude\":{d:.5},\"centroid_hz\":{d:.2},\"rolloff_85_hz\":{d:.2},\"flatness\":{d:.5}}}}}\n",
            .{
                preset.name(),
                midi_note,
                note_freq,
                sample_rate,
                seconds,
                total_frames,
                peak_amp,
                overall_rms,
                sustain_metrics.peak_bin,
                sustain_metrics.peak_freq_hz,
                sustain_metrics.peak_magnitude,
                sustain_metrics.centroid_hz,
                sustain_metrics.rolloff_85_hz,
                sustain_metrics.flatness,
            },
        );
    } else {
        try out.print("Preset: {s} | Note: MIDI {d} ({d:.2} Hz) | Sample Rate: {d} Hz\n", .{ preset.name(), midi_note, note_freq, sample_rate });
        try out.print("Render complete: {d:.2}s ({d} frames)\n", .{ seconds, total_frames });
        try out.print("Peak Amplitude: {d:.4} | Overall RMS: {d:.4}\n", .{ peak_amp, overall_rms });
        try out.print(
            "Sustain FFT Peak: Bin {d} ({d:.2} Hz, Mag: {d:.4}) | Centroid: {d:.1} Hz | Rolloff85: {d:.1} Hz | Flatness: {d:.4}\n",
            .{
                sustain_metrics.peak_bin,
                sustain_metrics.peak_freq_hz,
                sustain_metrics.peak_magnitude,
                sustain_metrics.centroid_hz,
                sustain_metrics.rolloff_85_hz,
                sustain_metrics.flatness,
            },
        );
        if (wav_path) |p| {
            try out.print("Wrote WAV: {s} ({s})\n", .{ p, if (wav_format == .pcm16) "16-bit PCM" else "32-bit IEEE float" });
        }
    }
}

fn runChordCmd(io: std.Io, out: *std.Io.Writer, args: *std.process.Args.Iterator) !void {
    var seconds: f64 = 2.0;
    var preset: synth.PresetId = .warm_pad;
    var sample_rate: u32 = 44100;
    var wav_path: ?[]const u8 = null;
    var wav_format: wav.WavFormat = .pcm16;
    var json_mode = false;
    var notes: [poly.MAX_VOICES]u8 = .{ 60, 64, 67, 72, 0, 0, 0, 0 };
    var note_count: usize = 4;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--notes")) {
            if (args.next()) |csv| {
                const parsed = parseMidiNotesList(csv, &notes);
                if (parsed > 0) note_count = parsed;
            }
        } else if (std.mem.eql(u8, arg, "--preset")) {
            if (args.next()) |v| {
                preset = synth.PresetId.fromName(v) orelse .warm_pad;
            }
        } else if (std.mem.eql(u8, arg, "--rate")) {
            if (args.next()) |v| {
                sample_rate = std.math.clamp(std.fmt.parseInt(u32, v, 10) catch 44100, 8000, 192000);
            }
        } else if (std.mem.eql(u8, arg, "--out")) {
            wav_path = args.next();
        } else if (std.mem.eql(u8, arg, "--float32")) {
            wav_format = .float32;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            seconds = parseSeconds(arg, 2.0);
        }
    }

    const sr_f: f32 = @floatFromInt(sample_rate);
    var ps = poly.PolySynth.init(sr_f);
    ps.loadPreset(preset);
    for (0..note_count) |i| {
        ps.noteOn(notes[i], 0.85);
    }
    const peak_voices = ps.activeVoiceCount();

    var buffer: [1024]f32 = undefined;
    const total_blocks = @max(@as(usize, 2), framesFor(seconds, sample_rate) / buffer.len);
    const total_frames: u32 = @intCast(total_blocks * buffer.len);
    const release_block = (total_blocks * 3) / 5;

    var wav_writer: ?wav.StreamWriter = if (wav_path) |p|
        try wav.StreamWriter.create(io, p, sample_rate, total_frames, wav_format)
    else
        null;
    defer if (wav_writer) |*w| w.close();

    var peak_amp: f32 = 0.0;
    var sum_sq: f64 = 0.0;
    var sustain_metrics: fft.SpectralMetrics = undefined;
    var captured = false;

    for (0..total_blocks) |blk| {
        if (blk == release_block) {
            sustain_metrics = ps.getSpectralMetrics();
            captured = true;
            ps.allNotesOff();
        }
        ps.render(&buffer);
        if (wav_writer) |*w| {
            try w.writeFrames(&buffer);
        }
        for (buffer) |s| {
            const a = @abs(s);
            if (a > peak_amp) peak_amp = a;
            sum_sq += @as(f64, s) * @as(f64, s);
        }
    }
    if (!captured) sustain_metrics = ps.getSpectralMetrics();
    const overall_rms: f32 = @floatCast(@sqrt(sum_sq / @as(f64, @floatFromInt(total_frames))));

    if (json_mode) {
        try out.print(
            "{{\"command\":\"chord\",\"preset\":\"{s}\",\"voices\":{d},\"sample_rate\":{d},\"frames\":{d},\"peak_amplitude\":{d:.5},\"rms\":{d:.5},\"sustain_fft\":{{\"peak_bin\":{d},\"peak_freq_hz\":{d:.2},\"peak_magnitude\":{d:.5},\"centroid_hz\":{d:.2},\"rolloff_85_hz\":{d:.2},\"flatness\":{d:.5}}}}}\n",
            .{
                preset.name(),
                peak_voices,
                sample_rate,
                total_frames,
                peak_amp,
                overall_rms,
                sustain_metrics.peak_bin,
                sustain_metrics.peak_freq_hz,
                sustain_metrics.peak_magnitude,
                sustain_metrics.centroid_hz,
                sustain_metrics.rolloff_85_hz,
                sustain_metrics.flatness,
            },
        );
    } else {
        try out.print("PolySynth Chord | Preset: {s} | Voices: {d} | Frames: {d}\n", .{ preset.name(), peak_voices, total_frames });
        try out.print("Peak Amplitude: {d:.4} | Overall RMS: {d:.4}\n", .{ peak_amp, overall_rms });
        try out.print(
            "Sustain FFT Peak: Bin {d} ({d:.2} Hz, Mag: {d:.4}) | Centroid: {d:.1} Hz | Rolloff85: {d:.1} Hz | Flatness: {d:.4}\n",
            .{
                sustain_metrics.peak_bin,
                sustain_metrics.peak_freq_hz,
                sustain_metrics.peak_magnitude,
                sustain_metrics.centroid_hz,
                sustain_metrics.rolloff_85_hz,
                sustain_metrics.flatness,
            },
        );
        if (wav_path) |p| {
            try out.print("Wrote WAV: {s} ({s})\n", .{ p, if (wav_format == .pcm16) "16-bit PCM" else "32-bit IEEE float" });
        }
    }
}

fn runAnalyzeCmd(out: *std.Io.Writer, args: *std.process.Args.Iterator) !void {
    var freq: f32 = 440.0;
    var waveform: osc.Waveform = .sine;
    var window: fft.WindowType = .hann;
    var sample_rate: u32 = 44100;
    var json_mode = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--freq")) {
            if (args.next()) |v| {
                freq = std.fmt.parseFloat(f32, v) catch 440.0;
            }
        } else if (std.mem.eql(u8, arg, "--waveform")) {
            if (args.next()) |v| {
                waveform = parseWaveformName(v) orelse .sine;
            }
        } else if (std.mem.eql(u8, arg, "--window")) {
            if (args.next()) |v| {
                window = parseWindowName(v) orelse .hann;
            }
        } else if (std.mem.eql(u8, arg, "--rate")) {
            if (args.next()) |v| {
                sample_rate = std.math.clamp(std.fmt.parseInt(u32, v, 10) catch 44100, 8000, 192000);
            }
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
        }
    }

    const sr_f: f32 = @floatFromInt(sample_rate);
    var gen = osc.Oscillator.init(sr_f);
    gen.setWaveform(waveform);
    gen.setFrequency(freq);

    var frame: [fft.FFT_SIZE]f32 = undefined;
    for (0..fft.FFT_SIZE) |i| {
        frame[i] = gen.nextSample(0.0);
    }

    const analyzer = fft.FftAnalyzer.initWithWindow(window);
    const m = analyzer.analyze(&frame, sr_f);

    if (json_mode) {
        try out.print(
            "{{\"command\":\"analyze\",\"waveform\":\"{s}\",\"window\":\"{s}\",\"target_freq_hz\":{d:.2},\"sample_rate\":{d},\"fft_size\":{d},\"peak_bin\":{d},\"peak_freq_hz\":{d:.2},\"peak_magnitude\":{d:.5},\"centroid_hz\":{d:.2},\"rolloff_85_hz\":{d:.2},\"flatness\":{d:.5},\"rms\":{d:.5},\"peak_amplitude\":{d:.5},\"peak_dbfs\":{d:.2},\"crest_factor\":{d:.4},\"zero_crossing_hz\":{d:.2}}}\n",
            .{
                @tagName(waveform),
                @tagName(window),
                freq,
                sample_rate,
                fft.FFT_SIZE,
                m.peak_bin,
                m.peak_freq_hz,
                m.peak_magnitude,
                m.centroid_hz,
                m.rolloff_85_hz,
                m.flatness,
                m.rms,
                m.peak_amplitude,
                m.peak_dbfs,
                m.crest_factor,
                m.zero_crossing_hz,
            },
        );
    } else {
        try out.print("FFT Analysis ({d}-pt, window={s}, waveform={s}, target={d:.2} Hz @ {d} Hz)\n", .{
            fft.FFT_SIZE,
            @tagName(window),
            @tagName(waveform),
            freq,
            sample_rate,
        });
        try out.print("  Peak Bin:       {d} ({d:.2} Hz interpolated, Mag {d:.4})\n", .{ m.peak_bin, m.peak_freq_hz, m.peak_magnitude });
        try out.print("  Centroid:       {d:.2} Hz | Rolloff (85%): {d:.2} Hz | Flatness: {d:.4}\n", .{ m.centroid_hz, m.rolloff_85_hz, m.flatness });
        try out.print("  RMS:            {d:.4} | Peak: {d:.4} ({d:.2} dBFS) | Crest: {d:.3} | ZCR: {d:.1} Hz\n", .{
            m.rms,
            m.peak_amplitude,
            m.peak_dbfs,
            m.crest_factor,
            m.zero_crossing_hz,
        });
    }
}

fn runBenchCmd(io: std.Io, out: *std.Io.Writer, args: *std.process.Args.Iterator) !void {
    var total_frames: usize = 441000; // 10 seconds at 44.1 kHz
    var num_voices: usize = 4;
    var fft_iters: usize = 2000;
    var json_mode = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--frames")) {
            if (args.next()) |v| {
                total_frames = @max(@as(usize, 1024), std.fmt.parseInt(usize, v, 10) catch 441000);
            }
        } else if (std.mem.eql(u8, arg, "--voices")) {
            if (args.next()) |v| {
                num_voices = std.math.clamp(std.fmt.parseInt(usize, v, 10) catch 4, 1, poly.MAX_VOICES);
            }
        } else if (std.mem.eql(u8, arg, "--ffts")) {
            if (args.next()) |v| {
                fft_iters = @max(@as(usize, 10), std.fmt.parseInt(usize, v, 10) catch 2000);
            }
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
        }
    }

    const sr: f32 = 44100.0;
    var ps = poly.PolySynth.init(sr);
    ps.loadPreset(.warm_pad);
    const chord = [_]u8{ 48, 55, 60, 64, 67, 71, 74, 79 };
    for (0..num_voices) |i| {
        ps.noteOn(chord[i], 0.85);
    }

    var buf: [1024]f32 = undefined;
    const blocks = @max(@as(usize, 1), total_frames / buf.len);
    const actual_frames = blocks * buf.len;

    const synth_t0 = std.Io.Clock.awake.now(io);
    var sink: f64 = 0.0;
    for (0..blocks) |_| {
        ps.render(&buf);
        sink += @as(f64, buf[0]) + @as(f64, buf[buf.len - 1]);
    }
    const synth_ns: f64 = @floatFromInt(@max(@as(i96, 1), synth_t0.untilNow(io, .awake).nanoseconds));
    const synth_sec = synth_ns / 1.0e9;
    const frames_per_sec = @as(f64, @floatFromInt(actual_frames)) / synth_sec;
    const realtime_x = frames_per_sec / @as(f64, sr);
    const ns_per_sample = synth_ns / @as(f64, @floatFromInt(actual_frames));

    var bins: [fft.NUM_BINS]f32 = undefined;
    const fft_t0 = std.Io.Clock.awake.now(io);
    for (0..fft_iters) |_| {
        ps.analyzer.computeSpectrum(&buf, &bins);
        sink += @as(f64, bins[10]);
    }
    const fft_ns: f64 = @floatFromInt(@max(@as(i96, 1), fft_t0.untilNow(io, .awake).nanoseconds));
    const fft_sec = fft_ns / 1.0e9;
    const ffts_per_sec = @as(f64, @floatFromInt(fft_iters)) / fft_sec;
    const us_per_fft = (fft_ns / 1.0e3) / @as(f64, @floatFromInt(fft_iters));

    if (json_mode) {
        try out.print(
            "{{\"command\":\"bench\",\"sample_rate\":44100,\"voices\":{d},\"frames\":{d},\"synth_elapsed_ms\":{d:.3},\"frames_per_sec\":{d:.1},\"ns_per_sample\":{d:.2},\"realtime_multiplier\":{d:.2},\"fft_iterations\":{d},\"fft_elapsed_ms\":{d:.3},\"ffts_per_sec\":{d:.1},\"us_per_fft\":{d:.2},\"checksum\":{d:.6}}}\n",
            .{
                num_voices,
                actual_frames,
                synth_sec * 1000.0,
                frames_per_sec,
                ns_per_sample,
                realtime_x,
                fft_iters,
                fft_sec * 1000.0,
                ffts_per_sec,
                us_per_fft,
                sink,
            },
        );
    } else {
        try out.print("Celestine DSP Benchmark (44.1 kHz, {d} poly voices + ZDF SVF + LFO + ChorusDelay)\n", .{num_voices});
        try out.print("  Synth Render: {d} frames in {d:.2} ms ({d:.0} frames/s, {d:.1} ns/sample, {d:.1}x realtime)\n", .{
            actual_frames,
            synth_sec * 1000.0,
            frames_per_sec,
            ns_per_sample,
            realtime_x,
        });
        try out.print("  1024-pt FFT:  {d} transforms in {d:.2} ms ({d:.0} FFTs/s, {d:.2} us/FFT)\n", .{
            fft_iters,
            fft_sec * 1000.0,
            ffts_per_sec,
            us_per_fft,
        });
        try out.print("  Checksum:     {d:.6}\n", .{sink});
    }
}

fn runPresetsCmd(out: *std.Io.Writer, json_mode: bool) !void {
    const all_presets = [_]synth.PresetId{
        .init_saw,
        .warm_pad,
        .acid_bass,
        .fm_bell,
        .pluck_lead,
        .ambient_chord,
    };

    if (json_mode) {
        try out.writeAll("[");
        for (all_presets, 0..) |id, i| {
            const p = synth.PatchConfig.fromPreset(id);
            if (i > 0) try out.writeAll(",");
            try out.print(
                "{{\"id\":{d},\"name\":\"{s}\",\"osc1\":\"{s}\",\"osc2\":\"{s}\",\"fm_depth\":{d:.2},\"cutoff_hz\":{d:.1},\"resonance\":{d:.2},\"lfo_target\":\"{s}\",\"delay_mix\":{d:.2}}}",
                .{
                    @backingInt(id),
                    id.name(),
                    @tagName(p.osc1_waveform),
                    @tagName(p.osc2_waveform),
                    p.fm_depth,
                    p.filter_cutoff,
                    p.filter_resonance,
                    @tagName(p.lfo_target),
                    p.delay_mix,
                },
            );
        }
        try out.writeAll("]\n");
    } else {
        try out.writeAll("Built-in Celestine Presets:\n");
        for (all_presets) |id| {
            const p = synth.PatchConfig.fromPreset(id);
            try out.print(
                "  [{d}] {s:<14} osc={s}+{s} fm={d:.2} fc={d:.0}Hz Q={d:.1} lfo={s} delay={d:.0}%\n",
                .{
                    @backingInt(id),
                    id.name(),
                    @tagName(p.osc1_waveform),
                    @tagName(p.osc2_waveform),
                    p.fm_depth,
                    p.filter_cutoff,
                    p.filter_resonance,
                    @tagName(p.lfo_target),
                    p.delay_mix * 100.0,
                },
            );
        }
    }
}

test "CLI MIDI chord parser" {
    var notes: [poly.MAX_VOICES]u8 = undefined;
    const count = parseMidiNotesList("60, 64, 67, 72, 200", &notes);
    try std.testing.expectEqual(@as(usize, 5), count);
    try std.testing.expectEqual(@as(u8, 60), notes[0]);
    try std.testing.expectEqual(@as(u8, 64), notes[1]);
    try std.testing.expectEqual(@as(u8, 67), notes[2]);
    try std.testing.expectEqual(@as(u8, 72), notes[3]);
    try std.testing.expectEqual(@as(u8, 127), notes[4]);
}

test {
    _ = @import("oscillator.zig");
    _ = @import("filter.zig");
    _ = @import("envelope.zig");
    _ = @import("lfo.zig");
    _ = @import("effects.zig");
    _ = @import("fft.zig");
    _ = @import("synth.zig");
    _ = @import("poly.zig");
    _ = @import("wav.zig");
    _ = @import("wasm.zig");
}
