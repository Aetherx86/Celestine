const std = @import("std");
pub const synth = @import("synth.zig");
pub const poly = @import("poly.zig");
pub const fft = @import("fft.zig");
pub const osc = @import("oscillator.zig");
pub const filter = @import("filter.zig");
pub const envelope = @import("envelope.zig");
pub const lfo = @import("lfo.zig");

var global_synth: poly.PolySynth = undefined;
var initialized: bool = false;
var audio_buffer: [2048]f32 = @splat(0.0);
var spectrum_buffer: [fft.NUM_BINS]f32 = @splat(0.0);

fn ensureInit() void {
    if (!initialized) {
        celestine_init(44100.0);
    }
}

inline fn safeEnumIndex(val: f32, max_inclusive: u32) u32 {
    if (!std.math.isFinite(val) or val <= 0.0) return 0;
    const max_f: f32 = @floatFromInt(max_inclusive);
    return @intFromFloat(std.math.clamp(val, 0.0, max_f));
}

pub export fn celestine_init(sample_rate: f32) void {
    global_synth.initInPlace(sample_rate);
    // Default to mono voice behavior for 100% backward compatibility with legacy note_on/note_off callers;
    // poly_note_on or param_id 28 enables 8-voice polyphony.
    global_synth.setPolyMode(false);
    @memset(&audio_buffer, 0.0);
    @memset(&spectrum_buffer, 0.0);
    initialized = true;
}

pub export fn celestine_note_on(midi_note: u8, velocity: f32) void {
    ensureInit();
    global_synth.noteOn(midi_note, velocity);
}

pub export fn celestine_note_off() void {
    ensureInit();
    global_synth.allNotesOff();
}

pub export fn celestine_poly_note_on(midi_note: u8, velocity: f32) void {
    ensureInit();
    global_synth.setPolyMode(true);
    global_synth.noteOn(midi_note, velocity);
}

pub export fn celestine_poly_note_off(midi_note: u8) void {
    ensureInit();
    global_synth.noteOff(midi_note);
}

pub export fn celestine_all_notes_off() void {
    ensureInit();
    global_synth.allNotesOff();
}

pub export fn celestine_load_preset(preset_id: u32) void {
    ensureInit();
    global_synth.loadPreset(synth.PresetId.fromU32(preset_id));
}

pub export fn celestine_set_param(param_id: u32, value: f32) void {
    ensureInit();
    if (!std.math.isFinite(value)) return;

    switch (param_id) {
        // Legacy parameter IDs 0..6 preserved with identical semantics (now fully sanitized)
        0 => global_synth.setMasterVolume(value),
        1 => global_synth.setOsc1Waveform(osc.Waveform.fromU32(safeEnumIndex(value, 4))),
        2 => global_synth.setOsc2Waveform(osc.Waveform.fromU32(safeEnumIndex(value, 4))),
        3 => global_synth.setFmDepth(value),
        4 => global_synth.setFilterCutoff(value),
        5 => global_synth.setFilterResonance(value),
        6 => global_synth.setFilterType(filter.FilterType.fromU32(safeEnumIndex(value, 5))),

        // Extended modular synth parameter IDs 7..31
        7 => global_synth.setOscMix(value),
        8 => global_synth.setOsc2DetuneCents(value),
        9 => global_synth.setPulseWidth(value),
        10 => global_synth.setFilterEnvAmount(value),
        11 => global_synth.setAmpAdsr(value, global_synth.patch.amp_decay, global_synth.patch.amp_sustain, global_synth.patch.amp_release),
        12 => global_synth.setAmpAdsr(global_synth.patch.amp_attack, value, global_synth.patch.amp_sustain, global_synth.patch.amp_release),
        13 => global_synth.setAmpAdsr(global_synth.patch.amp_attack, global_synth.patch.amp_decay, value, global_synth.patch.amp_release),
        14 => global_synth.setAmpAdsr(global_synth.patch.amp_attack, global_synth.patch.amp_decay, global_synth.patch.amp_sustain, value),
        15 => global_synth.setFilterAdsr(value, global_synth.patch.filter_decay, global_synth.patch.filter_sustain, global_synth.patch.filter_release),
        16 => global_synth.setFilterAdsr(global_synth.patch.filter_attack, value, global_synth.patch.filter_sustain, global_synth.patch.filter_release),
        17 => global_synth.setFilterAdsr(global_synth.patch.filter_attack, global_synth.patch.filter_decay, value, global_synth.patch.filter_release),
        18 => global_synth.setFilterAdsr(global_synth.patch.filter_attack, global_synth.patch.filter_decay, global_synth.patch.filter_sustain, value),
        19 => global_synth.lfo.setRate(value),
        20 => global_synth.lfo.setDepth(value),
        21 => global_synth.lfo.setWaveform(lfo.LfoWaveform.fromU32(safeEnumIndex(value, 5))),
        22 => global_synth.lfo.setTarget(lfo.LfoTarget.fromU32(safeEnumIndex(value, 5))),
        23 => global_synth.setDrive(value),
        24 => global_synth.setGlide(value),
        25 => global_synth.delay.setDelayMs(value),
        26 => global_synth.delay.setFeedback(value),
        27 => global_synth.delay.setWetMix(value),
        28 => global_synth.setPolyMode(value >= 0.5),
        29 => global_synth.setEnvCurve(envelope.EnvelopeCurve.fromU32(safeEnumIndex(value, 1))),
        30 => global_synth.analyzer.setWindow(fft.WindowType.fromU32(safeEnumIndex(value, 3))),
        31 => global_synth.setPitchBend(value),
        else => {},
    }
}

pub export fn celestine_render(frames: u32) [*]f32 {
    ensureInit();
    const count: usize = if (frames > audio_buffer.len) audio_buffer.len else frames;
    global_synth.render(audio_buffer[0..count]);
    return &audio_buffer;
}

pub export fn celestine_get_spectrum() [*]f32 {
    ensureInit();
    global_synth.getSpectrum(&spectrum_buffer);
    return &spectrum_buffer;
}

pub export fn celestine_get_spectrum_size() u32 {
    return @as(u32, @intCast(fft.NUM_BINS));
}

pub export fn celestine_get_buffer_ptr() [*]f32 {
    return &audio_buffer;
}

pub export fn celestine_get_buffer_size() u32 {
    return @as(u32, @intCast(audio_buffer.len));
}

pub export fn celestine_get_active_voices() u32 {
    ensureInit();
    return @as(u32, @intCast(global_synth.activeVoiceCount()));
}

pub export fn celestine_get_peak_freq() f32 {
    ensureInit();
    return global_synth.getSpectralMetrics().peak_freq_hz;
}

pub export fn celestine_get_spectral_centroid() f32 {
    ensureInit();
    return global_synth.getSpectralMetrics().centroid_hz;
}

pub export fn celestine_get_rms() f32 {
    ensureInit();
    return global_synth.getSpectralMetrics().rms;
}

test "WASM exports backward compatibility and adversarial parameter safety" {
    celestine_init(44100.0);
    try std.testing.expectEqual(@as(u32, 512), celestine_get_spectrum_size());
    try std.testing.expectEqual(@as(u32, 2048), celestine_get_buffer_size());

    // Adversarial inputs must not trap or corrupt DSP state
    celestine_set_param(0, std.math.nan(f32));
    celestine_set_param(1, -99.0);
    celestine_set_param(2, 9999.0);
    celestine_set_param(4, std.math.inf(f32));
    celestine_set_param(6, -5.0);
    celestine_set_param(999, 42.0);

    // Pure sine on osc1 via legacy param IDs
    celestine_set_param(0, 0.8);
    celestine_set_param(1, 0.0); // sine
    celestine_set_param(7, 0.0); // osc1 only
    celestine_set_param(4, 10000.0); // high cutoff
    celestine_set_param(10, 0.0); // no filter env
    celestine_note_on(69, 0.9); // A4 = 440 Hz

    const buf_ptr = celestine_render(1024);
    _ = celestine_render(1024);

    for (0..1024) |i| {
        try std.testing.expect(std.math.isFinite(buf_ptr[i]));
        try std.testing.expect(buf_ptr[i] >= -1.01 and buf_ptr[i] <= 1.01);
    }

    const peak_hz = celestine_get_peak_freq();
    try std.testing.expectApproxEqAbs(@as(f32, 440.0), peak_hz, 2.0);
    try std.testing.expect(celestine_get_rms() > 0.1);

    const spec_ptr = celestine_get_spectrum();
    try std.testing.expect(spec_ptr[10] > 0.1);

    // Release legacy mono note and verify it returns to idle
    celestine_note_off();
    for (0..15) |_| {
        _ = celestine_render(2048);
    }
    try std.testing.expectEqual(@as(u32, 0), celestine_get_active_voices());

    // Polyphonic exports
    celestine_load_preset(1); // warm_pad
    celestine_poly_note_on(60, 0.8);
    celestine_poly_note_on(64, 0.8);
    celestine_poly_note_on(67, 0.8);
    try std.testing.expectEqual(@as(u32, 3), celestine_get_active_voices());

    _ = celestine_render(512);
    celestine_poly_note_off(64);
    celestine_all_notes_off();
    // Render release tail
    for (0..40) |_| {
        _ = celestine_render(2048);
    }
    try std.testing.expectEqual(@as(u32, 0), celestine_get_active_voices());
}
