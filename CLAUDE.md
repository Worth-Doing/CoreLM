# CoreLM

Native macOS application for local LLM inference with a custom Mac-first inference engine.

## Project Structure

- `apps/CoreLMApp/` — SwiftUI macOS application
- `engine/` — C++ inference engine (core modules, C API, Metal shaders, tests)
- `shared/` — Cross-cutting schemas, config, utilities
- `docs/` — Architecture, engine, UI, benchmarks, roadmap documentation
- `scripts/` — Build and automation scripts

## Architecture

4-layer architecture with strict boundaries:
1. **App UI** (SwiftUI) — views and view models
2. **Swift Runtime Bridge** — engine lifecycle, sessions, streaming
3. **Engine Core** (C++) — model loading, tensors, attention, KV cache, sampling
4. **Backend Execution** — CPU (Accelerate) and Metal compute

## Key Decisions (v1)

- **Model family:** LLaMA architecture (decoder-only transformer)
- **File format:** GGUF v3
- **Quantization:** Q4_0 first, then Q4_K_M
- **Test model:** TinyLlama 1.1B for development, LLaMA 3.2 3B for validation

## Build Phases

- Phase 0: Architecture & planning (docs/) — COMPLETE
- Phase 1: App skeleton (SwiftUI shell, no inference) — COMPLETE
- Phase 2: Engine CPU reference core — COMPLETE (16/16 tests passing)
- Phase 3: Swift ↔ Engine bridge — COMPLETE
- Phase 4: Full chat integration
- Phase 5: Metal backend
- Phase 6: Mac-first optimization
- Phase 7: Product polish

## Rules

- No third-party dependencies for the inference path
- Engine code must never touch SwiftUI; UI code must never touch C++
- All errors must propagate — never swallow silently
- Every metric must be measurable from the diagnostics panel
- CPU reference path must be correct before Metal optimization begins
- Code-first UI only — no storyboards
