# CoreLM — Module Dependency Map

## Visual Dependency Graph

```
                    ┌─────────────────────┐
                    │      App UI         │
                    │  (SwiftUI Views +   │
                    │   ViewModels)       │
                    └────────┬────────────┘
                             │ observes / calls
                             ▼
                    ┌─────────────────────┐
                    │  Swift Runtime      │
                    │  Bridge             │
                    │  (CoreLMRuntime,    │
                    │   InferenceSession) │
                    └────────┬────────────┘
                             │ calls via FFI
                             ▼
                    ┌─────────────────────┐
                    │      C API          │
                    │  (clm_* functions)  │
                    └────────┬────────────┘
                             │ delegates to
                             ▼
          ┌──────────────────────────────────────┐
          │           Engine Core                │
          │                                      │
          │  ┌──────────┐    ┌───────────────┐   │
          │  │  Model    │───►│  Runtime      │   │
          │  │  Loader   │    │  (Generation  │   │
          │  └──────────┘    │   Loop)       │   │
          │       │          └───┬───┬───────┘   │
          │       │              │   │            │
          │       ▼              │   │            │
          │  ┌──────────┐       │   │            │
          │  │  Tensor   │◄──────┘   │            │
          │  │  Layer    │           │            │
          │  └──────────┘           │            │
          │       ▲                  │            │
          │       │    ┌─────────────┘            │
          │       │    │                          │
          │  ┌────┴────▼──┐  ┌───────────────┐   │
          │  │  Attention  │  │   Sampler     │   │
          │  │  Module     │  │              │   │
          │  └─────┬──────┘  └───────────────┘   │
          │        │                              │
          │        ▼                              │
          │  ┌──────────┐                        │
          │  │  KV Cache │                        │
          │  │  Manager  │                        │
          │  └──────────┘                        │
          │        │                              │
          └────────┼──────────────────────────────┘
                   │ dispatches ops to
                   ▼
          ┌──────────────────────────────────────┐
          │        Backend Abstraction           │
          │  ┌────────────┐  ┌────────────────┐  │
          │  │ CPU Backend│  │ Metal Backend  │  │
          │  │ (Accelerate│  │ (Compute       │  │
          │  │  framework)│  │  Shaders)      │  │
          │  └────────────┘  └────────────────┘  │
          └──────────────────────────────────────┘
```

---

## Detailed Module Dependencies

### App UI Layer

| Module | Depends On | Depended On By |
|--------|-----------|----------------|
| `ChatView` | `ChatViewModel` | — |
| `ChatViewModel` | `CoreLMRuntime`, `ChatStore` | `ChatView` |
| `ModelListView` | `ModelListViewModel` | — |
| `ModelListViewModel` | `CoreLMRuntime`, `ModelRegistry` | `ModelListView` |
| `DiagnosticsView` | `DiagnosticsViewModel` | — |
| `DiagnosticsViewModel` | `CoreLMRuntime` (metrics) | `DiagnosticsView` |
| `SettingsView` | `SettingsStore` | — |
| `ChatStore` | SQLite / file I/O | `ChatViewModel` |
| `ModelRegistry` | filesystem / JSON | `ModelListViewModel`, `CoreLMRuntime` |
| `SettingsStore` | UserDefaults / JSON | `SettingsView`, `CoreLMRuntime` |

### Swift Runtime Bridge

| Module | Depends On | Depended On By |
|--------|-----------|----------------|
| `CoreLMRuntime` | C API (`libcorelm`) | All ViewModels |
| `InferenceSession` | C API (`libcorelm`) | `ChatViewModel` |
| `RuntimeMetrics` | C API (metrics query) | `DiagnosticsViewModel` |
| `CoreLMError` | C API (error codes) | All ViewModels |

### C API

| Module | Depends On | Depended On By |
|--------|-----------|----------------|
| `clm_context_*` | Engine Runtime | Swift Bridge |
| `clm_model_*` | Model Loader | Swift Bridge |
| `clm_generate_*` | Runtime, Sampler | Swift Bridge |
| `clm_metrics_*` | Runtime, KV Cache | Swift Bridge |

### Engine Core

| Module | Depends On | Depended On By |
|--------|-----------|----------------|
| **Model Loader** | Tensor Layer | Runtime, C API |
| **Tensor Layer** | — (foundation) | All engine modules |
| **Runtime** | Model Loader, Tensor, Attention, Sampler, KV Cache, Backend | C API |
| **Attention** | Tensor, KV Cache, Backend | Runtime |
| **KV Cache** | Tensor | Attention, Runtime |
| **Sampler** | Tensor | Runtime |
| **Backend Interface** | Tensor | All compute modules |

### Backend Layer

| Module | Depends On | Depended On By |
|--------|-----------|----------------|
| **CPU Backend** | Accelerate framework, Tensor | Backend dispatcher |
| **Metal Backend** | Metal framework, Tensor, Metal shaders | Backend dispatcher |

---

## Build Dependency Order

The project must be built bottom-up. This is the strict build order:

```
Phase 1: Foundation (no internal dependencies)
  └── Tensor Layer

Phase 2: Core modules (depend on Tensor)
  ├── Model Loader
  ├── KV Cache Manager
  ├── Sampler
  └── Backend Interface

Phase 3: Compute backends (depend on Backend Interface + Tensor)
  ├── CPU Backend
  └── Metal Backend (can be deferred)

Phase 4: Execution layer (depends on all of Phase 2 + 3)
  ├── Attention Module
  └── Runtime / Generation Loop

Phase 5: C API (depends on Phase 4)
  └── clm_* function exports

Phase 6: Swift Bridge (depends on Phase 5)
  └── CoreLMRuntime, InferenceSession

Phase 7: App UI (depends on Phase 6)
  └── SwiftUI Views + ViewModels
```

---

## Shared Utilities

The `shared/` directory contains cross-cutting code used by multiple layers:

| Module | Location | Used By |
|--------|----------|---------|
| `schemas/` | Model metadata schemas, generation parameter schemas | App, Bridge, Engine |
| `config/` | Build configuration, feature flags | All layers |
| `utilities/` | Logging protocol, timing utilities | All layers |

---

## External Dependencies

| Dependency | Type | Used By | Purpose |
|-----------|------|---------|---------|
| Apple Accelerate | System framework | CPU Backend | Vectorized math (BLAS, vDSP) |
| Metal | System framework | Metal Backend | GPU compute |
| MetalPerformanceShaders | System framework | Metal Backend (optional) | Optimized GPU kernels |
| Foundation | System framework | App, Bridge | File I/O, networking-free utilities |
| SwiftUI | System framework | App UI | Interface |
| SQLite | System library | App (ChatStore) | Chat persistence |

**No third-party dependencies in v1.** This is deliberate — CoreLM must not carry dependency risk for its core inference path.

---

## Interface Boundaries (Key Contracts)

### Boundary 1: App ↔ Bridge

- Swift protocols and classes
- `@Observable` pattern for reactive updates
- `AsyncThrowingStream` for token streaming
- Swift `Error` types for failures
- No C types visible

### Boundary 2: Bridge ↔ C API

- C function calls with opaque handles
- `clm_status_t` return codes
- Callback function pointers for streaming
- `const char*` for string data
- Fixed-layout structs for parameters

### Boundary 3: C API ↔ Engine

- C++ method calls on engine objects
- Engine objects hidden behind opaque C handles
- No C++ types in the C header

### Boundary 4: Engine ↔ Backends

- Abstract C++ `Backend` base class
- Virtual dispatch for operations
- Tensor references (not copies) passed across boundary
- Backend reports capability per operation
