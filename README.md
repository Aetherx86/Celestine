# Celestine

Audio DSP Modular Synthesizer & Oscilloscope

A high-precision, bit-exact audio DSP modular synthesizer engine and 1024-point real-time FFT spectrum analyzer compiled to native binaries and a 12 KB freestanding WebAssembly artifact (`-target wasm32-freestanding`), written in Zig.

## Architecture

- Band-Limited Oscillators: Sinc/PolyBLEP (Polynomial Band-Limited Step) algorithm suppresses aliasing harmonics on Sawtooth and Square waveforms.
- State Variable Filter (SVF): Provides continuous low-pass, high-pass, band-pass, and notch outputs with resonance (Q) and envelope tracking.
- Modular Modulation: Dual-operator Frequency Modulation (FM) and additive routing with ADSR amplitude and filter cutoff envelopes.
- Real-Time FFT Analyzer: In-place Radix-2 Cooley-Tukey 1024-point FFT with Hann windowing extracts 512 magnitude spectrum bins for HTML5 Canvas oscilloscopes.
- Zero Runtime Allocation: Render loop operates entirely within fixed stack and caller-provided ring buffers without garbage collection or heap allocation.

## WebAssembly Exported API

```c
void celestine_init(float sample_rate);
void celestine_note_on(uint8_t midi_note, float velocity);
void celestine_note_off(void);
void celestine_set_param(uint32_t param_id, float value);
float* celestine_render(uint32_t frames);
float* celestine_get_spectrum(void);
uint32_t celestine_get_spectrum_size(void);
float* celestine_get_buffer_ptr(void);
uint32_t celestine_get_buffer_size(void);
```

## CLI Usage

```bash
# Render 2 seconds of synthesized audio and display spectral telemetry
celestine render 2
```

## Building and Testing

```bash
# Run unit tests
zig build test

# Compile freestanding WebAssembly artifact and native CLI
zig build -Doptimize=ReleaseSmall
```

## License

MIT License - Copyright (c) 2026 Jeong Hoon Kim
