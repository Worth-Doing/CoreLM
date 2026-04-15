# CoreLM — System Architecture

## Overview

CoreLM is a native macOS application for local LLM inference, composed of four strictly separated layers. Each layer has clear responsibilities, explicit interfaces, and no upward dependencies.

```
┌─────────────────────────────────────────────────────┐
│                 Layer 1: App UI                     │
│            SwiftUI · AppKit bridging                │
├─────────────────────────────────────────────────────┤
│            Layer 2: Swift Runtime Bridge            │
│        Lifecycle · Sessions · Streaming             │
├─────────────────────────────────────────────────────┤
│              Layer 3: Engine Core                   │
│    Loader · Tensors · Graph · Attention · KV Cache  │
│                 Sampler · Tokenizer                 │
├─────────────────────────────────────────────────────┤
│           Layer 4: Backend Execution                │
│              CPU backend · Metal backend            │
└─────────────────────────────────────────────────────┘
```

Data flows **downward** through function calls.
Data flows **upward** through callbacks, return values, and observation patterns.

No layer may bypass an adjacent layer. The UI never calls C++ directly. The engine never touches SwiftUI.

---

## Layer 1 — App UI

**Language:** Swift + SwiftUI
**Location:** `apps/CoreLMApp/Sources/`

### Responsibilities

- Window management and navigation
- Chat interface (conversation display, prompt input, streaming output)
- Model manager UI (list, import, load/unload, metadata display)
- Settings UI (generation parameters, appearance, backend preferences)
- Diagnostics UI (runtime stats, logs, performance metrics)
- Local persistence for app-facing state (chats, settings, presets)

### What this layer must NOT do

- Perform any inference math
- Hold references to C/C++ pointers
- Manage engine memory
- Know about tensor shapes, KV cache internals, or Metal buffers

### Key Design Decisions

- **Dark mode first**, light mode supported
- **Code-first UI** — no storyboards, no Xcode visual editors
- **MVVM pattern** — Views observe ViewModels; ViewModels call into the Runtime Bridge
- **Markdown rendering** in chat via AttributedString or a lightweight parser
- **Token streaming** displayed incrementally with smooth append, no full-rerender

### State Management

| State | Storage | Scope |
|-------|---------|-------|
| Chat history | SQLite via local DB | Persistent |
| Model registry | JSON + filesystem | Persistent |
| App settings | UserDefaults + JSON | Persistent |
| Generation presets | JSON files | Persistent |
| Active session | In-memory ViewModel | Session-scoped |
| Runtime metrics | Observable from bridge | Ephemeral |

---

## Layer 2 — Swift Runtime Bridge

**Language:** Swift
**Location:** `apps/CoreLMApp/Sources/Runtime/` (Swift side) + `engine/c_api/` (C boundary)

### Responsibilities

- Engine lifecycle management (init, shutdown)
- Model loading/unloading orchestration
- Session creation, management, and teardown
- Request → C API translation
- Token streaming callback relay (C callback → Swift async stream)
- Error translation (C error codes → Swift errors)
- Threading coordination (ensure engine work off main thread, UI updates on main thread)
- Cancellation propagation
- Runtime metrics collection and exposure

### Interface Contract

The bridge exposes a **Swift-native API** to Layer 1:

```swift
// Conceptual — actual implementation may differ in details
@Observable
class CoreLMRuntime {
    var state: RuntimeState          // .idle, .loading, .ready, .generating, .error
    var loadedModel: ModelInfo?
    var metrics: RuntimeMetrics

    func loadModel(at url: URL) async throws
    func unloadModel() async
    func createSession(parameters: GenerationParameters) -> InferenceSession
}

class InferenceSession {
    func generate(prompt: String) -> AsyncThrowingStream<Token, Error>
    func cancel()
    func reset()
}
```

### Threading Model

```
Main Thread           Bridge Thread          Engine Thread
    │                      │                      │
    ├─ generate(prompt) ──►│                      │
    │                      ├─ clm_generate() ────►│
    │                      │                      ├─ compute token
    │                      │◄── token callback ───┤
    │◄── AsyncStream ──────┤                      │
    │    yield token        │                      │
    ├─ update UI            │                      │
```

### Error Boundary

All C API errors are caught at this layer and converted to typed Swift errors:

```swift
enum CoreLMError: Error {
    case modelLoadFailed(reason: String)
    case unsupportedArchitecture(String)
    case unsupportedQuantization(String)
    case memoryAllocationFailed
    case backendInitFailed(backend: String, reason: String)
    case generationFailed(reason: String)
    case cancelled
    case invalidState(String)
}
```

---

## Layer 3 — Engine Core

**Language:** C++17
**Location:** `engine/core/`

### Responsibilities

- Model file parsing and validation
- Weight loading (memory-mapped where possible)
- Tensor primitives (views, shapes, dtypes, strides, buffer management)
- Architecture-specific graph construction (transformer blocks, attention, FFN)
- KV cache allocation and management
- Forward pass execution (prompt evaluation + token generation)
- Logits computation
- Sampling (temperature, top-k, top-p, repetition penalty)
- Backend dispatch (route operations to CPU or Metal)
- Tokenizer integration

### Module Breakdown

| Module | Directory | Purpose |
|--------|-----------|---------|
| Model | `engine/core/model/` | Config parsing, weight mapping, architecture definitions |
| Tensor | `engine/core/tensor/` | Buffer, shape, dtype, stride, view, memory ownership |
| Runtime | `engine/core/runtime/` | Session state, generation loop, forward pass orchestration |
| Sampling | `engine/core/sampling/` | Logits processing, all sampling strategies |
| KV Cache | `engine/core/kv_cache/` | Cache allocation, update, metrics, reset |
| Backends | `engine/core/backends/` | Backend interface + CPU/Metal implementations |

### Execution Flow — Single Token Generation

```
1. Encode input token(s) → embedding lookup
2. For each transformer layer:
   a. RMSNorm (pre-attention)
   b. QKV projection
   c. RoPE positional encoding
   d. Attention computation (with KV cache read/write)
   e. Attention output projection
   f. Residual connection
   g. RMSNorm (pre-FFN)
   h. FFN (gate_proj, up_proj → SiLU → down_proj)
   i. Residual connection
3. Final RMSNorm
4. LM head projection → logits
5. Sample next token from logits
6. Return token, update KV cache position
```

### Memory Strategy

- Model weights: memory-mapped from disk (read-only)
- KV cache: pre-allocated contiguous buffer per session
- Intermediate tensors: allocated from a scratch buffer pool, reused across layers
- No redundant copies between CPU and GPU in unified memory

---

## Layer 4 — Backend Execution

**Language:** C++ (CPU), C++ + Metal Shading Language (GPU)
**Location:** `engine/core/backends/` + `engine/metal/`

### Responsibilities

- Execute individual operations (matmul, softmax, RMSNorm, RoPE, SiLU, element-wise ops)
- Manage backend-specific resources (Metal command queues, compute pipelines)
- Report backend capabilities
- Support fallback (Metal op not implemented → fall back to CPU for that op)

### Backend Interface

```cpp
class Backend {
public:
    virtual ~Backend() = default;

    virtual std::string name() const = 0;
    virtual bool supports(OpType op, DataType dtype) const = 0;

    virtual void matmul(const Tensor& A, const Tensor& B, Tensor& C) = 0;
    virtual void rmsnorm(const Tensor& input, const Tensor& weight, Tensor& output, float eps) = 0;
    virtual void rope(Tensor& q, Tensor& k, int pos, const RoPEConfig& config) = 0;
    virtual void softmax(Tensor& input, int axis) = 0;
    virtual void silu(Tensor& input) = 0;
    virtual void elementwise_mul(const Tensor& a, const Tensor& b, Tensor& out) = 0;
    virtual void add(const Tensor& a, const Tensor& b, Tensor& out) = 0;

    virtual void synchronize() = 0;  // wait for async ops to complete
};
```

### CPU Backend (Stage A — First)

- Reference implementation for all ops
- Used for correctness validation
- Leverages Accelerate framework (vDSP, BLAS) where beneficial
- Single-threaded initially, parallelism added after correctness proven

### Metal Backend (Stage B/C — After CPU works)

- Custom compute shaders for key ops (matmul, attention, RMSNorm, RoPE)
- Shared memory buffers with CPU (unified memory — no explicit transfers needed)
- Command buffer batching for throughput
- Profiling hooks for GPU timeline analysis

### Backend Selection Strategy

```
For each operation in the forward pass:
  1. Check if Metal backend supports this op + dtype
  2. If yes → dispatch to Metal
  3. If no → dispatch to CPU (with synchronization if prior op was on Metal)
```

This allows incremental Metal migration: start with all-CPU, move ops to Metal one by one, always validating correctness against the CPU reference.

---

## Cross-Cutting Concerns

### Logging

- Structured logging with levels: `trace`, `debug`, `info`, `warn`, `error`
- Engine logs via C callback → Bridge captures → App displays in diagnostics
- No `printf` or `NSLog` in production paths
- Log sink configurable (console, file, UI panel)

### Metrics Collection

All metrics flow upward through the bridge:

| Metric | Source | Collection Point |
|--------|--------|-------------------|
| Model load time | Engine | Bridge, on load completion |
| Prompt eval time | Engine | Bridge, on eval completion |
| Time to first token | Engine | Bridge, first token callback |
| Tokens/sec | Engine | Bridge, computed from timestamps |
| Memory usage | Engine + system | Bridge, polled |
| KV cache size | Engine | Bridge, from cache metrics |
| Active backend | Engine | Bridge, from backend query |

### Error Propagation

```
Engine (C++ exception / error code)
  → C API (clm_status_t error code + message buffer)
    → Bridge (CoreLMError Swift enum)
      → UI (user-facing alert / diagnostics log)
```

No layer swallows errors silently. Every error is either handled or propagated.

---

## Data Flow Diagram — Full Generation Path

```
User types prompt
    │
    ▼
[Chat View] ──prompt text──► [ChatViewModel]
                                    │
                                    ▼
                            [CoreLMRuntime.generate()]
                                    │
                                    ▼ (bridge thread)
                            [C API: clm_generate()]
                                    │
                                    ▼ (engine thread)
                            [Tokenize prompt]
                                    │
                                    ▼
                            [Prompt evaluation — N tokens]
                            [Forward pass per layer]
                            [KV cache populated]
                                    │
                                    ▼
                            [Sample first token]
                                    │
                            ┌───────┴────────┐
                            │ token callback  │◄── repeat until stop
                            └───────┬────────┘
                                    │
                                    ▼ (bridge thread)
                            [AsyncStream yield token]
                                    │
                                    ▼ (main thread)
                            [ChatViewModel appends token]
                                    │
                                    ▼
                            [Chat View re-renders incrementally]
```

---

## Security Boundaries

- **No network access** during inference. Model execution is entirely local.
- **No telemetry** unless explicitly opted in by the user.
- **Prompts never leave the device** in v1.
- **Model files** are read-only after import. The engine never writes to model files.
- **Developer logging** (which may include prompt text) is gated behind an explicit toggle.
