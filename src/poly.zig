const std = @import("std");
pub const osc = @import("oscillator.zig");
pub const filter = @import("filter.zig");
pub const envelope = @import("envelope.zig");
pub const fft = @import("fft.zig");
pub const lfo_mod = @import("lfo.zig");
pub const effects = @import("effects.zig");
pub const synth_mod = @import("synth.zig");

pub const MAX_VOICES: usize = 8;

pub const Voice = struct {
    osc1: osc.Oscillator,
    osc2: osc.Oscillator,
    amp_env: envelope.Adsr,
    filter_env: envelope.Adsr,
    svf: filter.StateVariableFilter,

    midi_note: u8 = 0,
    velocity: f32 = 0.0,
    held: bool = false,
    sustained: bool = false,
    age: u64 = 0,
    target_freq: f32 = 440.0,
    current_freq: f32 = 440.0,
    has_triggered: bool = false,

    pub fn init(sample_rate: f32, patch: synth_mod.PatchConfig) Voice {
        var v = Voice{
            .osc1 = osc.Oscillator.init(sample_rate),
            .osc2 = osc.Oscillator.init(sample_rate),
            .amp_env = envelope.Adsr.init(sample_rate),
            .filter_env = envelope.Adsr.init(sample_rate),
            .svf = filter.StateVariableFilter.init(sample_rate),
        };
        v.syncPatch(patch);
        return v;
    }

    pub fn syncPatch(self: *Voice, patch: synth_mod.PatchConfig) void {
        self.osc1.setWaveform(patch.osc1_waveform);
        self.osc2.setWaveform(patch.osc2_waveform);
        self.osc1.setPulseWidth(patch.pulse_width);
        self.osc2.setPulseWidth(patch.pulse_width);

        self.svf.setFilterType(patch.filter_type);
        self.svf.setCutoff(patch.filter_cutoff);
        self.svf.setResonance(patch.filter_resonance);

        self.amp_env.setCurve(patch.env_curve);
        self.amp_env.setParameters(patch.amp_attack, patch.amp_decay, patch.amp_sustain, patch.amp_release);
        self.filter_env.setCurve(patch.env_curve);
        self.filter_env.setParameters(patch.filter_attack, patch.filter_decay, patch.filter_sustain, patch.filter_release);
    }

    pub fn isActive(self: *const Voice) bool {
        return self.amp_env.isActive();
    }

    pub fn trigger(self: *Voice, midi_note: u8, velocity: f32, age: u64, patch: synth_mod.PatchConfig, allow_glide: bool) void {
        const freq = synth_mod.midiNoteToFreq(midi_note);
        self.midi_note = midi_note;
        self.velocity = std.math.clamp(if (std.math.isFinite(velocity)) velocity else 0.8, 0.0, 1.0);
        self.held = true;
        self.sustained = false;
        self.age = age;
        self.target_freq = freq;

        if (!allow_glide or !self.has_triggered or patch.glide_sec <= 0.0005) {
            self.current_freq = freq;
            self.has_triggered = true;
        }
        const detune = patch.detuneRatio();
        self.osc1.setFrequency(self.current_freq);
        self.osc2.setFrequency(self.current_freq * detune);
        self.amp_env.gateOn(self.velocity);
        self.filter_env.gateOn(self.velocity);
    }

    pub fn release(self: *Voice) void {
        self.held = false;
        self.sustained = false;
        self.amp_env.gateOff();
        self.filter_env.gateOff();
    }

    pub fn reset(self: *Voice) void {
        self.held = false;
        self.sustained = false;
        self.has_triggered = false;
        self.amp_env.reset();
        self.filter_env.reset();
        self.svf.reset();
    }
};

/// 8-voice polyphonic modular synthesizer with priority voice stealing, sustain pedal,
/// shared LFO modulation matrix, fractional chorus/delay, and real-time FFT oscilloscope.
pub const PolySynth = struct {
    sample_rate: f32 = 44100.0,
    patch: synth_mod.PatchConfig = .{},
    voices: [MAX_VOICES]Voice = undefined,
    note_counter: u64 = 0,
    poly_mode: bool = true,
    sustain_pedal: bool = false,
    pitch_bend_semitones: f32 = 0.0,

    lfo: lfo_mod.Lfo = undefined,
    delay: effects.ChorusDelay = undefined,

    ring_buffer: [fft.FFT_SIZE]f32 = @splat(0.0),
    ring_idx: usize = 0,
    analyzer: fft.FftAnalyzer = undefined,

    pub fn init(sample_rate: f32) PolySynth {
        var ps: PolySynth = undefined;
        ps.initInPlace(sample_rate);
        return ps;
    }

    pub fn initInPlace(self: *PolySynth, sample_rate: f32) void {
        const sr = if (std.math.isFinite(sample_rate) and sample_rate >= 1.0) sample_rate else 44100.0;
        self.sample_rate = sr;
        self.patch = .{};
        self.note_counter = 0;
        self.poly_mode = true;
        self.sustain_pedal = false;
        self.pitch_bend_semitones = 0.0;

        for (0..MAX_VOICES) |i| {
            self.voices[i] = Voice.init(sr, self.patch);
            const idx_u32: u32 = @intCast(i);
            // Distinct noise seeds per voice so polyphonic noise layers decorrelate
            self.voices[i].osc1.setNoiseSeed(0x12345678 +% (idx_u32 *% 0x9E3779B1));
            self.voices[i].osc2.setNoiseSeed(0x87654321 +% (idx_u32 *% 0x85EBCA6B));
        }

        self.lfo = lfo_mod.Lfo.init(sr);
        self.delay.initInPlace(sr);
        @memset(&self.ring_buffer, 0.0);
        self.ring_idx = 0;
        self.analyzer.initInPlace(.hann);
    }

    pub fn applyPatch(self: *PolySynth, patch: synth_mod.PatchConfig) void {
        self.patch = patch;
        for (&self.voices) |*v| {
            v.syncPatch(patch);
        }
        self.lfo.setWaveform(patch.lfo_waveform);
        self.lfo.setTarget(patch.lfo_target);
        self.lfo.setRate(patch.lfo_rate_hz);
        self.lfo.setDepth(patch.lfo_depth);

        self.delay.setDelayMs(patch.delay_ms);
        self.delay.setFeedback(patch.delay_feedback);
        self.delay.setDamping(patch.delay_damping);
        self.delay.setWetMix(patch.delay_mix);
        self.delay.setChorusMod(patch.chorus_rate_hz, patch.chorus_depth_ms);
    }

    pub fn loadPreset(self: *PolySynth, preset: synth_mod.PresetId) void {
        self.applyPatch(synth_mod.PatchConfig.fromPreset(preset));
    }

    pub fn setPolyMode(self: *PolySynth, enabled: bool) void {
        if (self.poly_mode == enabled) return;
        self.poly_mode = enabled;
        if (!enabled) {
            // Release auxiliary voices cleanly when switching to mono
            for (1..MAX_VOICES) |i| {
                self.voices[i].release();
            }
        }
    }

    pub fn setMasterVolume(self: *PolySynth, vol: f32) void {
        if (!std.math.isFinite(vol)) return;
        self.patch.master_volume = std.math.clamp(vol, 0.0, 1.0);
    }

    pub fn setOsc1Waveform(self: *PolySynth, wf: osc.Waveform) void {
        self.patch.osc1_waveform = wf;
        for (&self.voices) |*v| v.osc1.setWaveform(wf);
    }

    pub fn setOsc2Waveform(self: *PolySynth, wf: osc.Waveform) void {
        self.patch.osc2_waveform = wf;
        for (&self.voices) |*v| v.osc2.setWaveform(wf);
    }

    pub fn setOscMix(self: *PolySynth, mix: f32) void {
        if (!std.math.isFinite(mix)) return;
        self.patch.osc_mix = std.math.clamp(mix, 0.0, 1.0);
    }

    pub fn setOsc2DetuneCents(self: *PolySynth, cents: f32) void {
        if (!std.math.isFinite(cents)) return;
        self.patch.osc2_detune_cents = std.math.clamp(cents, -2400.0, 2400.0);
    }

    pub fn setPulseWidth(self: *PolySynth, pw: f32) void {
        if (!std.math.isFinite(pw)) return;
        const clamped = std.math.clamp(pw, 0.02, 0.98);
        self.patch.pulse_width = clamped;
        for (&self.voices) |*v| {
            v.osc1.setPulseWidth(clamped);
            v.osc2.setPulseWidth(clamped);
        }
    }

    pub fn setFmDepth(self: *PolySynth, depth: f32) void {
        if (!std.math.isFinite(depth)) return;
        self.patch.fm_depth = std.math.clamp(depth, 0.0, 10.0);
    }

    pub fn setFilterCutoff(self: *PolySynth, hz: f32) void {
        if (!std.math.isFinite(hz)) return;
        const nyquist = self.sample_rate * 0.49;
        const clamped = std.math.clamp(hz, 20.0, nyquist);
        self.patch.filter_cutoff = clamped;
        for (&self.voices) |*v| v.svf.setCutoff(clamped);
    }

    pub fn setFilterResonance(self: *PolySynth, q: f32) void {
        if (!std.math.isFinite(q)) return;
        const clamped = std.math.clamp(q, 0.5, 20.0);
        self.patch.filter_resonance = clamped;
        for (&self.voices) |*v| v.svf.setResonance(clamped);
    }

    pub fn setFilterType(self: *PolySynth, ft: filter.FilterType) void {
        self.patch.filter_type = ft;
        for (&self.voices) |*v| v.svf.setFilterType(ft);
    }

    pub fn setFilterEnvAmount(self: *PolySynth, amount: f32) void {
        if (!std.math.isFinite(amount)) return;
        self.patch.filter_env_amount = std.math.clamp(amount, -10000.0, 15000.0);
    }

    pub fn setAmpAdsr(self: *PolySynth, attack: f32, decay: f32, sustain: f32, release: f32) void {
        if (std.math.isFinite(attack)) self.patch.amp_attack = std.math.clamp(attack, 0.001, 5.0);
        if (std.math.isFinite(decay)) self.patch.amp_decay = std.math.clamp(decay, 0.001, 5.0);
        if (std.math.isFinite(sustain)) self.patch.amp_sustain = std.math.clamp(sustain, 0.0, 1.0);
        if (std.math.isFinite(release)) self.patch.amp_release = std.math.clamp(release, 0.001, 10.0);
        for (&self.voices) |*v| {
            v.amp_env.setParameters(self.patch.amp_attack, self.patch.amp_decay, self.patch.amp_sustain, self.patch.amp_release);
        }
    }

    pub fn setFilterAdsr(self: *PolySynth, attack: f32, decay: f32, sustain: f32, release: f32) void {
        if (std.math.isFinite(attack)) self.patch.filter_attack = std.math.clamp(attack, 0.001, 5.0);
        if (std.math.isFinite(decay)) self.patch.filter_decay = std.math.clamp(decay, 0.001, 5.0);
        if (std.math.isFinite(sustain)) self.patch.filter_sustain = std.math.clamp(sustain, 0.0, 1.0);
        if (std.math.isFinite(release)) self.patch.filter_release = std.math.clamp(release, 0.001, 10.0);
        for (&self.voices) |*v| {
            v.filter_env.setParameters(self.patch.filter_attack, self.patch.filter_decay, self.patch.filter_sustain, self.patch.filter_release);
        }
    }

    pub fn setEnvCurve(self: *PolySynth, curve: envelope.EnvelopeCurve) void {
        self.patch.env_curve = curve;
        for (&self.voices) |*v| {
            v.amp_env.setCurve(curve);
            v.filter_env.setCurve(curve);
        }
    }

    pub fn setDrive(self: *PolySynth, drive: f32) void {
        if (!std.math.isFinite(drive)) return;
        self.patch.drive = std.math.clamp(drive, 0.5, 8.0);
    }

    pub fn setGlide(self: *PolySynth, sec: f32) void {
        if (!std.math.isFinite(sec)) return;
        self.patch.glide_sec = std.math.clamp(sec, 0.0, 2.0);
    }

    pub fn setPitchBend(self: *PolySynth, semitones: f32) void {
        if (!std.math.isFinite(semitones)) return;
        self.pitch_bend_semitones = std.math.clamp(semitones, -12.0, 12.0);
    }

    pub fn setSustainPedal(self: *PolySynth, down: bool) void {
        self.sustain_pedal = down;
        if (!down) {
            for (&self.voices) |*v| {
                if (v.sustained) {
                    v.release();
                }
            }
        }
    }

    fn allocateVoiceIndex(self: *PolySynth, midi_note: u8) usize {
        if (!self.poly_mode) return 0;

        // 1. Retrigger voice already playing the same note
        for (0..MAX_VOICES) |i| {
            if (self.voices[i].isActive() and self.voices[i].midi_note == midi_note) {
                return i;
            }
        }

        // 2. First idle voice
        for (0..MAX_VOICES) |i| {
            if (!self.voices[i].isActive()) {
                return i;
            }
        }

        // 3. Quietest voice currently in release stage
        var best_release: ?usize = null;
        var lowest_level: f32 = 2.0;
        for (0..MAX_VOICES) |i| {
            if (self.voices[i].amp_env.state == .release and self.voices[i].amp_env.current_value < lowest_level) {
                lowest_level = self.voices[i].amp_env.current_value;
                best_release = i;
            }
        }
        if (best_release) |idx| return idx;

        // 4. Oldest active voice
        var oldest_idx: usize = 0;
        var oldest_age: u64 = self.voices[0].age;
        for (1..MAX_VOICES) |i| {
            if (self.voices[i].age < oldest_age) {
                oldest_age = self.voices[i].age;
                oldest_idx = i;
            }
        }
        return oldest_idx;
    }

    pub fn noteOn(self: *PolySynth, midi_note: u8, velocity: f32) void {
        const idx = self.allocateVoiceIndex(midi_note);
        self.note_counter +%= 1;
        const allow_glide = !self.poly_mode;
        self.voices[idx].trigger(midi_note, velocity, self.note_counter, self.patch, allow_glide);
    }

    pub fn noteOff(self: *PolySynth, midi_note: u8) void {
        for (&self.voices) |*v| {
            if (v.isActive() and v.midi_note == midi_note and v.held) {
                if (self.sustain_pedal) {
                    v.held = false;
                    v.sustained = true;
                } else {
                    v.release();
                }
            }
        }
    }

    pub fn allNotesOff(self: *PolySynth) void {
        for (&self.voices) |*v| {
            if (v.isActive()) {
                v.release();
            }
        }
    }

    pub fn panic(self: *PolySynth) void {
        self.sustain_pedal = false;
        for (&self.voices) |*v| {
            v.reset();
        }
        self.delay.clear();
    }

    pub fn activeVoiceCount(self: *const PolySynth) usize {
        var count: usize = 0;
        for (&self.voices) |*v| {
            if (v.isActive()) count += 1;
        }
        return count;
    }

    pub fn render(self: *PolySynth, out_frames: []f32) void {
        const sr = if (self.sample_rate >= 1.0) self.sample_rate else 44100.0;
        const glide_coef: f32 = if (self.patch.glide_sec > 0.0005)
            @exp(-1.0 / (self.patch.glide_sec * sr))
        else
            0.0;
        const bend_ratio = if (self.pitch_bend_semitones != 0.0)
            synth_mod.centsToRatio(self.pitch_bend_semitones * 100.0)
        else
            1.0;
        const detune_ratio = self.patch.detuneRatio();
        const mix = std.math.clamp(self.patch.osc_mix, 0.0, 1.0);
        const osc1_gain = 1.0 - mix;
        const osc2_gain = mix;
        const drive = std.math.clamp(self.patch.drive, 0.5, 8.0);
        const vol = std.math.clamp(self.patch.master_volume, 0.0, 1.0);
        const voice_headroom: f32 = if (self.poly_mode) 0.55 else 1.0;

        for (out_frames) |*sample| {
            const lfo_val = self.lfo.nextSample();
            const pitch_lfo_ratio: f32 = if (self.lfo.target == .pitch and lfo_val != 0.0)
                synth_mod.centsToRatio(lfo_val * 200.0)
            else
                1.0;
            const pw_mod: f32 = if (self.lfo.target == .pulse_width) lfo_val * 0.4 else 0.0;
            const fm_mod_depth: f32 = if (self.lfo.target == .fm_depth)
                @max(0.0, self.patch.fm_depth * (1.0 + lfo_val))
            else
                self.patch.fm_depth;
            const cutoff_lfo: f32 = if (self.lfo.target == .filter_cutoff)
                lfo_val * @max(self.patch.filter_cutoff * 0.8, 1200.0)
            else
                0.0;
            const tremolo_gain: f32 = if (self.lfo.target == .amplitude)
                std.math.clamp(1.0 + (lfo_val * 0.5), 0.0, 1.5)
            else
                1.0;

            var bus: f32 = 0.0;
            for (&self.voices) |*v| {
                if (!v.isActive()) continue;

                if (glide_coef > 0.0) {
                    v.current_freq = v.target_freq + ((v.current_freq - v.target_freq) * glide_coef);
                } else {
                    v.current_freq = v.target_freq;
                }

                const eff_freq = v.current_freq * bend_ratio * pitch_lfo_ratio;
                v.osc1.setFrequency(eff_freq);
                v.osc2.setFrequency(eff_freq * detune_ratio);

                const osc2_s = v.osc2.nextSampleWithPwm(0.0, pw_mod);
                const osc1_s = v.osc1.nextSampleWithPwm(osc2_s * fm_mod_depth, pw_mod);
                const raw = (osc1_s * osc1_gain) + (osc2_s * osc2_gain);
                const driven = if (drive > 1.001) synth_mod.softClip(raw * drive) else raw;

                const f_env = v.filter_env.nextSample();
                const mod_cutoff = v.svf.cutoff + (f_env * self.patch.filter_env_amount) + cutoff_lfo;
                const filtered = v.svf.processModulated(driven, mod_cutoff);
                const a_env = v.amp_env.nextSample();

                bus += filtered * a_env;
            }

            const dry_bus = bus * voice_headroom * tremolo_gain;
            const effected = self.delay.process(dry_bus);
            const out_val = synth_mod.softClip(effected * vol);

            sample.* = out_val;
            self.ring_buffer[self.ring_idx] = out_val;
            self.ring_idx = (self.ring_idx + 1) % fft.FFT_SIZE;
        }
    }

    pub fn getSpectrum(self: *const PolySynth, out_bins: *[fft.NUM_BINS]f32) void {
        var linear_buf: [fft.FFT_SIZE]f32 = undefined;
        self.linearizeRing(&linear_buf);
        self.analyzer.computeSpectrum(&linear_buf, out_bins);
    }

    pub fn getSpectralMetrics(self: *const PolySynth) fft.SpectralMetrics {
        var linear_buf: [fft.FFT_SIZE]f32 = undefined;
        self.linearizeRing(&linear_buf);
        return self.analyzer.analyze(&linear_buf, self.sample_rate);
    }

    fn linearizeRing(self: *const PolySynth, out: *[fft.FFT_SIZE]f32) void {
        for (0..fft.FFT_SIZE) |i| {
            const idx = (self.ring_idx + i) % fft.FFT_SIZE;
            out[i] = self.ring_buffer[idx];
        }
    }
};

test "PolySynth chord synthesis renders distinct multi-voice harmonics" {
    var ps = PolySynth.init(44100.0);
    ps.setOsc1Waveform(.sine);
    ps.setOscMix(0.0); // pure sine per voice for clean chord bin verification
    ps.setFilterCutoff(10000.0);
    ps.setFilterResonance(0.7071);
    ps.setFilterEnvAmount(0.0);
    ps.setAmpAdsr(0.002, 0.01, 1.0, 0.1);

    // C4 (60: 261.6 Hz), E4 (64: 329.6 Hz), G4 (67: 392.0 Hz)
    ps.noteOn(60, 0.8);
    ps.noteOn(64, 0.8);
    ps.noteOn(67, 0.8);
    try std.testing.expectEqual(@as(usize, 3), ps.activeVoiceCount());

    var buf: [1024]f32 = undefined;
    ps.render(&buf);
    ps.render(&buf);

    var bins: [fft.NUM_BINS]f32 = undefined;
    ps.getSpectrum(&bins);

    // Bins for 261.6 Hz (~6), 329.6 Hz (~8), 392.0 Hz (~9) should all carry significant energy
    try std.testing.expect(bins[6] > 0.04);
    try std.testing.expect(bins[8] > 0.04);
    try std.testing.expect(bins[9] > 0.04);

    // Releasing only E4 leaves C4 and G4 sustaining
    ps.noteOff(64);
    for (0..12) |_| ps.render(&buf);
    try std.testing.expectEqual(@as(usize, 2), ps.activeVoiceCount());
}

test "PolySynth priority voice stealing prefers releasing voices then oldest" {
    var ps = PolySynth.init(44100.0);
    ps.setAmpAdsr(0.001, 0.01, 0.8, 0.5);

    // Fill all 8 voices with MIDI notes 60..67
    for (0..MAX_VOICES) |i| {
        ps.noteOn(@intCast(60 + i), 0.8);
    }
    try std.testing.expectEqual(MAX_VOICES, ps.activeVoiceCount());

    var buf: [64]f32 = undefined;
    ps.render(&buf);

    // Release note 63 so it enters release stage and decays slightly
    ps.noteOff(63);
    ps.render(&buf);

    // Triggering 9th note (72) must steal releasing note 63 rather than oldest held note 60
    ps.noteOn(72, 0.9);
    try std.testing.expectEqual(MAX_VOICES, ps.activeVoiceCount());

    var found_60 = false;
    var found_63 = false;
    var found_72 = false;
    for (ps.voices) |v| {
        if (v.midi_note == 60) found_60 = true;
        if (v.midi_note == 63) found_63 = true;
        if (v.midi_note == 72) found_72 = true;
    }
    try std.testing.expect(found_60);
    try std.testing.expect(!found_63);
    try std.testing.expect(found_72);

    // Triggering 10th note (74) while all 8 are held must steal oldest held note 60
    ps.noteOn(74, 0.9);
    found_60 = false;
    var found_74 = false;
    for (ps.voices) |v| {
        if (v.midi_note == 60) found_60 = true;
        if (v.midi_note == 74) found_74 = true;
    }
    try std.testing.expect(!found_60);
    try std.testing.expect(found_74);
}

test "PolySynth sustain pedal holds released notes until lifted" {
    var ps = PolySynth.init(44100.0);
    ps.setAmpAdsr(0.001, 0.005, 0.8, 0.01);

    ps.setSustainPedal(true);
    ps.noteOn(60, 0.9);
    ps.noteOff(60);

    var buf: [512]f32 = undefined;
    // Should remain active while sustain pedal is down
    for (0..6) |_| ps.render(&buf);
    try std.testing.expectEqual(@as(usize, 1), ps.activeVoiceCount());

    // Lifting pedal triggers release -> transitions to idle
    ps.setSustainPedal(false);
    for (0..6) |_| ps.render(&buf);
    try std.testing.expectEqual(@as(usize, 0), ps.activeVoiceCount());
}
