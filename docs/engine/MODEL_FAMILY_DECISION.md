# CoreLM v1 — Model Family Decision

## Decision

**CoreLM v1 will target the LLaMA architecture family.**

Specifically: the decoder-only transformer architecture used by LLaMA 2, LLaMA 3, and compatible derivatives (Mistral, CodeLlama, and community fine-tunes).

---

## Rationale

### 1. Architecture Simplicity

The LLaMA architecture is one of the cleanest modern decoder-only transformer designs:

- Pre-RMSNorm (not LayerNorm, not post-norm)
- Rotary Positional Embeddings (RoPE)
- SwiGLU activation in FFN (gate + up projection → SiLU → down projection)
- Grouped-Query Attention (GQA) in LLaMA 2 70B and all LLaMA 3 variants
- No bias terms in most linear layers
- Straightforward residual connections

This means fewer special cases in our engine code. Every component maps cleanly to a well-understood operation.

### 2. Ecosystem Dominance

LLaMA-architecture models represent the largest share of publicly available, high-quality open models:

- **Meta LLaMA 3 / 3.1 / 3.2** — flagship open models at 1B, 3B, 8B, 70B
- **Mistral 7B / Mixtral** — top-tier community models (same architecture base)
- **CodeLlama** — code-specialized variants
- **Thousands of fine-tunes** on HuggingFace

By supporting LLaMA, we immediately unlock the largest library of usable models.

### 3. Size Range

LLaMA-family models span a practical range for local inference on Apple Silicon:

| Model | Parameters | Q4 Size (approx) | Feasible On |
|-------|-----------|-------------------|-------------|
| LLaMA 3.2 1B | 1.24B | ~0.7 GB | Any Mac |
| LLaMA 3.2 3B | 3.21B | ~1.8 GB | Any Mac |
| LLaMA 3.1 8B | 8.03B | ~4.5 GB | 8GB+ Mac |
| Mistral 7B | 7.24B | ~4.1 GB | 8GB+ Mac |
| LLaMA 3.1 70B | 70.6B | ~40 GB | 64GB+ Mac |

The 1B–8B range is the sweet spot for most Mac users and provides excellent development and testing targets.

### 4. Reference Implementations Available

Multiple high-quality reference implementations exist for correctness validation:

- llama.cpp (C/C++)
- HuggingFace Transformers (Python)
- Meta's own reference code

This allows us to validate our engine output against known-correct implementations during development.

### 5. Well-Understood Tokenizer

LLaMA 3 uses a BPE tokenizer with a clean, well-documented vocabulary. Tokenizer integration is a non-trivial part of the engine — starting with a well-understood tokenizer reduces risk.

---

## Architecture Specification (v1 Target)

CoreLM v1 engine must handle models with these architectural parameters:

| Parameter | Description | Typical Values |
|-----------|-------------|----------------|
| `vocab_size` | Token vocabulary size | 32000 (LLaMA 2), 128256 (LLaMA 3) |
| `hidden_size` | Model hidden dimension | 2048, 4096 |
| `intermediate_size` | FFN intermediate dimension | 5632, 11008, 14336 |
| `num_hidden_layers` | Number of transformer blocks | 16, 22, 32 |
| `num_attention_heads` | Number of attention heads | 16, 32 |
| `num_key_value_heads` | Number of KV heads (for GQA) | 4, 8, 32 |
| `head_dim` | Dimension per attention head | 64, 128 |
| `rms_norm_eps` | RMSNorm epsilon | 1e-5, 1e-6 |
| `rope_theta` | RoPE base frequency | 10000, 500000 |
| `max_position_embeddings` | Maximum context length | 2048, 4096, 8192, 131072 |

### Transformer Block Structure

```
Input
  │
  ├──► RMSNorm (attention_norm)
  │         │
  │         ▼
  │    Q = Wq(x)     K = Wk(x)     V = Wv(x)
  │         │              │              │
  │         ▼              ▼              │
  │    RoPE(Q, pos)   RoPE(K, pos)       │
  │         │              │              │
  │         │         ┌────┴────┐         │
  │         │         │ KV Cache│         │
  │         │         │ Update  │         │
  │         │         └────┬────┘         │
  │         │              │              │
  │         ▼              ▼              ▼
  │         └──── Attention(Q, K, V) ────┘
  │                        │
  │                        ▼
  │                   Wo(attention_out)
  │                        │
  ├────── + ◄──────────────┘   (residual)
  │
  ├──► RMSNorm (ffn_norm)
  │         │
  │         ▼
  │    gate = Wgate(x)
  │    up   = Wup(x)
  │    ffn  = Wdown(SiLU(gate) * up)
  │         │
  ├────── + ◄──────────────┘   (residual)
  │
  ▼
Output
```

---

## What We Explicitly Defer (v1)

- **Mixture-of-Experts** (Mixtral) — different forward pass logic
- **Qwen architecture** — similar but different norm placement and attention details
- **Phi architecture** — partial attention patterns
- **Encoder-decoder models** — entirely different paradigm
- **Vision encoders** — multi-modal not in v1 scope

These can be added in v2/v3 once the engine architecture proves extensible.

---

## Development Model Recommendations

For engine development and testing, use these models in order:

1. **TinyLlama 1.1B** — fast iteration, fits in any Mac's memory, LLaMA architecture
2. **LLaMA 3.2 1B** — official Meta model, small, modern architecture
3. **LLaMA 3.2 3B** — slightly larger, tests GQA properly
4. **LLaMA 3.1 8B** — production-quality model, real-world performance target

Start with TinyLlama for correctness testing, graduate to LLaMA 3.2 1B for validation, then use 8B for performance benchmarking.
