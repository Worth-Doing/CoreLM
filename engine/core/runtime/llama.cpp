#include "llama.h"
#include "../backends/backend.h"
#include "../backends/cpu/cpu_ops.h"
#include "../model/dequant.h"
#include <mach/mach_time.h>
#include <cstring>
#include <cstdio>

namespace corelm {

static double now_ms() {
    static mach_timebase_info_data_t info;
    if (info.denom == 0) mach_timebase_info(&info);
    return (double)mach_absolute_time() * info.numer / info.denom / 1e6;
}

// ── Weight mapping ─────────────────────────────────────────

// Compute row-major shape from GGUF column-major shape
static Shape gguf_shape(const GGUFTensorInfo* ti) {
    if (ti->ndim == 1) {
        return Shape(ti->shape[0]);
    } else if (ti->ndim == 2) {
        return Shape(ti->shape[1], ti->shape[0]); // swap to row-major
    } else if (ti->ndim == 3) {
        return Shape(ti->shape[2], ti->shape[1], ti->shape[0]);
    } else {
        Shape shape;
        shape.ndim = ti->ndim;
        for (int d = 0; d < (int)ti->ndim; d++) {
            shape.dims[d] = ti->shape[ti->ndim - 1 - d];
        }
        return shape;
    }
}

// Load a tensor from GGUF, dequantizing ALL types to F32.
// This guarantees correctness regardless of quantization format.
static Tensor tensor_from_gguf(const GGUFFile& gguf, const std::string& name) {
    auto* ti = gguf.find_tensor(name);
    if (!ti) return Tensor();

    const void* data = gguf.tensor_data(name);
    if (!data) return Tensor();

    Shape shape = gguf_shape(ti);
    int64_t numel = shape.numel();

    // F32: wrap directly (no copy)
    if (ti->dtype == GGUFDType::F32) {
        return Tensor::wrap_const(data, shape, DType::F32);
    }

    // All other types: dequantize to F32
    if (!is_dtype_supported(ti->dtype)) {
        fprintf(stderr, "[CoreLM] Warning: tensor '%s' has unsupported type %d, skipping\n",
                name.c_str(), (int)ti->dtype);
        return Tensor();
    }

    // Dequantize to a flat F32 buffer, then reshape
    Tensor flat = dequantize_to_f32(data, numel, ti->dtype);

    // Reshape: the dequantized tensor is Shape(numel), we need the proper 2D shape
    if (shape.ndim == 1) {
        return flat; // already correct
    }

    // For 2D+, we need to re-wrap with the correct shape
    Tensor reshaped = Tensor::alloc(shape, DType::F32);
    std::memcpy(reshaped.data(), flat.data(), numel * sizeof(float));
    return reshaped;
}

bool LlamaModel::map_weights(const GGUFFile& gguf, std::string& error) {
    // Token embedding
    weights_.token_embedding = tensor_from_gguf(gguf, "token_embd.weight");
    if (!weights_.token_embedding.data()) {
        error = "missing token_embd.weight";
        return false;
    }

    // Output norm
    weights_.output_norm = tensor_from_gguf(gguf, "output_norm.weight");
    if (!weights_.output_norm.data()) {
        error = "missing output_norm.weight";
        return false;
    }

    // Output (lm_head) — may be tied to embedding
    weights_.output = tensor_from_gguf(gguf, "output.weight");
    if (!weights_.output.data()) {
        // Tied embeddings: lm_head shares weights with token_embd
        weights_.output = weights_.token_embedding;
    }

    // Per-layer weights
    weights_.layers.resize(config_.num_layers);
    for (uint32_t l = 0; l < config_.num_layers; l++) {
        auto& lw = weights_.layers[l];
        std::string prefix = "blk." + std::to_string(l) + ".";

        lw.attn_norm = tensor_from_gguf(gguf, prefix + "attn_norm.weight");
        lw.ffn_norm  = tensor_from_gguf(gguf, prefix + "ffn_norm.weight");
        lw.wq       = tensor_from_gguf(gguf, prefix + "attn_q.weight");
        lw.wk       = tensor_from_gguf(gguf, prefix + "attn_k.weight");
        lw.wv       = tensor_from_gguf(gguf, prefix + "attn_v.weight");
        lw.wo       = tensor_from_gguf(gguf, prefix + "attn_output.weight");
        lw.w_gate   = tensor_from_gguf(gguf, prefix + "ffn_gate.weight");
        lw.w_up     = tensor_from_gguf(gguf, prefix + "ffn_up.weight");
        lw.w_down   = tensor_from_gguf(gguf, prefix + "ffn_down.weight");

        if (!lw.wq.data() || !lw.wk.data() || !lw.wv.data() || !lw.wo.data()) {
            error = "missing attention weights at layer " + std::to_string(l);
            return false;
        }
        if (!lw.w_gate.data() || !lw.w_up.data() || !lw.w_down.data()) {
            error = "missing FFN weights at layer " + std::to_string(l);
            return false;
        }
    }

    return true;
}

// ── Scratch allocation ─────────────────────────────────────

void LlamaModel::alloc_scratch() {
    int h = config_.hidden_size;
    int inter = config_.intermediate_size;
    int vocab = config_.vocab_size;
    int nh = config_.num_heads;
    int nkv = config_.num_kv_heads;
    int hd = config_.head_dim;
    int ctx = config_.max_context_length;

    x_        = Tensor::alloc(Shape(h), DType::F32);
    xb_       = Tensor::alloc(Shape(h), DType::F32);
    xb2_      = Tensor::alloc(Shape(h), DType::F32);
    q_        = Tensor::alloc(Shape(nh * hd), DType::F32);
    k_        = Tensor::alloc(Shape(nkv * hd), DType::F32);
    v_        = Tensor::alloc(Shape(nkv * hd), DType::F32);
    att_      = Tensor::alloc(Shape(nh, ctx), DType::F32);
    ffn_gate_ = Tensor::alloc(Shape(inter), DType::F32);
    ffn_up_   = Tensor::alloc(Shape(inter), DType::F32);
    ffn_down_ = Tensor::alloc(Shape(h), DType::F32);
    logits_   = Tensor::alloc(Shape(vocab), DType::F32);
}

// ── Load ────────────────────────────────────────────────────

bool LlamaModel::load(const std::string& path, std::string& error) {
    double t0 = now_ms();

    auto result = gguf_parse(path);
    if (!result.success) {
        error = result.error;
        return false;
    }

    gguf_ = std::move(result.file);
    config_ = ModelConfig::from_gguf(*gguf_);

    if (config_.architecture == "clip" || config_.architecture == "mllama_vision") {
        error = "This is a vision encoder file (CLIP), not a language model. Download the main model file instead.";
        return false;
    }
    if (config_.architecture != "llama") {
        error = "Unsupported architecture: " + config_.architecture + ". CoreLM supports LLaMA-family models.";
        return false;
    }

    // Load tokenizer
    if (!tokenizer_.load_from_gguf(*gguf_)) {
        error = "failed to load tokenizer";
        return false;
    }

    // Patch vocab_size from tokenizer if GGUF metadata was inconsistent
    if (config_.vocab_size == 0) {
        config_.vocab_size = tokenizer_.vocab_size();
    }

    // Map weights
    if (!map_weights(*gguf_, error)) {
        return false;
    }

    // Advise kernel on model memory access pattern
    if (gguf_->data_base && gguf_->file_size > 0) {
        cpu::advise_sequential(gguf_->data_base, gguf_->file_size);
        cpu::advise_willneed(gguf_->data_base, gguf_->file_size);
    }

    // Allocate scratch
    alloc_scratch();

    // Initialize KV cache
    kv_cache_.init(config_.num_layers, config_.max_context_length,
                   config_.num_kv_heads, config_.head_dim);

    // Initialize backend
    backend_ = create_backend(requested_backend_);
    if (!backend_) {
        backend_ = std::make_unique<CPUBackend>();
    }

    loaded_ = true;
    metrics_.model_load_ms = now_ms() - t0;
    metrics_.context_max = config_.max_context_length;

    // Estimate memory
    metrics_.memory_model = gguf_->file_size;
    metrics_.memory_cache = kv_cache_.memory_bytes();

    return true;
}

void LlamaModel::set_backend(const std::string& name) {
    requested_backend_ = name;
    if (loaded_) {
        backend_ = create_backend(name);
        if (!backend_) {
            backend_ = std::make_unique<CPUBackend>();
        }
    }
}

// ── Forward pass (single token) ─────────────────────────────

void LlamaModel::forward(int token_id, int pos) {
    int nh = config_.num_heads;
    int nkv = config_.num_kv_heads;
    int hd = config_.head_dim;
    int gqa = config_.gqa_ratio();

    // 1. Token embedding
    backend_->embedding_lookup(weights_.token_embedding, token_id, x_);

    // 2. Transformer layers
    for (uint32_t l = 0; l < config_.num_layers; l++) {
        auto& lw = weights_.layers[l];

        // ── Pre-attention RMSNorm ──
        backend_->rmsnorm(x_, lw.attn_norm, xb_, config_.rms_norm_eps);

        // ── QKV projections ──
        backend_->matvec(lw.wq, xb_, q_);
        backend_->matvec(lw.wk, xb_, k_);
        backend_->matvec(lw.wv, xb_, v_);

        // ── RoPE ──
        backend_->rope(q_.data_f32(), k_.data_f32(), hd, nh, nkv, pos, config_.rope_theta);

        // ── Update KV cache ──
        kv_cache_.update(l, pos, k_.data_f32(), v_.data_f32());

        // ── Multi-head attention ──
        // Attention score computation stays on CPU — it's memory-bound and
        // the KV cache is already in CPU memory. GPU dispatch overhead
        // would hurt more than help for single-token generation.
        int seq_len = pos + 1;
        float scale = 1.0f / sqrtf((float)hd);

        for (int head = 0; head < nh; head++) {
            float* q_head = q_.data_f32() + head * hd;
            float* att_scores = att_.data_f32() + head * config_.max_context_length;

            int kv_head = head / gqa;

            // Compute attention scores: Q @ K^T
            for (int t = 0; t < seq_len; t++) {
                const float* k_t = kv_cache_.key_at(l, kv_head, t);
                float score = 0.0f;
                for (int d = 0; d < hd; d++) {
                    score += q_head[d] * k_t[d];
                }
                att_scores[t] = score * scale;
            }

            // Softmax
            backend_->softmax(att_scores, seq_len);

            // Weighted sum of values
            float* xb_head = xb_.data_f32() + head * hd;
            std::memset(xb_head, 0, hd * sizeof(float));

            for (int t = 0; t < seq_len; t++) {
                const float* v_t = kv_cache_.value_at(l, kv_head, t);
                float w = att_scores[t];
                for (int d = 0; d < hd; d++) {
                    xb_head[d] += w * v_t[d];
                }
            }
        }

        // ── Attention output projection ──
        backend_->matvec(lw.wo, xb_, xb2_);

        // ── Residual connection ──
        backend_->add_inplace(x_, xb2_);

        // ── Pre-FFN RMSNorm ──
        backend_->rmsnorm(x_, lw.ffn_norm, xb_, config_.rms_norm_eps);

        // ── FFN: SwiGLU ──
        backend_->matvec(lw.w_gate, xb_, ffn_gate_);
        backend_->matvec(lw.w_up,   xb_, ffn_up_);

        // SiLU(gate) * up
        backend_->silu_inplace(ffn_gate_);
        backend_->mul_inplace(ffn_gate_, ffn_up_);

        // Down projection
        backend_->matvec(lw.w_down, ffn_gate_, ffn_down_);

        // ── Residual connection ──
        backend_->add_inplace(x_, ffn_down_);
    }

    // 3. Final RMSNorm
    backend_->rmsnorm(x_, weights_.output_norm, xb_, config_.rms_norm_eps);

    // 4. LM head: logits = output_weight @ x
    backend_->matvec(weights_.output, xb_, logits_);
}

// ── Forward batch (prompt evaluation) ───────────────────────

void LlamaModel::forward_batch(const std::vector<int32_t>& tokens, int start_pos) {
    // For simplicity, evaluate prompt tokens one at a time
    // A production engine would batch the prompt evaluation for better throughput
    for (int i = 0; i < (int)tokens.size(); i++) {
        if (cancelled_.load(std::memory_order_relaxed)) return;
        forward(tokens[i], start_pos + i);
    }
}

// ── Generation ──────────────────────────────────────────────

bool LlamaModel::generate(const std::string& prompt,
                            const SamplerConfig& sampler_config,
                            int max_tokens,
                            int context_size,
                            TokenCallback on_token,
                            std::string& error) {
    if (!loaded_) {
        error = "model not loaded";
        return false;
    }

    cancelled_.store(false, std::memory_order_relaxed);

    // Apply context size limit
    if (context_size > 0 && context_size < (int)config_.max_context_length) {
        // Use requested context size (don't reallocate, just limit)
    }

    // Tokenize
    auto tokens = tokenizer_.encode(prompt, true);
    if (tokens.empty()) {
        error = "tokenization produced no tokens";
        return false;
    }

    int prompt_len = (int)tokens.size();
    if (prompt_len >= (int)config_.max_context_length) {
        error = "prompt too long for context window";
        return false;
    }

    // Initialize sampler
    Sampler sampler;
    sampler.init(sampler_config);

    // Reset metrics
    metrics_.prompt_tokens = prompt_len;
    metrics_.generation_tokens = 0;
    metrics_.context_used = prompt_len;

    // ── Prompt evaluation ──
    double t_prompt_start = now_ms();
    forward_batch(tokens, 0);
    double t_prompt_end = now_ms();
    metrics_.prompt_eval_ms = t_prompt_end - t_prompt_start;

    if (cancelled_.load(std::memory_order_relaxed)) {
        return true; // cancelled is not an error
    }

    // ── Generation loop ──
    double t_gen_start = now_ms();
    bool first_token = true;
    std::vector<int32_t> recent_tokens(tokens);
    int pos = prompt_len;

    for (int i = 0; i < max_tokens; i++) {
        if (cancelled_.load(std::memory_order_relaxed)) break;
        if (pos >= (int)config_.max_context_length) break;

        // Sample
        float* logit_ptr = logits_.data_f32();
        sampler.apply_repeat_penalty(logit_ptr, config_.vocab_size, recent_tokens);
        int32_t next_token = sampler.sample(logit_ptr, config_.vocab_size);

        if (first_token) {
            metrics_.first_token_ms = now_ms() - t_gen_start;
            first_token = false;
        }

        // Check EOS
        if (tokenizer_.is_eos(next_token)) break;

        // Decode and emit
        std::string token_text = tokenizer_.decode(next_token);
        if (on_token && !on_token(token_text.c_str(), next_token)) {
            break;
        }

        metrics_.generation_tokens++;
        metrics_.context_used = pos + 1;
        recent_tokens.push_back(next_token);

        // Keep recent_tokens bounded
        if (recent_tokens.size() > 256) {
            recent_tokens.erase(recent_tokens.begin(),
                                recent_tokens.begin() + (recent_tokens.size() - 256));
        }

        // Forward next token
        forward(next_token, pos);
        pos++;
    }

    metrics_.generation_ms = now_ms() - t_gen_start;
    return true;
}

void LlamaModel::cancel() {
    cancelled_.store(true, std::memory_order_relaxed);
}

void LlamaModel::reset_session() {
    kv_cache_.reset();
    metrics_ = InferenceMetrics();
    metrics_.context_max = config_.max_context_length;
    metrics_.memory_model = gguf_ ? (int64_t)gguf_->file_size : 0;
    metrics_.memory_cache = kv_cache_.memory_bytes();
}

} // namespace corelm
