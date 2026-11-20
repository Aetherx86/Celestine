# Changelog

All notable changes to this project will be documented in this file.

## [0.2.0] - 2026-11-20

### Added
- 8-voice `PolySynth` with priority voice stealing (releasing voices first, then oldest) and sustain pedal handling.
- Effects: chorus and feedback delay line with exact echo timing and bounded feedback.
- LFO module (sine, triangle, saw, square, sample-and-hold) for pitch, filter and amplitude modulation.
- RIFF WAV writer with 16-bit PCM and 32-bit IEEE float encodings, streamed to disk.
- Patch presets, selectable from the CLI and through `celestine_load_preset`.
- FFT analysis windows (Hann, Hamming, Blackman-Harris, rectangular), parabolic sub-bin peak interpolation, spectral centroid, 85 percent rolloff and spectral flatness.
- CLI subcommands `render`, `chord`, `analyze`, `bench` and `presets`, each with `--json` output. Durations accept fractional seconds and are clamped to 0.05 to 600 s.
- WASM exports for polyphonic note on and off, all-notes-off, presets, parameter setting, active voice count, peak frequency, spectral centroid and RMS.

### Changed
- State variable filter rewritten as a topology-preserving (zero-delay feedback) SVF, which stays stable near Nyquist at high resonance.
- Triangle oscillator uses PolyBLAMP correction, and pulse width modulation is DC-neutral.
- ADSR stages use exponential curves, and a zero-sustain percussive release can no longer stall.
- Soft clipper is C1-continuous.

## 0.1.0 - 2026-11-08

### Added
- Initial release of Celestine audio DSP modular synthesizer and oscilloscope engine.
- Band-limited oscillator waveforms (Sine, Saw, Square, Triangle, Noise) with PolyBLEP anti-aliasing.
- State Variable Filter (SVF) with resonant Low-pass, High-pass, Band-pass, and Notch responses.
- Dual ADSR envelope generators for amplitude and filter cutoff modulation.
- In-place Radix-2 Cooley-Tukey 1024-point FFT with Hann windowing for real-time spectral visualization.
- Freestanding WebAssembly compilation target yielding a 12 KB binary for WebAudio worklets.
