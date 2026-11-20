const std = @import("std");
pub const osc = @import("oscillator.zig");
pub const filter = @import("filter.zig");
pub const envelope = @import("envelope.zig");
pub const fft = @import("fft.zig");
pub const lfo_mod = @import("lfo.zig");
pub const effects = @import("effects.zig");

pub const PresetId = enum(u32) {
    init_saw = 0,
    warm_pad = 1,
    acid_bass = 2,
    fm_bell = 3,
    pluck_lead = 4,
    ambient_chord = 5,

    pub fn fromU32(val: u32) PresetId {
        return switch (val) {
            0 => .init_saw,
            1 => .warm_pad,
            2 => .acid_bass,
            3 => .fm_bell,
            4 => .pluck_lead,
            5 => .ambient_chord,
            else => .init_saw,
        };
    }

    pub fn name(self: PresetId) []const u8 {
        return switch (self) {
            .init_saw => "init_saw",
            .warm_pad => "warm_pad",
            .acid_bass => "acid_bass",
            .fm_bell => "fm_bell",
            .pluck_lead => "pluck_lead",
            .ambient_chord => "ambient_chord",
        };
    }

    pub fn fromName(str: []const u8) ?PresetId {
        if (std.mem.eql(u8, str, "init_saw") or std.mem.eql(u8, str, "init")) return .init_saw;
        if (std.mem.eql(u8, str, "warm_pad") or std.mem.eql(u8, str, "pad")) return .warm_pad;
        if (std.mem.eql(u8, str, "acid_bass") or std.mem.eql(u8, str, "bass")) return .acid_bass;
        if (std.mem.eql(u8, str, "fm_bell") or std.mem.eql(u8, str, "bell")) return .fm_bell;
        if (std.mem.eql(u8, str, "pluck_lead") or std.mem.eql(u8, str, "pluck")) return .pluck_lead;
        if (std.mem.eql(u8, str, "ambient_chord") or std.mem.eql(u8, str, "ambient")) return .ambient_chord;
        return null;
    }
};

pub const PatchConfig = struct {
    osc1_waveform: osc.Waveform = .saw,
    osc2_waveform: osc.Waveform = .square,
    osc_mix: f32 = 0.4, // 0.0 = osc1 only, 1.0 = osc2 only
    osc2_detune_cents: f32 = 8.634, // ratio ~1.005
    pulse_width: f32 = 0.5,
    fm_depth: f32 = 0.0,

    filter_type: filter.FilterType = .lowpass,
    filter_cutoff: f32 = 800.0,
    filter_resonance: f32 = 1.5,
    filter_env_amount: f32 = 2000.0,

    amp_attack: f32 = 0.01,
    amp_decay: f32 = 0.1,
    amp_sustain: f32 = 0.7,
    amp_release: f32 = 0.2,

    filter_attack: f32 = 0.01,
    filter_decay: f32 = 0.1,
    filter_sustain: f32 = 0.7,
    filter_release: f32 = 0.2,
    env_curve: envelope.EnvelopeCurve = .linear,

    lfo_waveform: lfo_mod.LfoWaveform = .sine,
    lfo_target: lfo_mod.LfoTarget = .none,
    lfo_rate_hz: f32 = 2.0,
    lfo_depth: f32 = 0.0,

    drive: f32 = 1.0,
    glide_sec: f32 = 0.0,
    master_volume: f32 = 0.5,

    delay_ms: f32 = 25.0,
    delay_feedback: f32 = 0.25,
    delay_damping: f32 = 0.3,
    delay_mix: f32 = 0.0,
    chorus_rate_hz: f32 = 0.8,
    chorus_depth_ms: f32 = 0.0,

    pub fn detuneRatio(self: *const PatchConfig) f32 {
        return centsToRatio(self.osc2_detune_cents);
    }

    pub fn fromPreset(preset: PresetId) PatchConfig {
        return switch (preset) {
            .init_saw => .{},
            .warm_pad => .{
                .osc1_waveform = .saw,
                .osc2_waveform = .triangle,
                .osc_mix = 0.45,
                .osc2_detune_cents = 14.0,
                .pulse_width = 0.5,
                .fm_depth = 0.05,
                .filter_type = .lowpass,
                .filter_cutoff = 650.0,
                .filter_resonance = 1.8,
                .filter_env_amount = 1600.0,
                .amp_attack = 0.25,
                .amp_decay = 0.4,
                .amp_sustain = 0.75,
                .amp_release = 0.65,
                .filter_attack = 0.35,
                .filter_decay = 0.5,
                .filter_sustain = 0.5,
                .filter_release = 0.6,
                .env_curve = .exponential,
                .lfo_waveform = .sine,
                .lfo_target = .filter_cutoff,
                .lfo_rate_hz = 0.45,
                .lfo_depth = 0.25,
                .drive = 1.15,
                .glide_sec = 0.04,
                .master_volume = 0.55,
                .delay_ms = 22.0,
                .delay_feedback = 0.32,
                .delay_damping = 0.45,
                .delay_mix = 0.30,
                .chorus_rate_hz = 0.65,
                .chorus_depth_ms = 2.8,
            },
            .acid_bass => .{
                .osc1_waveform = .saw,
                .osc2_waveform = .square,
                .osc_mix = 0.25,
                .osc2_detune_cents = -1200.0, // sub-octave
                .pulse_width = 0.35,
                .fm_depth = 0.0,
                .filter_type = .lowpass,
                .filter_cutoff = 260.0,
                .filter_resonance = 6.5,
                .filter_env_amount = 3800.0,
                .amp_attack = 0.004,
                .amp_decay = 0.18,
                .amp_sustain = 0.35,
                .amp_release = 0.09,
                .filter_attack = 0.003,
                .filter_decay = 0.14,
                .filter_sustain = 0.1,
                .filter_release = 0.08,
                .env_curve = .exponential,
                .lfo_waveform = .triangle,
                .lfo_target = .pulse_width,
                .lfo_rate_hz = 1.8,
                .lfo_depth = 0.2,
                .drive = 2.2,
                .glide_sec = 0.03,
                .master_volume = 0.55,
                .delay_ms = 18.0,
                .delay_feedback = 0.15,
                .delay_damping = 0.5,
                .delay_mix = 0.08,
                .chorus_rate_hz = 0.5,
                .chorus_depth_ms = 0.0,
            },
            .fm_bell => .{
                .osc1_waveform = .sine,
                .osc2_waveform = .sine,
                .osc_mix = 0.0, // pure carrier output modulated by osc2
                .osc2_detune_cents = 1901.955, // 3:1 harmonic ratio (octave + fifth)
                .pulse_width = 0.5,
                .fm_depth = 0.65,
                .filter_type = .lowpass,
                .filter_cutoff = 4500.0,
                .filter_resonance = 0.9,
                .filter_env_amount = 4000.0,
                .amp_attack = 0.002,
                .amp_decay = 0.75,
                .amp_sustain = 0.0,
                .amp_release = 0.5,
                .filter_attack = 0.002,
                .filter_decay = 0.45,
                .filter_sustain = 0.05,
                .filter_release = 0.35,
                .env_curve = .exponential,
                .lfo_waveform = .sine,
                .lfo_target = .fm_depth,
                .lfo_rate_hz = 4.5,
                .lfo_depth = 0.15,
                .drive = 1.0,
                .glide_sec = 0.0,
                .master_volume = 0.55,
                .delay_ms = 48.0,
                .delay_feedback = 0.45,
                .delay_damping = 0.35,
                .delay_mix = 0.28,
                .chorus_rate_hz = 0.4,
                .chorus_depth_ms = 0.8,
            },
            .pluck_lead => .{
                .osc1_waveform = .square,
                .osc2_waveform = .saw,
                .osc_mix = 0.5,
                .osc2_detune_cents = 7.0,
                .pulse_width = 0.28,
                .fm_depth = 0.08,
                .filter_type = .lowpass,
                .filter_cutoff = 550.0,
                .filter_resonance = 2.6,
                .filter_env_amount = 4500.0,
                .amp_attack = 0.003,
                .amp_decay = 0.22,
                .amp_sustain = 0.15,
                .amp_release = 0.18,
                .filter_attack = 0.002,
                .filter_decay = 0.15,
                .filter_sustain = 0.1,
                .filter_release = 0.15,
                .env_curve = .exponential,
                .lfo_waveform = .sine,
                .lfo_target = .pitch,
                .lfo_rate_hz = 5.5,
                .lfo_depth = 0.08,
                .drive = 1.35,
                .glide_sec = 0.015,
                .master_volume = 0.55,
                .delay_ms = 65.0,
                .delay_feedback = 0.38,
                .delay_damping = 0.35,
                .delay_mix = 0.22,
                .chorus_rate_hz = 1.1,
                .chorus_depth_ms = 1.2,
            },
            .ambient_chord => .{
                .osc1_waveform = .triangle,
                .osc2_waveform = .sine,
                .osc_mix = 0.4,
                .osc2_detune_cents = 1205.0, // octave + gentle chorus detune
                .pulse_width = 0.5,
                .fm_depth = 0.12,
                .filter_type = .lowpass,
                .filter_cutoff = 1100.0,
                .filter_resonance = 1.2,
                .filter_env_amount = 1400.0,
                .amp_attack = 0.18,
                .amp_decay = 0.35,
                .amp_sustain = 0.8,
                .amp_release = 0.75,
                .filter_attack = 0.22,
                .filter_decay = 0.4,
                .filter_sustain = 0.6,
                .filter_release = 0.65,
                .env_curve = .exponential,
                .lfo_waveform = .sine,
                .lfo_target = .amplitude,
                .lfo_rate_hz = 1.2,
                .lfo_depth = 0.15,
                .drive = 1.0,
                .glide_sec = 0.0,
                .master_volume = 0.55,
                .delay_ms = 36.0,
                .delay_feedback = 0.42,
                .delay_damping = 0.4,
                .delay_mix = 0.35,
                .chorus_rate_hz = 0.55,
                .chorus_depth_ms = 3.2,
            },
        };
    }
};

pub inline fn centsToRatio(cents: f32) f32 {
    if (!std.math.isFinite(cents)) return 1.0;
    const clamped = std.math.clamp(cents, -4800.0, 4800.0);
    return std.math.pow(f32, 2.0, clamped / 1200.0);
}

pub inline fn midiNoteToFreq(note: u8) f32 {
    const n = @as(f32, @floatFromInt(note));
    return 440.0 * std.math.pow(f32, 2.0, (n - 69.0) / 12.0);
}

/// C1-continuous cubic soft clipper with unity gain at 0 and smooth saturation at +/-1.0.
pub inline fn softClip(x: f32) f32 {
    if (!std.math.isFinite(x)) return 0.0;
    if (x >= 1.5) return 1.0;
    if (x <= -1.5) return -1.0;
    return x - ((4.0 / 27.0) * x * x * x);
}

pub const Synth = struct {
    sample_rate: f32 = 44100.0,
    osc1: osc.Oscillator,
    osc2: osc.Oscillator,
    fm_depth: f32 = 0.0,
    osc_mix: f32 = 0.4,
    osc2_detune_ratio: f32 = 1.005,

    amp_env: envelope.Adsr,
    filter_env: envelope.Adsr,
    svf: filter.StateVariableFilter,
    filter_env_amount: f32 = 2000.0,

    lfo: lfo_mod.Lfo,
    delay: effects.ChorusDelay,

    drive: f32 = 1.0,
    glide_sec: f32 = 0.0,
    pitch_bend_semitones: f32 = 0.0,
    target_freq: f32 = 440.0,
    current_freq: f32 = 440.0,
    has_triggered: bool = false,

    master_volume: f32 = 0.5,

    // Circular ring buffer for oscilloscope & FFT
    ring_buffer: [fft.FFT_SIZE]f32,
    ring_idx: usize = 0,
    analyzer: fft.FftAnalyzer,

    pub fn init(sample_rate: f32) Synth {
        var s: Synth = undefined;
        s.initInPlace(sample_rate);
        return s;
    }

    pub fn initInPlace(self: *Synth, sample_rate: f32) void {
        const sr = if (std.math.isFinite(sample_rate) and sample_rate >= 1.0) sample_rate else 44100.0;
        self.sample_rate = sr;
        self.osc1 = osc.Oscillator.init(sr);
        self.osc2 = osc.Oscillator.init(sr);
        self.fm_depth = 0.0;
        self.osc_mix = 0.4;
        self.osc2_detune_ratio = 1.005;
        self.amp_env = envelope.Adsr.init(sr);
        self.filter_env = envelope.Adsr.init(sr);
        self.svf = filter.StateVariableFilter.init(sr);
        self.filter_env_amount = 2000.0;
        self.lfo = lfo_mod.Lfo.init(sr);
        self.delay.initInPlace(sr);
        self.drive = 1.0;
        self.glide_sec = 0.0;
        self.pitch_bend_semitones = 0.0;
        self.target_freq = 440.0;
        self.current_freq = 440.0;
        self.has_triggered = false;
        self.master_volume = 0.5;
        @memset(&self.ring_buffer, 0.0);
        self.ring_idx = 0;
        self.analyzer.initInPlace(.hann);

        self.osc1.setWaveform(.saw);
        self.osc2.setWaveform(.square);
        self.svf.setCutoff(800.0);
        self.svf.setResonance(1.5);
    }

    pub fn midiNoteToFreq(note: u8) f32 {
        const n = @as(f32, @floatFromInt(note));
        return 440.0 * std.math.pow(f32, 2.0, (n - 69.0) / 12.0);
    }

    pub fn applyPatch(self: *Synth, patch: PatchConfig) void {
        self.osc1.setWaveform(patch.osc1_waveform);
        self.osc2.setWaveform(patch.osc2_waveform);
        self.osc1.setPulseWidth(patch.pulse_width);
        self.osc2.setPulseWidth(patch.pulse_width);
        self.osc_mix = std.math.clamp(patch.osc_mix, 0.0, 1.0);
        self.osc2_detune_ratio = patch.detuneRatio();
        self.fm_depth = std.math.clamp(patch.fm_depth, 0.0, 10.0);

        self.svf.setFilterType(patch.filter_type);
        self.svf.setCutoff(patch.filter_cutoff);
        self.svf.setResonance(patch.filter_resonance);
        self.filter_env_amount = patch.filter_env_amount;

        self.amp_env.setCurve(patch.env_curve);
        self.amp_env.setParameters(patch.amp_attack, patch.amp_decay, patch.amp_sustain, patch.amp_release);
        self.filter_env.setCurve(patch.env_curve);
        self.filter_env.setParameters(patch.filter_attack, patch.filter_decay, patch.filter_sustain, patch.filter_release);

        self.lfo.setWaveform(patch.lfo_waveform);
        self.lfo.setTarget(patch.lfo_target);
        self.lfo.setRate(patch.lfo_rate_hz);
        self.lfo.setDepth(patch.lfo_depth);

        self.drive = std.math.clamp(patch.drive, 0.5, 8.0);
        self.glide_sec = std.math.clamp(patch.glide_sec, 0.0, 2.0);
        self.master_volume = std.math.clamp(patch.master_volume, 0.0, 1.0);

        self.delay.setDelayMs(patch.delay_ms);
        self.delay.setFeedback(patch.delay_feedback);
        self.delay.setDamping(patch.delay_damping);
        self.delay.setWetMix(patch.delay_mix);
        self.delay.setChorusMod(patch.chorus_rate_hz, patch.chorus_depth_ms);
    }

    pub fn loadPreset(self: *Synth, preset: PresetId) void {
        self.applyPatch(PatchConfig.fromPreset(preset));
    }

    pub fn setOsc2Detune(self: *Synth, semitones: f32, cents: f32) void {
        const total_cents = (semitones * 100.0) + cents;
        self.osc2_detune_ratio = centsToRatio(total_cents);
    }

    pub fn noteOn(self: *Synth, midi_note: u8, velocity: f32) void {
        const freq = Synth.midiNoteToFreq(midi_note);
        self.target_freq = freq;
        if (!self.has_triggered or self.glide_sec <= 0.0005) {
            self.current_freq = freq;
            self.has_triggered = true;
        }
        self.osc1.setFrequency(self.current_freq);
        self.osc2.setFrequency(self.current_freq * self.osc2_detune_ratio);
        self.amp_env.gateOn(velocity);
        self.filter_env.gateOn(velocity);
    }

    pub fn noteOff(self: *Synth) void {
        self.amp_env.gateOff();
        self.filter_env.gateOff();
    }

    pub fn render(self: *Synth, out_frames: []f32) void {
        const sr = if (self.sample_rate >= 1.0) self.sample_rate else 44100.0;
        const glide_coef: f32 = if (self.glide_sec > 0.0005)
            @exp(-1.0 / (self.glide_sec * sr))
        else
            0.0;
        const bend_ratio = if (self.pitch_bend_semitones != 0.0)
            centsToRatio(self.pitch_bend_semitones * 100.0)
        else
            1.0;
        const mix = std.math.clamp(self.osc_mix, 0.0, 1.0);
        const osc1_gain = 1.0 - mix;
        const osc2_gain = mix;
        const drive = std.math.clamp(self.drive, 0.5, 8.0);
        const vol = std.math.clamp(self.master_volume, 0.0, 1.0);

        for (out_frames) |*sample| {
            // Exponential portamento / glide
            if (glide_coef > 0.0) {
                self.current_freq = self.target_freq + ((self.current_freq - self.target_freq) * glide_coef);
            } else {
                self.current_freq = self.target_freq;
            }

            const lfo_val = self.lfo.nextSample();

            // Apply LFO pitch vibrato (+/- 2 semitones at full depth) and pitch bend
            const pitch_lfo_ratio: f32 = if (self.lfo.target == .pitch and lfo_val != 0.0)
                centsToRatio(lfo_val * 200.0)
            else
                1.0;
            const eff_freq = self.current_freq * bend_ratio * pitch_lfo_ratio;
            self.osc1.setFrequency(eff_freq);
            self.osc2.setFrequency(eff_freq * self.osc2_detune_ratio);

            const pw_mod: f32 = if (self.lfo.target == .pulse_width) lfo_val * 0.4 else 0.0;
            const fm_mod_depth: f32 = if (self.lfo.target == .fm_depth)
                @max(0.0, self.fm_depth * (1.0 + lfo_val))
            else
                self.fm_depth;

            // Sample osc2 ONCE per frame (fixes previous double-stepping octave bug)
            const osc2_sample = self.osc2.nextSampleWithPwm(0.0, pw_mod);
            const osc1_sample = self.osc1.nextSampleWithPwm(osc2_sample * fm_mod_depth, pw_mod);
            const raw_mix = (osc1_sample * osc1_gain) + (osc2_sample * osc2_gain);
            const driven = if (drive > 1.001) softClip(raw_mix * drive) else raw_mix;

            // Modulate filter cutoff without overwriting svf.cutoff base value
            const f_env = self.filter_env.nextSample();
            const cutoff_lfo: f32 = if (self.lfo.target == .filter_cutoff)
                lfo_val * @max(self.svf.cutoff * 0.8, 1200.0)
            else
                0.0;
            const current_cutoff = self.svf.cutoff + (f_env * self.filter_env_amount) + cutoff_lfo;
            const filtered = self.svf.processModulated(driven, current_cutoff);

            const a_env = self.amp_env.nextSample();
            const tremolo_gain: f32 = if (self.lfo.target == .amplitude)
                std.math.clamp(1.0 + (lfo_val * 0.5), 0.0, 1.5)
            else
                1.0;

            const dry_voice = filtered * a_env * tremolo_gain;
            const effected = self.delay.process(dry_voice);
            const out_val = softClip(effected * vol);

            sample.* = out_val;

            // Push into oscilloscope ring buffer
            self.ring_buffer[self.ring_idx] = out_val;
            self.ring_idx = (self.ring_idx + 1) % fft.FFT_SIZE;
        }
    }

    pub fn getSpectrum(self: *const Synth, out_bins: *[fft.NUM_BINS]f32) void {
        var linear_buf: [fft.FFT_SIZE]f32 = undefined;
        self.linearizeRing(&linear_buf);
        self.analyzer.computeSpectrum(&linear_buf, out_bins);
    }

    pub fn getSpectralMetrics(self: *const Synth) fft.SpectralMetrics {
        var linear_buf: [fft.FFT_SIZE]f32 = undefined;
        self.linearizeRing(&linear_buf);
        return self.analyzer.analyze(&linear_buf, self.sample_rate);
    }

    fn linearizeRing(self: *const Synth, out: *[fft.FFT_SIZE]f32) void {
        for (0..fft.FFT_SIZE) |i| {
            const idx = (self.ring_idx + i) % fft.FFT_SIZE;
            out[i] = self.ring_buffer[idx];
        }
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
    var iterations: usize = 0;
    while (synth.amp_env.state != .idle and iterations < 100) : (iterations += 1) {
        synth.render(&buffer);
    }
    try std.testing.expectEqual(envelope.AdsrState.idle, synth.amp_env.state);
    try std.testing.expectEqual(@as(f32, 0.0), synth.amp_env.current_value);
}

test "Synth osc2 single-step frequency accuracy and base filter cutoff tracking" {
    var synth = Synth.init(44100.0);
    // Isolate osc2 as a pure 440 Hz sine (no detune, osc_mix = 1.0)
    synth.osc1.setWaveform(.sine);
    synth.osc2.setWaveform(.sine);
    synth.osc_mix = 1.0;
    synth.osc2_detune_ratio = 1.0;
    synth.filter_env_amount = 0.0;
    synth.svf.setCutoff(12000.0);
    synth.svf.setResonance(0.7071);
    synth.amp_env.setParameters(0.001, 0.01, 1.0, 0.1);

    synth.noteOn(69, 1.0); // 440 Hz
    var buf: [1024]f32 = undefined;
    // Warm up past attack
    synth.render(&buf);
    synth.render(&buf);

    const metrics = synth.getSpectralMetrics();
    // Previously osc2 ran at 2x (880 Hz); now it must accurately peak at 440 Hz
    try std.testing.expectApproxEqAbs(@as(f32, 440.0), metrics.peak_freq_hz, 2.0);
    // Base cutoff must remain 12000 Hz, never overwritten by render()
    try std.testing.expectApproxEqAbs(@as(f32, 12000.0), synth.svf.cutoff, 1.0e-3);

    // Lowering base cutoff must measurably reduce spectral centroid of a bright saw wave
    synth.osc1.setWaveform(.saw);
    synth.osc_mix = 0.0;
    synth.svf.setCutoff(6000.0);
    synth.render(&buf);
    synth.render(&buf);
    const bright_centroid = synth.getSpectralMetrics().centroid_hz;

    synth.svf.setCutoff(500.0);
    synth.render(&buf);
    synth.render(&buf);
    const dark_centroid = synth.getSpectralMetrics().centroid_hz;

    try std.testing.expect(dark_centroid < bright_centroid * 0.5);
}

test "Synth presets and C1 softClip continuity" {
    // Check C1 softClip continuity at boundaries +/-1.5
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), softClip(1.4999), 1.0e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), softClip(1.5), 1.0e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), softClip(-1.4999), 1.0e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), softClip(0.0), 1.0e-6);

    const presets = [_]PresetId{ .init_saw, .warm_pad, .acid_bass, .fm_bell, .pluck_lead, .ambient_chord };
    var buf: [512]f32 = undefined;
    for (presets) |p| {
        var synth = Synth.init(44100.0);
        synth.loadPreset(p);
        synth.noteOn(60, 0.85);
        var peak: f32 = 0.0;
        for (0..8) |_| {
            synth.render(&buf);
            for (buf) |s| {
                try std.testing.expect(std.math.isFinite(s));
                try std.testing.expect(s >= -1.001 and s <= 1.001);
                if (@abs(s) > peak) peak = @abs(s);
            }
        }
        try std.testing.expect(peak > 0.02);
    }
}
