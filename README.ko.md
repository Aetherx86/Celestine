# Celestine

오디오 DSP 모듈러 신시사이저 및 오실로스코프 (Audio DSP Modular Synthesizer & Oscilloscope)

고정밀 비트 단위 오디오 DSP 모듈러 신시사이저 엔진 및 1024포인트 실시간 FFT 스펙트럼 분석기로, 네이티브 바이너리와 12 KB 크기의 독립형 WebAssembly 아티팩트(`-target wasm32-freestanding`)로 컴파일되는 Zig 기반 시스템입니다.

[English Documentation](README.md) • [Interactive WebAssembly Demo](https://aetherx86.github.io/celestine/)

## 아키텍처

- 대역 제한 오실레이터 (Band-Limited Oscillators): Sinc 및 PolyBLEP (다항식 대역 제한 스텝) 알고리즘을 적용하여 톱니파(Sawtooth) 및 사각파(Square)의 에일리어싱 고조파를 억제합니다.
- 상태 변수 필터 (State Variable Filter, SVF): 공진(Resonance/Q) 및 엔벨로프 트래킹을 통해 로우패스, 하이패스, 밴드패스, 노치 출력을 연속적으로 제공합니다.
- 모듈러 변조: 듀얼 오퍼레이터 주파수 변조(FM) 및 가산 합성 라우팅, ADSR 진폭 및 필터 컷오프 엔벨로프를 지원합니다.
- 실시간 FFT 분석기: 인플레이스 Radix-2 Cooley-Tukey 1024포인트 FFT와 Hann 윈도우를 결합하여 HTML5 Canvas 오실로스코프를 위한 512 크기 스펙트럼 빈을 추출합니다.
- 런타임 제로 할당: 가비지 컬렉션이나 힙 할당 없이 고정 스택 및 호출자가 제공한 링 버퍼 내에서 렌더 루프가 완전히 실행됩니다.

## WebAssembly 내보낸 API

```c
void celestine_init(float sample_rate);
void celestine_note_on(uint8_t midi_note, float velocity);
void celestine_note_off(void);
void celestine_set_param(uint32_t param_id, float value);
float* celestine_render(uint32_t frames);
float* celestine_get_spectrum(void);
uint32_t celestine_get_spectrum_size(void);
float* celestine_get_buffer_ptr(void);
```

## 빌드 및 테스트

```bash
# 단위 테스트 실행
zig build test

# 독립형 WebAssembly 바이너리 및 네이티브 CLI 빌드
zig build -Doptimize=ReleaseSmall
```

## 라이선스

MIT License - Copyright (c) 2026 Jeong Hoon Kim
