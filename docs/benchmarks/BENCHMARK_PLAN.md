# CoreLM — Benchmark and Correctness Validation Plan

## Goals

1. **Correctness** — Prove that CoreLM produces the same output as reference implementations for identical inputs and settings.
2. **Performance** — Measure latency and throughput at every stage of inference and track them over time.
3. **Regression detection** — Any code change that degrades correctness or performance beyond threshold is caught immediately.

---

## Part 1: Correctness Validation

### 1.1 Reference Implementation

Use **llama.cpp** as the reference implementation for correctness comparison.

Justification:
- Same model format (GGUF)
- Same quantization types (Q4_0, Q4_K_M)
- Widely tested and validated by the community
- Deterministic output with fixed seed

### 1.2 Correctness Test Levels

#### Level 1 — Component Unit Tests

Test individual engine components in isolation.

| Component | Test | Validation |
|-----------|------|------------|
| GGUF Parser | Parse known-good GGUF file | Metadata matches expected values |
| GGUF Parser | Parse corrupt/truncated file | Returns appropriate error |
| Tensor | Shape arithmetic | Correct strides, element counts, byte sizes |
| Tensor | View slicing | Correct offsets, no out-of-bounds |
| Q4_0 Dequant | Dequantize known block | Output matches hand-computed values |
| Q4_K_M Dequant | Dequantize known block | Output matches hand-computed values |
| RMSNorm | Norm of known vector | Output matches numpy reference (±1e-5) |
| RoPE | Rotate known Q, K vectors | Output matches reference (±1e-5) |
| Softmax | Softmax of known logits | Output matches reference, sums to 1.0 |
| SiLU | Activation of known input | Output matches reference (±1e-6) |
| MatMul | Small matrix multiply | Output matches Accelerate/numpy (±1e-4) |
| Sampler | Temperature scaling | Correct probability distribution |
| Sampler | Top-K filtering | Correct top-K selection |
| Sampler | Top-P filtering | Correct nucleus selection |
| Sampler | Greedy (temp=0) | Selects argmax token |
| KV Cache | Insert and retrieve | Correct values at correct positions |
| KV Cache | Reset | Clean state after reset |

#### Level 2 — Layer-Level Tests

Test complete transformer layer forward pass.

| Test | Method |
|------|--------|
| Single layer forward | Feed known input tensor through one transformer block. Compare output against reference (llama.cpp debug output or Python reference). Tolerance: ±1e-3 per element. |
| Attention output | Compare QKV path output for a small context. Verify attention weights sum to 1.0 per query position. |
| FFN output | Compare gate/up/down projection results for known input. |

#### Level 3 — End-to-End Generation Tests

Test full generation pipeline.

| Test | Setup | Validation |
|------|-------|------------|
| Deterministic greedy | Seed=42, temp=0, fixed prompt | Exact token-for-token match with llama.cpp output |
| Deterministic sampled | Seed=42, temp=0.7, top_k=40 | Exact token-for-token match with llama.cpp (same seed, same sampler) |
| Long generation | 500 tokens, greedy | No NaN, no repeated degeneration, tokens make sense |
| Multi-turn | Two prompt/response pairs in same session | Context handled correctly, no corruption |
| Context full | Generate until context is full | Graceful handling, correct error or truncation |

### 1.3 Reference Test Vectors

Create and store reference test data:

```
engine/tests/
├── data/
│   ├── reference_logits_layer0.bin    # Known logits after layer 0
│   ├── reference_logits_final.bin     # Known final logits
│   ├── reference_tokens_greedy.txt    # Expected greedy output
│   ├── reference_tokens_sampled.txt   # Expected sampled output (seed=42)
│   ├── reference_q4_0_block.bin       # Known Q4_0 block for dequant test
│   ├── reference_q4_km_block.bin      # Known Q4_K_M block for dequant test
│   ├── reference_rmsnorm.bin          # Input/output pair for RMSNorm
│   ├── reference_rope.bin             # Input/output pair for RoPE
│   └── reference_attention.bin        # Input/output pair for attention
```

Generation script (Python):

```python
# scripts/generate_test_vectors.py
# Uses HuggingFace transformers or llama-cpp-python to produce
# reference outputs for known inputs with known parameters.
# Outputs are saved as binary files for C++ test comparison.
```

### 1.4 Test Model

Use **TinyLlama 1.1B Q4_0** as the primary test model:
- Small enough to load instantly
- LLaMA architecture (our target)
- Fast enough for CI-like test runs
- Available as GGUF on HuggingFace

For unit/component tests, use synthetic small tensors (no model file needed).

### 1.5 Correctness Tolerances

| Level | Tolerance | Rationale |
|-------|-----------|-----------|
| Dequantization | Exact (bit-perfect) | Pure integer arithmetic, must match |
| Element-wise ops (SiLU, add) | ±1e-6 | FP32 arithmetic, negligible error |
| RMSNorm, Softmax | ±1e-5 | Reduction ops accumulate small errors |
| MatMul (small) | ±1e-4 | Accumulation across many elements |
| Full layer output | ±1e-3 | Errors compound through ops |
| Final logits | ±1e-2 | 32 layers of accumulation |
| Token output (greedy) | Exact match | Same logits → same argmax |
| Token output (sampled) | Exact match with same seed | Same RNG state → same choices |

---

## Part 2: Performance Benchmarks

### 2.1 Metrics to Measure

| Metric | Unit | Measurement Point |
|--------|------|--------------------|
| Model load time | ms | Start of `clm_model_load` → return |
| Prompt evaluation time | ms | Start of prompt eval → first token ready |
| Prompt evaluation speed | tok/s | prompt_tokens / prompt_eval_time |
| Time to first token | ms | `clm_generate` called → first token callback |
| Generation speed (steady state) | tok/s | tokens_generated / generation_time |
| Total generation time | ms | First token → last token |
| Peak memory (model) | MB | After model load, before generation |
| Peak memory (total) | MB | During generation (model + KV cache + scratch) |
| KV cache memory | MB | Allocated cache size |
| KV cache utilization | % | Tokens in cache / max cache size |

### 2.2 Benchmark Prompts

Fixed prompts for reproducible benchmarks:

```
Prompt A (Short, factual):
"What is the capital of France?"

Prompt B (Medium, explanatory):
"Explain how a transformer neural network processes a sentence, step by step."

Prompt C (Long context):
[512-token technical passage] + "Summarize the key points above."

Prompt D (Code generation):
"Write a Python function that implements binary search on a sorted list."

Prompt E (Stress test — long generation):
"Write a detailed essay about the history of computing, covering at least the following topics: Charles Babbage, Alan Turing, ENIAC, the transistor, integrated circuits, personal computers, the internet, and artificial intelligence."
```

### 2.3 Benchmark Configurations

| Config Name | Model | Quant | Context | Backend | Purpose |
|-------------|-------|-------|---------|---------|---------|
| `baseline-cpu-small` | TinyLlama 1.1B | Q4_0 | 2048 | CPU | Fast iteration baseline |
| `baseline-cpu-3b` | LLaMA 3.2 3B | Q4_0 | 4096 | CPU | Mid-size CPU reference |
| `baseline-cpu-8b` | LLaMA 3.1 8B | Q4_0 | 4096 | CPU | Full-size CPU reference |
| `metal-small` | TinyLlama 1.1B | Q4_0 | 2048 | Metal | Metal correctness check |
| `metal-3b` | LLaMA 3.2 3B | Q4_0 | 4096 | Metal | Metal performance target |
| `metal-8b` | LLaMA 3.1 8B | Q4_0 | 4096 | Metal | Metal production target |
| `q4km-cpu-3b` | LLaMA 3.2 3B | Q4_K_M | 4096 | CPU | Q4_K_M validation |

### 2.4 Benchmark Protocol

Each benchmark run:

1. Cold start: Quit app, clear OS file cache (`purge` on macOS)
2. Measure model load time
3. Generate with Prompt A (short) — measure TTFT and generation speed
4. Generate with Prompt B (medium) — measure full generation metrics
5. Generate with Prompt E (long) — measure sustained generation speed
6. Record all metrics to JSON

Repeat 3 times. Report median values.

### 2.5 Benchmark Output Format

```json
{
    "timestamp": "2026-04-14T15:30:00Z",
    "config": "baseline-cpu-3b",
    "system": {
        "chip": "M2 Pro",
        "memory_gb": 16,
        "os_version": "macOS 15.4"
    },
    "model": {
        "name": "LLaMA 3.2 3B",
        "quantization": "Q4_0",
        "file_size_mb": 1800
    },
    "results": {
        "model_load_time_ms": 1234,
        "prompt_a": {
            "prompt_tokens": 8,
            "prompt_eval_ms": 56,
            "prompt_eval_tok_per_sec": 142.8,
            "generated_tokens": 64,
            "time_to_first_token_ms": 87,
            "generation_ms": 1680,
            "generation_tok_per_sec": 38.1,
            "total_time_ms": 1736
        },
        "prompt_b": { "..." : "..." },
        "prompt_e": { "..." : "..." },
        "memory": {
            "model_mb": 1800,
            "kv_cache_mb": 256,
            "scratch_mb": 48,
            "total_mb": 2104
        }
    }
}
```

### 2.6 Performance Targets (v1)

These are goals, not hard requirements. They guide optimization priority.

| Metric | Target (8B Q4_0, M2 Pro) | Notes |
|--------|--------------------------|-------|
| Model load | < 3s | Memory-mapped, minimal parsing |
| Prompt eval (short) | > 100 tok/s | CPU baseline |
| TTFT (short prompt) | < 200ms | User-perceived responsiveness |
| Generation speed | > 20 tok/s (CPU) | Readable streaming |
| Generation speed | > 40 tok/s (Metal) | Smooth streaming |
| Memory overhead | < 20% above model size | Efficient KV cache + scratch |

### 2.7 Comparison Methodology

For each benchmark configuration, also run the same prompt through llama.cpp with equivalent settings and record:

- llama.cpp prompt eval speed
- llama.cpp generation speed
- llama.cpp memory usage

This provides a concrete comparison point. The goal is not necessarily to beat llama.cpp in v1, but to understand where CoreLM stands and identify optimization opportunities.

---

## Part 3: Regression Testing

### 3.1 Automated Test Suite

```
engine/tests/
├── test_gguf_parser.cpp        # GGUF format parsing
├── test_tensor.cpp             # Tensor primitives
├── test_dequant.cpp            # Quantization/dequantization
├── test_ops.cpp                # Individual operations
├── test_sampler.cpp            # Sampling strategies
├── test_kv_cache.cpp           # KV cache management
├── test_generation.cpp         # End-to-end generation
├── test_api.cpp                # C API surface tests
└── data/                       # Reference test vectors
```

### 3.2 Test Categories

| Category | Frequency | Duration |
|----------|-----------|----------|
| Unit tests (no model) | Every build | < 5 seconds |
| Component tests (no model) | Every build | < 10 seconds |
| Integration tests (tiny model) | Before merge | < 60 seconds |
| Full benchmarks | Weekly / on-demand | ~10 minutes |

### 3.3 Correctness Regression Detection

After each code change that touches the engine:

1. Run unit tests → all must pass
2. Run greedy generation with TinyLlama + Prompt A → compare token output against reference
3. If tokens differ → **regression detected**, investigate before merging

### 3.4 Performance Regression Detection

Compare benchmark results against the last known baseline:

| Metric | Alert Threshold |
|--------|----------------|
| Generation speed | > 10% slower |
| TTFT | > 20% slower |
| Prompt eval speed | > 10% slower |
| Memory usage | > 15% increase |

---

## Part 4: Testing the Swift Bridge and App

### 4.1 Bridge Tests

| Test | Method |
|------|--------|
| Load valid model | Call `runtime.loadModel()`, verify state becomes `.ready` |
| Load invalid file | Call `runtime.loadModel()` with non-GGUF file, verify error |
| Load unsupported arch | Call with unsupported architecture GGUF, verify specific error |
| Create session | Load model, create session, verify no error |
| Generate tokens | Load + create session + generate with Prompt A, verify tokens received |
| Cancel generation | Start generation, cancel after 5 tokens, verify stream ends |
| Session reset | Generate, reset, generate again — verify context is clean |
| Metrics query | After generation, query metrics, verify non-zero values |
| Concurrent cancel | Cancel from main thread while generating on background thread |
| Memory cleanup | Load, generate, unload — verify no leaks (Instruments) |

### 4.2 App UI Tests

| Test | Method |
|------|--------|
| App launches | App opens without crash, welcome screen shown |
| New chat | Tap "New Chat", verify chat screen appears |
| Model import | Import .gguf via file picker, verify model appears in list |
| Model load | Load model from model list, verify state change |
| Send message | Type prompt, send, verify message appears in chat |
| Settings persistence | Change setting, restart app, verify setting retained |
| Chat persistence | Create chat with messages, restart app, verify chat restored |
| Sidebar navigation | Navigate to each section, verify correct screen shown |
| Inspector toggle | Toggle inspector, verify panel appears/disappears |

---

## Part 5: Instrumentation Implementation

### 5.1 Engine-Side Timing

```cpp
// engine/core/runtime/metrics.h
struct InferenceMetrics {
    double model_load_ms     = 0;
    double prompt_eval_ms    = 0;
    int    prompt_tokens     = 0;
    double generation_ms     = 0;
    int    generation_tokens = 0;
    double first_token_ms    = 0;

    // Derived
    double prompt_tok_per_sec() const;
    double generation_tok_per_sec() const;

    // Memory
    int64_t memory_model  = 0;
    int64_t memory_cache  = 0;
    int64_t memory_scratch = 0;

    // Context
    int context_used = 0;
    int context_max  = 0;

    void reset();
};
```

Timing uses `mach_absolute_time()` on macOS for high-resolution, low-overhead measurement.

### 5.2 Timing Points in Generation Loop

```
clm_generate() called
    ├── [timer: start prompt_eval]
    │   tokenize(prompt)
    │   for each batch of prompt tokens:
    │       forward_pass(batch)
    ├── [timer: end prompt_eval]
    │
    ├── [timer: start generation]
    │   sample first token
    ├── [timer: record first_token]
    │   callback(token)
    │
    │   loop:
    │       forward_pass(single token)
    │       sample next token
    │       callback(token)
    │       if stop condition → break
    │
    ├── [timer: end generation]
    └── return
```

---

## Execution Order

1. **Now (Phase 0):** Establish reference test vectors for Q4_0 dequant, RMSNorm, RoPE, Softmax using Python scripts.
2. **Phase 2 (CPU engine):** Implement unit tests alongside each engine module. Run greedy generation test as the Phase 2 exit gate.
3. **Phase 3 (Bridge):** Implement bridge tests. Full integration test (app → bridge → engine → token output) as exit gate.
4. **Phase 4 (Chat integration):** Manual UI testing + automated UI state tests.
5. **Phase 5 (Metal):** CPU-vs-Metal correctness comparison tests. Performance benchmarks begin.
6. **Ongoing:** Run regression suite before any merge. Weekly full benchmark runs.
