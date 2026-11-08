const std = @import("std");
pub const synth = @import("synth.zig");
pub const fft = @import("fft.zig");
pub const osc = @import("oscillator.zig");
pub const filter = @import("filter.zig");

var global_synth: synth.Synth = undefined;
var audio_buffer: [2048]f32 = undefined;
var spectrum_buffer: [fft.NUM_BINS]f32 = undefined;

pub export fn celestine_init(sample_rate: f32) void {
    global_synth = synth.Synth.init(sample_rate);
    @memset(&audio_buffer, 0.0);
    @memset(&spectrum_buffer, 0.0);
}

pub export fn celestine_note_on(midi_note: u8, velocity: f32) void {
    global_synth.noteOn(midi_note, velocity);
}

pub export fn celestine_note_off() void {
    global_synth.noteOff();
}

pub export fn celestine_set_param(param_id: u32, value: f32) void {
    switch (param_id) {
        0 => global_synth.master_volume = std.math.clamp(value, 0.0, 1.0),
        1 => global_synth.osc1.setWaveform(@enumFromInt(@as(u32, @intFromFloat(value)))),
        2 => global_synth.osc2.setWaveform(@enumFromInt(@as(u32, @intFromFloat(value)))),
        3 => global_synth.fm_depth = value,
        4 => global_synth.svf.setCutoff(value),
        5 => global_synth.svf.setResonance(value),
        6 => global_synth.svf.filter_type = @enumFromInt(@as(u32, @intFromFloat(value))),
        else => {},
    }
}

pub export fn celestine_render(frames: u32) [*]f32 {
    const count: usize = if (frames > audio_buffer.len) audio_buffer.len else frames;
    global_synth.render(audio_buffer[0..count]);
    return &audio_buffer;
}

pub export fn celestine_get_spectrum() [*]f32 {
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
