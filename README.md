<p align="center">
  <img src="https://raw.githubusercontent.com/Worth-Doing/brand-assets/main/png/variants/04-horizontal.png" alt="WorthDoing.ai" width="600" />
</p>

<h1 align="center">CoreLM</h1>

<p align="center">
  <strong>Native macOS Local AI Studio with a Custom Mac-First Inference Engine</strong>
</p>

<p align="center">
  <a href="https://github.com/Worth-Doing/CoreLM/releases/latest"><img src="https://img.shields.io/badge/Download-CoreLM.dmg-blue?style=for-the-badge&logo=apple" alt="Download DMG" /></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-black?style=flat-square&logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon-orange?style=flat-square" alt="Apple Silicon" />
  <img src="https://img.shields.io/badge/Language-Swift%20%2B%20C%2B%2B-blue?style=flat-square" alt="Swift + C++" />
  <img src="https://img.shields.io/badge/GPU-Metal%20Compute-green?style=flat-square&logo=apple" alt="Metal" />
  <img src="https://img.shields.io/badge/License-MIT-lightgrey?style=flat-square" alt="MIT" />
  <img src="https://img.shields.io/badge/Notarized-Apple-success?style=flat-square&logo=apple" alt="Notarized" />
  <img src="https://img.shields.io/badge/Format-GGUF-purple?style=flat-square" alt="GGUF" />
  <img src="https://img.shields.io/badge/Built%20by-WorthDoing.ai-ff6b6b?style=flat-square" alt="WorthDoing.ai" />
</p>

---

## What is CoreLM?

CoreLM is a **native macOS application** for running large language models **locally on your Mac**. It features a **custom-built inference engine** designed from the ground up for Apple Silicon, with Metal GPU acceleration and a beautiful SwiftUI interface.

> CoreLM is not a wrapper around someone else's engine.
> It is a native Mac-first AI studio built with product taste and systems rigor.

### Key Highlights

- **100% Native macOS** — Pure SwiftUI + C++ engine. No Electron. No webviews. No compromises.
- **Custom Inference Engine** — Home-built transformer runtime with CPU (Accelerate + NEON) and Metal GPU backends.
- **Universal GGUF Support** — Loads any GGUF model: Q4_0, Q4_K_M, Q5_K_M, Q6_K, Q8_0, F16, F32.
- **HuggingFace Browser** — Search, browse, and download models directly from HuggingFace without leaving the app.
- **Apple Notarized** — Signed with Developer ID and notarized by Apple. No Gatekeeper warnings.
- **Zero Dependencies** — No Python. No pip. No conda. Just download, open, and run.

---

## Download

<p align="center">
  <a href="https://github.com/Worth-Doing/CoreLM/releases/latest/download/CoreLM.dmg">
    <img src="https://img.shields.io/badge/Download-CoreLM.dmg%20(2.4%20MB)-blue?style=for-the-badge&logo=apple&logoColor=white" alt="Download CoreLM" />
  </a>
</p>

### System Requirements

| Requirement | Minimum |
|------------|---------|
| **macOS** | 14.0 (Sonoma) or later |
| **Chip** | Apple Silicon (M1, M2, M3, M4) |
| **RAM** | 8 GB (16+ GB recommended) |
| **Disk** | 50 MB for app + model file size |

### Installation

1. **Download** `CoreLM.dmg` from the link above
2. **Open** the DMG and drag `CoreLM.app` to Applications
3. **Launch** CoreLM — no setup required
4. **Browse** models from HuggingFace or import a local `.gguf` file

---

## Features

### Native macOS Interface

CoreLM looks and feels like a premium Apple application. Dark mode first, with a three-column layout inspired by professional creative tools.

| Component | Description |
|-----------|-------------|
| **Sidebar** | Navigate between Chats, Model Browser, My Models, Diagnostics, and Settings |
| **Chat View** | Full conversation interface with markdown rendering and code blocks |
| **Inspector** | Context-sensitive panel showing model info, runtime stats, and generation parameters |
| **Debug Panel** | Expandable bottom panel with runtime logs and token timings |

### Built-in Model Browser

Browse and download GGUF models directly from HuggingFace:

- **Search** — Find models by name (llama, mistral, phi, tinyllama...)
- **Compatibility Badges** — Each file shows compatibility status before download:
  - 🟢 **Supported** — Q4_0, F16, F32
  - 🔵 **Likely Compatible** — Q4_K_M, Q5_K_M, Q6_K, Q8_0
  - 🟠 **Experimental** — Q2_K, Q3_K
  - 🔴 **Unsupported** — IQ quantizations
- **Smart Recommendations** — Suggests the best quantization for your Mac
- **Progress Tracking** — Download with real-time progress bar
- **Auto-Import** — Downloaded models are immediately available to load
- **Vision Filter** — Automatically hides CLIP/mmproj files that aren't language models

### Chat Interface

- **Token Streaming** — See responses appear word by word in real-time
- **Markdown Rendering** — Rich text with headers, lists, bold, italic
- **Code Blocks** — Syntax-highlighted code with language labels and one-click copy
- **Generation Presets** — Switch between Balanced, Creative, Precise, Code, and Deterministic modes
- **Controls** — Stop generation, regenerate, clear context
- **Keyboard Shortcuts** — ⌘N (new chat), ⌘⏎ (send), ⌘. (stop), ⌘⇧R (regenerate)

### Diagnostics

Real-time inference metrics:

| Metric | Description |
|--------|-------------|
| **Load Time** | Model loading duration |
| **Prompt Eval** | Prompt processing speed (tokens/sec) |
| **Generation** | Token generation speed (tokens/sec) |
| **First Token** | Time to first token latency |
| **Memory** | Model, KV cache, and scratch buffer usage |
| **Context** | Current token count vs. max context window |
| **Backend** | Active compute backend (CPU or Metal) |

### Generation Presets

| Preset | Temperature | Top-K | Top-P | Use Case |
|--------|------------|-------|-------|----------|
| **Balanced** | 0.7 | 40 | 0.95 | General conversation |
| **Creative** | 1.0 | 80 | 0.98 | Creative writing, brainstorming |
| **Precise** | 0.3 | 20 | 0.85 | Factual answers, analysis |
| **Code** | 0.2 | 10 | 0.90 | Code generation |
| **Deterministic** | 0.0 | 1 | 1.0 | Reproducible outputs (seed=42) |

---

## Supported Models

CoreLM supports **LLaMA-architecture** models in **GGUF format**. This includes:

### Model Families

| Family | Examples | Status |
|--------|----------|--------|
| **Meta LLaMA** | LLaMA 3.2 1B/3B, LLaMA 3.1 8B/70B | ✅ Supported |
| **TinyLlama** | TinyLlama 1.1B Chat | ✅ Supported |
| **Mistral** | Mistral 7B, Mistral Nemo | ✅ Supported |
| **CodeLlama** | CodeLlama 7B/13B | ✅ Supported |
| **Qwen** | Qwen 2.5 (llama arch variants) | ⚠️ Experimental |
| **Phi** | Phi-3 | ❌ Not yet |
| **Gemma** | Gemma 2 | ❌ Not yet |

### Quantization Formats

All common GGUF quantization types are supported via automatic F32 dequantization at load time:

| Format | Bits/Weight | Status | Notes |
|--------|-----------|--------|-------|
| **F32** | 32 | ✅ Native | Full precision, largest files |
| **F16** | 16 | ✅ Dequantized | High quality, large files |
| **Q8_0** | 8.5 | ✅ Dequantized | Near-lossless quality |
| **Q6_K** | 6.6 | ✅ Dequantized | Excellent quality |
| **Q5_K_M** | 5.7 | ✅ Dequantized | Very good quality |
| **Q4_K_M** | 4.8 | ✅ Dequantized | Best quality/size ratio |
| **Q4_0** | 4.5 | ✅ Dequantized | Good quality, small files |
| **Q4_1** | 5.0 | ✅ Dequantized | Slightly better than Q4_0 |

### Recommended Models for Getting Started

| Model | Size | RAM Needed | Quality | Download |
|-------|------|-----------|---------|----------|
| **TinyLlama 1.1B Q4_0** | ~600 MB | ~4 GB | Good for testing | Search "TinyLlama" in browser |
| **LLaMA 3.2 1B Q4_K_M** | ~700 MB | ~5 GB | Great for any Mac | Search "Llama-3.2-1B" |
| **LLaMA 3.2 3B Q4_K_M** | ~1.8 GB | ~12 GB | Best for 16GB+ Macs | Search "Llama-3.2-3B" |
| **Mistral 7B Q4_K_M** | ~4.1 GB | ~28 GB | Best for 32GB+ Macs | Search "Mistral-7B" |

---

## Architecture

CoreLM is built with a strict 4-layer architecture:

```
┌─────────────────────────────────────────────────────┐
│                 Layer 1: App UI                     │
│            SwiftUI · MVVM · Dark Mode First         │
├─────────────────────────────────────────────────────┤
│            Layer 2: Swift Runtime Bridge            │
│     @Observable · AsyncThrowingStream · C FFI       │
├─────────────────────────────────────────────────────┤
│              Layer 3: Engine Core (C++)             │
│    GGUF Parser · Tokenizer · Transformer Forward    │
│       KV Cache · Sampler · Dequantization           │
├─────────────────────────────────────────────────────┤
│           Layer 4: Backend Execution                │
│     CPU (Accelerate + NEON)  ·  Metal (GPU)         │
└─────────────────────────────────────────────────────┘
```

### Engine Components

| Component | File(s) | Purpose |
|-----------|---------|---------|
| **GGUF Parser** | `gguf.h/cpp` | Memory-mapped GGUF v3 parsing with full metadata extraction |
| **Dequantizer** | `dequant.h/cpp` | Universal F32 dequantization for Q4_0, Q4_1, Q4_K, Q5_K, Q6_K, Q8_0, F16 |
| **Tokenizer** | `tokenizer.h/cpp` | BPE tokenizer loaded from GGUF, SentencePiece-compatible |
| **Model Config** | `model_config.h/cpp` | Auto-extraction of LLaMA hyperparameters |
| **KV Cache** | `kv_cache.h/cpp` | Per-layer GQA-aware key/value cache |
| **Sampler** | `sampler.h/cpp` | Temperature, top-k, top-p, repetition penalty, greedy mode |
| **LLaMA Runtime** | `llama.h/cpp` | Full transformer forward pass with token streaming |
| **CPU Backend** | `cpu_ops.h/cpp` | Accelerate BLAS + ARM NEON vectorized ops |
| **Metal Backend** | `metal_backend.h/mm` | 7 GPU compute kernels for parallel inference |
| **C API** | `corelm.h` | Stable C interface between engine and Swift app |

### Metal Compute Shaders

| Kernel | Operation |
|--------|-----------|
| `matvec_q4_0` | Quantized matrix-vector multiply |
| `matvec_f32` | Float matrix-vector multiply |
| `rmsnorm` | RMS normalization |
| `rope_apply` | Rotary positional encoding |
| `silu_inplace` | SiLU activation function |
| `elementwise_mul` | Element-wise multiplication |
| `elementwise_add` | Element-wise addition |

### CPU Optimizations

| Optimization | Technique |
|-------------|-----------|
| **Matrix ops** | Accelerate BLAS (`cblas_sgemv`, `cblas_sgemm`) |
| **Normalization** | vDSP vectorized RMSNorm |
| **Softmax** | 5-pass Accelerate: `maxv → vsadd → vvexpf → sve → vsmul` |
| **RoPE** | Precomputed cos/sin frequency table (shared across heads) |
| **Memory** | `madvise(MADV_WILLNEED)` for model weight pre-faulting |

---

## Project Structure

```
corelm/
├── apps/CoreLMApp/
│   ├── Sources/
│   │   ├── CoreLMApp.swift              # App entry point
│   │   ├── ContentView.swift            # Three-column layout
│   │   ├── Runtime/
│   │   │   └── CoreLMRuntime.swift      # Swift ↔ C++ bridge
│   │   ├── Views/
│   │   │   ├── Chat/                    # Chat screen, messages, composer
│   │   │   ├── Models/                  # Model list, browser, cards
│   │   │   ├── Diagnostics/             # Runtime metrics
│   │   │   ├── Settings/                # App settings
│   │   │   ├── Inspector/               # Side panels
│   │   │   └── Sidebar/                 # Navigation sidebar
│   │   ├── ViewModels/                  # MVVM view models
│   │   ├── Models/                      # Data models
│   │   ├── Stores/                      # Persistence (JSON/SQLite)
│   │   ├── Services/                    # HuggingFace API client
│   │   └── Utilities/                   # Theme, helpers
│   └── Resources/                       # Icon, Info.plist
│
├── engine/
│   ├── include/corelm.h                 # Public C API
│   ├── core/
│   │   ├── model/                       # GGUF parser, config, tokenizer, dequant
│   │   ├── tensor/                      # Tensor primitives
│   │   ├── runtime/                     # LLaMA forward pass, generation loop
│   │   ├── sampling/                    # Token sampling strategies
│   │   ├── kv_cache/                    # KV cache management
│   │   └── backends/
│   │       ├── cpu/                     # CPU ops (Accelerate + NEON)
│   │       └── metal/                   # Metal GPU backend
│   ├── metal/kernels.metal              # GPU compute shaders
│   ├── c_api/                           # C API implementation
│   └── tests/                           # Engine test suite (16 tests)
│
├── docs/                                # Architecture & design docs
├── scripts/build-app.sh                 # Build, sign, DMG, notarize
└── build/CoreLM.dmg                     # Ready-to-install DMG
```

---

## Building from Source

### Prerequisites

- macOS 14.0+
- Xcode Command Line Tools (`xcode-select --install`)
- Apple Silicon Mac

### Build Steps

```bash
# 1. Clone the repository
git clone https://github.com/Worth-Doing/CoreLM.git
cd CoreLM

# 2. Build the C++ engine
cd engine
make clean && make lib
cd ..

# 3. Build the Swift app
cd apps/CoreLMApp
swift build
cd ../..

# 4. Run
cd apps/CoreLMApp && swift run
```

### Build Signed DMG (requires Apple Developer ID)

```bash
# Edit scripts/build-app.sh with your signing identity, then:
./scripts/build-app.sh

# Notarize
xcrun notarytool submit build/CoreLM.dmg \
  --apple-id YOUR_EMAIL \
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_PASSWORD \
  --wait

xcrun stapler staple build/CoreLM.dmg
```

### Run Tests

```bash
cd engine
make test
# Output: 16 passed, 0 failed
```

---

## Technical Details

### Inference Pipeline

```
User Prompt
    │
    ▼
BPE Tokenization (SentencePiece-compatible)
    │
    ▼
Token Embedding Lookup (F32)
    │
    ▼
┌─── Transformer Layers (×N) ───────────────────────┐
│                                                     │
│  Pre-Attention RMSNorm → QKV Projection → RoPE     │
│      → KV Cache Update → Multi-Head Attention       │
│      → Output Projection → Residual                 │
│                                                     │
│  Pre-FFN RMSNorm → Gate/Up Projection               │
│      → SiLU(gate) × up → Down Projection            │
│      → Residual                                     │
│                                                     │
└────────────────────────────────────────────────────┘
    │
    ▼
Final RMSNorm → LM Head → Logits
    │
    ▼
Sampling (temperature, top-k, top-p, repeat penalty)
    │
    ▼
Token Decode → Stream to UI
```

### Memory Model

CoreLM is designed for Apple Silicon's unified memory architecture:

- **Model weights**: memory-mapped from disk (`mmap`), OS handles paging
- **Dequantized weights**: F32 in unified memory (accessible by CPU and GPU)
- **KV cache**: pre-allocated contiguous buffers per layer
- **Scratch buffers**: reused across layers, no per-inference allocation

### Security & Privacy

- **100% Local** — All inference runs on-device. No data leaves your Mac.
- **No Telemetry** — Zero tracking, zero analytics, zero phone-home.
- **No Network for Inference** — Network is only used for the optional model browser.
- **Apple Notarized** — Signed with Developer ID, verified by Apple.
- **Open Source** — Full source code available for audit.

---

## Roadmap

### v1.0 (Current)

- [x] Native macOS SwiftUI app
- [x] Custom C++ inference engine
- [x] LLaMA architecture support
- [x] Universal GGUF dequantization (Q4_0 through Q8_0)
- [x] CPU backend (Accelerate + ARM NEON)
- [x] Metal GPU backend (7 compute shaders)
- [x] BPE tokenizer from GGUF
- [x] Token streaming with async callbacks
- [x] HuggingFace model browser with download
- [x] Generation presets (Balanced, Creative, Precise, Code)
- [x] Markdown + code block rendering in chat
- [x] Runtime diagnostics and metrics
- [x] Apple notarized DMG

### v2.0 (Planned)

- [ ] Quantized inference paths (Q4_0 matvec for reduced RAM)
- [ ] Multiple model families (Qwen, Phi, Gemma)
- [ ] Embeddings runtime for semantic search
- [ ] Prompt templates and system prompts
- [ ] Chat export (Markdown, JSON)
- [ ] Model download queue with resume
- [ ] Conversation branching

### v3.0 (Future)

- [ ] Multi-model routing
- [ ] Local agents and tool use
- [ ] Speculative decoding
- [ ] Memory layer for persistent context
- [ ] Advanced Metal optimization (tiled matmul, flash attention)

---

## Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with precision by <a href="https://worthdoing.ai"><strong>WorthDoing.ai</strong></a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Worth-Doing/brand-assets/main/png/variants/04-horizontal.png" alt="WorthDoing.ai" width="300" />
</p>
