const std = @import("std");
pub const osc = @import("oscillator.zig");
pub const filter = @import("filter.zig");
pub const envelope = @import("envelope.zig");
pub const fft = @import("fft.zig");

pub const Synth = struct {
    sample_rate: f32 = 44100.0,
    osc1: osc.Oscillator,
    osc2: osc.Oscillator,
    fm_depth: f32 = 0.0,

    amp_env: envelope.Adsr,
    filter_env: envelope.Adsr,
    svf: filter.StateVariableFilter,
    filter_env_amount: f32 = 2000.0,

    master_volume: f32 = 0.5,

    // Circular ring buffer for oscilloscope & FFT
    ring_buffer: [fft.FFT_SIZE]f32,
    ring_idx: usize = 0,
    analyzer: fft.FftAnalyzer,

    pub fn init(sample_rate: f32) Synth {
        var ring: [fft.FFT_SIZE]f32 = undefined;
        @memset(&ring, 0.0);

        var s = Synth{
            .sample_rate = sample_rate,
            .osc1 = osc.Oscillator.init(sample_rate),
            .osc2 = osc.Oscillator.init(sample_rate),
            .fm_depth = 0.0,
            .amp_env = envelope.Adsr.init(sample_rate),
            .filter_env = envelope.Adsr.init(sample_rate),
            .svf = filter.StateVariableFilter.init(sample_rate),
            .filter_env_amount = 2000.0,
            .master_volume = 0.5,
            .ring_buffer = ring,
            .ring_idx = 0,
            .analyzer = fft.FftAnalyzer.init(),
        };

        s.osc1.setWaveform(.saw);
        s.osc2.setWaveform(.square);
        s.svf.setCutoff(2000.0);
        s.svf.setResonance(1.5);
        return s;
    }

    pub fn midiNoteToFreq(note: u8) f32 {
        const n = @as(f32, @floatFromInt(note));
        return 440.0 * std.math.pow(f32, 2.0, (n - 69.0) / 12.0);
    }

    pub fn noteOn(self: *Synth, midi_note: u8, velocity: f32) void {
        const freq = midiNoteToFreq(midi_note);
        self.osc1.setFrequency(freq);
        self.osc2.setFrequency(freq * 1.005); // slight chorusing detune
        self.amp_env.gateOn(velocity);
        self.filter_env.gateOn(velocity);
    }

    pub fn noteOff(self: *Synth) void {
        self.amp_env.gateOff();
        self.filter_env.gateOff();
    }

    inline fn softClip(x: f32) f32 {
        if (x > 1.5) return 1.0;
        if (x < -1.5) return -1.0;
        return x - (x * x * x / 3.0);
    }

    pub fn render(self: *Synth, out_frames: []f32) void {
        for (out_frames) |*sample| {
            const mod_sample = self.osc2.nextSample(0.0) * self.fm_depth;
            const osc1_sample = self.osc1.nextSample(mod_sample);
            const raw_mix = (osc1_sample * 0.6) + (self.osc2.nextSample(0.0) * 0.4);

            const f_env = self.filter_env.nextSample();
            const current_cutoff = 800.0 + (f_env * self.filter_env_amount);
            self.svf.setCutoff(current_cutoff);

            const filtered = self.svf.process(raw_mix);
            const a_env = self.amp_env.nextSample();
            const out_val = softClip(filtered * a_env * self.master_volume);

            sample.* = out_val;

            // Push into oscilloscope ring buffer
            self.ring_buffer[self.ring_idx] = out_val;
            self.ring_idx = (self.ring_idx + 1) % fft.FFT_SIZE;
        }
    }

    pub fn getSpectrum(self: *const Synth, out_bins: *[fft.NUM_BINS]f32) void {
        // Linearize ring buffer before computing FFT
        var linear_buf: [fft.FFT_SIZE]f32 = undefined;
        for (0..fft.FFT_SIZE) |i| {
            const idx = (self.ring_idx + i) % fft.FFT_SIZE;
            linear_buf[i] = self.ring_buffer[idx];
        }
        self.analyzer.computeSpectrum(&linear_buf, out_bins);
    }
};

test "Synth render and note triggering" {
    var synth = Synth.init(44100.0);
    synth.noteOn(69, 0.8); // A4 (440 Hz)

    var buffer: [512]f32 = undefined;
    synth.render(&buffer);

    var has_sound = false;
    for (buffer) |s| {
        if (@abs(s) > 0.01) {
            has_sound = true;
            break;
        }
    }
    try std.testing.expect(has_sound);

    synth.noteOff();
    // Render until envelope reaches idle
    var iterations: usize = 0;
    while (synth.amp_env.state != .idle and iterations < 100) : (iterations += 1) {
        synth.render(&buffer);
    }
    try std.testing.expectEqual(envelope.AdsrState.idle, synth.amp_env.state);
    try std.testing.expectEqual(@as(f32, 0.0), synth.amp_env.current_value);
}
