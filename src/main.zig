const std = @import("std");
pub const osc = @import("oscillator.zig");
pub const filter = @import("filter.zig");
pub const envelope = @import("envelope.zig");
pub const fft = @import("fft.zig");
pub const synth = @import("synth.zig");
pub const wasm = @import("wasm.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    _ = allocator;

    var args = init.minimal.args.iterate();
    _ = args.next(); // skip prog name

    const cmd = args.next() orelse {
        printUsage();
        return;
    };

    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "help")) {
        printUsage();
        return;
    }

    if (std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "-v")) {
        std.debug.print("Celestine v0.1.0 (Audio DSP Modular Synthesizer & Oscilloscope)\n", .{});
        return;
    }

    if (std.mem.eql(u8, cmd, "render")) {
        const sec_str = args.next() orelse "1";
        const seconds = std.fmt.parseInt(usize, sec_str, 10) catch 1;
        try runRenderDemo(seconds);
        return;
    }

    printUsage();
}

fn printUsage() void {
    std.debug.print(
        \\Celestine: Audio DSP Modular Synthesizer & Oscilloscope
        \\Usage: celestine <command> [options]
        \\
        \\Commands:
        \\  render <seconds>    Render synthesized audio and inspect FFT spectrum
        \\  --version, -v       Print engine version
        \\  --help, -h          Print this help message
        \\
    , .{});
}

fn runRenderDemo(seconds: usize) !void {
    const sample_rate: f32 = 44100.0;
    var engine = synth.Synth.init(sample_rate);

    std.debug.print("Triggering Note A4 (MIDI 69, 440 Hz)...\n", .{});
    engine.noteOn(69, 0.9);

    var buffer: [1024]f32 = undefined;
    const total_blocks = (seconds * 44100) / buffer.len;

    var peak_amp: f32 = 0.0;
    for (0..total_blocks) |blk| {
        if (blk == total_blocks / 2) {
            engine.noteOff();
        }
        engine.render(&buffer);
        for (buffer) |s| {
            const a = @abs(s);
            if (a > peak_amp) peak_amp = a;
        }
    }

    var bins: [fft.NUM_BINS]f32 = undefined;
    engine.getSpectrum(&bins);

    var max_bin: usize = 0;
    var max_bin_val: f32 = -1.0;
    for (0..fft.NUM_BINS) |k| {
        if (bins[k] > max_bin_val) {
            max_bin_val = bins[k];
            max_bin = k;
        }
    }

    const peak_freq = @as(f32, @floatFromInt(max_bin)) * (sample_rate / @as(f32, @floatFromInt(fft.FFT_SIZE)));

    std.debug.print("Render complete: {d} seconds ({d} frames)\n", .{ seconds, total_blocks * buffer.len });
    std.debug.print("Peak Audio Amplitude: {d:.4}\n", .{peak_amp});
    std.debug.print("Spectral FFT Peak: Bin {d} (~{d:.1} Hz, Magnitude: {d:.4})\n", .{ max_bin, peak_freq, max_bin_val });
}

test {
    _ = @import("oscillator.zig");
    _ = @import("filter.zig");
    _ = @import("envelope.zig");
    _ = @import("fft.zig");
    _ = @import("synth.zig");
}
