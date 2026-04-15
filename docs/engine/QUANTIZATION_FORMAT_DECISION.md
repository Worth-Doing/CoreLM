# CoreLM v1 — Quantization Format Decision

## Decision

**CoreLM v1 will use GGUF as its model file format, with Q4_0 as the initial quantization type.**

Q4_K_M will be added as the second supported quantization shortly after Q4_0 works correctly.

---

## Why GGUF

### 1. Self-Contained Format

GGUF (GPT-Generated Unified Format) is a single-file model format that contains:

- Model metadata (architecture, hyperparameters, tokenizer config)
- Tokenizer vocabulary and merge rules
- All weight tensors with quantization metadata
- Alignment and versioning information

This means: **one file = one model, fully loadable with no external dependencies.**

No need to handle:
- Separate tokenizer files
- Scattered config JSONs
- Multi-file safetensors shards
- Python pickle deserialization

### 2. Industry Standard for Local Inference

GGUF is the dominant format for local LLM inference:

- Created and maintained by the llama.cpp project
- Supported by virtually all local inference tools (LM Studio, Ollama, text-generation-webui)
- Thousands of pre-quantized models available on HuggingFace
- Active community producing high-quality quantizations

Users already have GGUF files. CoreLM should load what users already have.

### 3. Clean Binary Format

GGUF has a well-defined binary layout:

```
┌──────────────────────────────┐
│  Magic: "GGUF" (4 bytes)     │
│  Version: uint32             │
│  Tensor count: uint64        │
│  Metadata KV count: uint64   │
├──────────────────────────────┤
│  Metadata Key-Value pairs    │
│  (architecture, tokenizer,   │
│   hyperparameters, etc.)     │
├──────────────────────────────┤
│  Tensor descriptors          │
│  (name, shape, dtype, offset)│
├──────────────────────────────┤
│  Alignment padding           │
├──────────────────────────────┤
│  Tensor data                 │
│  (contiguous weight blocks)  │
└──────────────────────────────┘
```

This is straightforward to parse in C++ without external libraries. The data section can be memory-mapped directly.

### 4. Memory-Mapping Friendly

The tensor data section is designed for direct memory mapping:

- Tensors are stored contiguously with known offsets
- Alignment guarantees allow direct pointer access
- On Apple Silicon with unified memory, a memory-mapped GGUF file means weights go from disk → unified memory with minimal overhead
- The OS virtual memory system handles paging automatically

---

## Why Q4_0 First

### What is Q4_0?

Q4_0 is a block quantization scheme:

- Each block contains **32 weights**
- Each weight is stored as a **4-bit integer** (16 possible values)
- Each block stores one **FP16 scale factor** (the `d` value)
- Dequantization: `weight = q * d` where `q` is the 4-bit signed integer

### Block Layout

```
struct block_q4_0 {
    float16_t d;          // 2 bytes — scale factor
    uint8_t   qs[16];     // 16 bytes — 32 × 4-bit quantized weights
};                        // Total: 18 bytes per 32 weights
```

Each `uint8_t` in `qs` holds two 4-bit values (packed). Values are in range [-8, 7].

### Memory Efficiency

| Format | Bits/Weight | 7B Model Size |
|--------|-----------|---------------|
| FP32 | 32 | ~28 GB |
| FP16 | 16 | ~14 GB |
| Q8_0 | 8.5 | ~7.5 GB |
| **Q4_0** | **4.5** | **~3.8 GB** |
| Q4_K_M | ~4.8 | ~4.1 GB |

Q4_0 is compact enough to fit a 7B model comfortably on an 8GB Mac.

### Why Q4_0 Before Q4_K_M?

1. **Simplest dequantization logic** — just a scale and an integer multiply. No min values, no super-blocks, no importance matrices. Perfect for getting the engine working correctly.

2. **Easy to validate** — dequantize a block, compare against known reference values. If our Q4_0 dequant is wrong, we know immediately.

3. **Stepping stone** — once Q4_0 works, Q4_K_M adds k-quant improvements (per-sub-block scales and mins) on the same foundation.

---

## Q4_K_M (Second Priority)

### What is Q4_K_M?

Q4_K_M uses the "k-quant" scheme with sub-blocks:

- A **super-block** of 256 weights
- Divided into 8 **sub-blocks** of 32 weights each
- Each sub-block has its own 6-bit scale and 6-bit minimum
- Super-block has FP16 master scale and master minimum
- Weights are 4-bit quantized within each sub-block

### Why Q4_K_M Matters

- Better quality than Q4_0 at similar size (the sub-block structure captures weight distribution better)
- Most commonly recommended quantization for daily use
- Most GGUF downloads on HuggingFace use Q4_K_M

### Implementation Complexity

Q4_K_M is more complex than Q4_0 but still tractable:

- Super-block header parsing
- Sub-block scale/min unpacking (6-bit packed values)
- Two-level dequantization (sub-block relative to super-block)

This is manageable once Q4_0 proves the dequantization + matmul pipeline works.

---

## GGUF Parser Requirements

### Header Parsing

The parser must:

1. Validate magic bytes (`GGUF`)
2. Read and validate version (support version 3, the current standard)
3. Read tensor count and metadata count
4. Parse all metadata key-value pairs

### Metadata Extraction

Critical metadata keys to extract:

| Key | Purpose |
|-----|---------|
| `general.architecture` | Model family (must be `llama` for v1) |
| `general.name` | Model display name |
| `general.file_type` | Quantization type indicator |
| `llama.context_length` | Maximum context window |
| `llama.embedding_length` | Hidden size |
| `llama.feed_forward_length` | FFN intermediate size |
| `llama.block_count` | Number of transformer layers |
| `llama.attention.head_count` | Number of attention heads |
| `llama.attention.head_count_kv` | Number of KV heads (for GQA) |
| `llama.rope.freq_base` | RoPE theta |
| `llama.attention.layer_norm_rms_epsilon` | RMSNorm epsilon |
| `tokenizer.ggml.model` | Tokenizer type |
| `tokenizer.ggml.tokens` | Vocabulary tokens |
| `tokenizer.ggml.scores` | Token scores |
| `tokenizer.ggml.token_type` | Token types (normal, special, etc.) |
| `tokenizer.ggml.merges` | BPE merge rules |

### Tensor Descriptor Parsing

For each tensor descriptor:

1. Read tensor name (string)
2. Read number of dimensions (uint32)
3. Read shape (uint64 per dimension)
4. Read data type enum (maps to Q4_0, Q4_K_M, F16, F32, etc.)
5. Read data offset (uint64, relative to data section start)

### Tensor Data Access

- Compute absolute file offset for each tensor
- Memory-map the data section
- Provide typed pointer access: `tensor_data(name) → (void*, size, dtype)`
- Validate that reported sizes match expected sizes given shape + dtype

### Validation Checks

The parser must validate:

- [ ] Magic bytes are correct
- [ ] Version is supported
- [ ] Architecture is `llama`
- [ ] All required metadata keys are present
- [ ] Tensor shapes are consistent with architecture config
- [ ] No tensor data extends past end of file
- [ ] Quantization type matches what we support
- [ ] Tensor alignment is correct

---

## Dequantization Implementation Plan

### Q4_0 Dequantization (CPU Reference)

```cpp
// Pseudocode
void dequantize_q4_0(const block_q4_0* block, float* output) {
    float d = half_to_float(block->d);
    for (int i = 0; i < 16; i++) {
        int8_t lo = (block->qs[i] & 0x0F) - 8;  // low nibble
        int8_t hi = (block->qs[i] >> 4) - 8;     // high nibble
        output[2*i]     = lo * d;
        output[2*i + 1] = hi * d;
    }
}
```

### Q4_0 Dot Product (CPU Reference)

For matrix-vector multiplication with quantized weights, we can compute the dot product directly on quantized values without full dequantization:

```cpp
// Pseudocode — dot product of quantized block with float vector
float dot_q4_0(const block_q4_0* block, const float* x) {
    float sum = 0.0f;
    float d = half_to_float(block->d);
    for (int i = 0; i < 16; i++) {
        int8_t lo = (block->qs[i] & 0x0F) - 8;
        int8_t hi = (block->qs[i] >> 4) - 8;
        sum += lo * x[2*i] + hi * x[2*i + 1];
    }
    return sum * d;
}
```

This is the hot path for inference performance. Optimize this carefully.

---

## What We Explicitly Defer

- **Q5_0, Q5_1** — less commonly used
- **Q8_0** — large file sizes, less practical for local use
- **Q2_K, Q3_K** — too aggressive quality loss for v1
- **Q5_K_M, Q6_K** — nice to have but not essential for launch
- **GPTQ, AWQ, EXL2** — different quantization ecosystems entirely
- **FP16 full precision** — useful for debugging but not the primary use case
- **IQ quantizations** — importance-matrix quants, complex to implement

These can be added incrementally. The block-based dequantization architecture generalizes naturally to other GGUF quantization types.

---

## Tradeoff Acknowledgment

### Q4_0 Quality

Q4_0 is not the highest quality quantization available. It applies uniform scaling to each block, which loses information compared to k-quant methods. For a 7B model:

- Q4_0 perplexity is measurably worse than Q4_K_M
- For 1B-3B models, the quality difference is more noticeable

This is acceptable for v1 because:

1. The goal is **correctness first** — prove the engine works end-to-end
2. Q4_K_M follows immediately after
3. Users can still have useful conversations with Q4_0 models
4. Many Q4_0 quantizations are available for download

### GGUF Lock-In

Choosing GGUF means we depend on an external format specification. Risks:

- Format could evolve in breaking ways (mitigated: version field, we target v3)
- We inherit llama.cpp's naming conventions for tensors (acceptable: it's a standard)
- Some models only exist in safetensors/HF format (mitigated: conversion tools exist, and we can add safetensors support in v2)

The benefits of instant access to thousands of pre-quantized models far outweigh these risks.
