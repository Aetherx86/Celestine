# Changelog

All notable changes to this project will be documented in this file.

## 0.1.0 - 2026-11-08

### Added
- Initial release of Celestine audio DSP modular synthesizer and oscilloscope engine.
- Band-limited oscillator waveforms (Sine, Saw, Square, Triangle, Noise) with PolyBLEP anti-aliasing.
- State Variable Filter (SVF) with resonant Low-pass, High-pass, Band-pass, and Notch responses.
- Dual ADSR envelope generators for amplitude and filter cutoff modulation.
- In-place Radix-2 Cooley-Tukey 1024-point FFT with Hann windowing for real-time spectral visualization.
- Freestanding WebAssembly compilation target yielding a 12 KB binary for WebAudio worklets.
