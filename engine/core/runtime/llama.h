#pragma once

#include "../model/model_config.h"
#include "../model/gguf.h"
#include "../model/tokenizer.h"
#include "../tensor/tensor.h"
#include "../kv_cache/kv_cache.h"
#include "../sampling/sampler.h"
#include "../backends/backend.h"

#include <string>
#include <vector>
#include <functional>
#include <atomic>
#include <memory>

namespace corelm {

// Weights for a single transformer layer
struct LlamaLayerWeights {
    Tensor attn_norm;      // [hidden_size]
    Tensor ffn_norm;       // [hidden_size]
    Tensor wq;             // [hidden_size, hidden_size] or quantized
    Tensor wk;             // [kv_dim, hidden_size] or quantized
    Tensor wv;             // [kv_dim, hidden_size] or quantized
    Tensor wo;             // [hidden_size, hidden_size] or quantized
    Tensor w_gate;         // [intermediate_size, hidden_size] or quantized
    Tensor w_up;           // [intermediate_size, hidden_size] or quantized
    Tensor w_down;         // [hidden_size, intermediate_size] or quantized
};

// All model weights
struct LlamaWeights {
    Tensor token_embedding;    // [vocab_size, hidden_size]
    Tensor output_norm;        // [hidden_size]
    Tensor output;             // [vocab_size, hidden_size] (lm_head)
    std::vector<LlamaLayerWeights> layers;
};

// Runtime metrics
struct InferenceMetrics {
    double model_load_ms     = 0;
    double prompt_eval_ms    = 0;
    int    prompt_tokens     = 0;
    double generation_ms     = 0;
    int    generation_tokens = 0;
    double first_token_ms    = 0;
    int64_t memory_model     = 0;
    int64_t memory_cache     = 0;
    int64_t memory_scratch   = 0;
    int    context_used      = 0;
    int    context_max       = 0;

    double prompt_tok_per_sec() const {
        return prompt_eval_ms > 0 ? (prompt_tokens * 1000.0 / prompt_eval_ms) : 0;
    }
    double generation_tok_per_sec() const {
        return generation_ms > 0 ? (generation_tokens * 1000.0 / generation_ms) : 0;
    }
};

// Token callback: return false to stop generation
using TokenCallback = std::function<bool(const char* text, int32_t token_id)>;

class LlamaModel {
public:
    ~LlamaModel() = default;

    // Load model from GGUF file
    bool load(const std::string& path, std::string& error);

    // Run generation
    bool generate(const std::string& prompt,
                  const SamplerConfig& sampler_config,
                  int max_tokens,
                  int context_size,
                  TokenCallback on_token,
                  std::string& error);

    // Cancel in-progress generation (thread-safe)
    void cancel();

    // Reset KV cache / session state
    void reset_session();

    // Set backend (must be called before load, or uses auto)
    void set_backend(const std::string& backend_name);

    // Accessors
    const ModelConfig& config() const { return config_; }
    const Tokenizer& tokenizer() const { return tokenizer_; }
    const InferenceMetrics& metrics() const { return metrics_; }
    bool is_loaded() const { return loaded_; }
    std::string backend_name() const { return backend_ ? backend_->name() : "none"; }

private:
    // Forward pass for a single token at position `pos`
    void forward(int token_id, int pos);

    // Forward pass for a batch of tokens (prompt evaluation)
    void forward_batch(const std::vector<int32_t>& tokens, int start_pos);

    // Map GGUF tensors to weight structs
    bool map_weights(const GGUFFile& gguf, std::string& error);

    // Scratch buffers
    void alloc_scratch();

    ModelConfig config_;
    Tokenizer tokenizer_;
    LlamaWeights weights_;
    KVCache kv_cache_;
    InferenceMetrics metrics_;

    // Scratch space (reused across layers)
    Tensor x_;            // current hidden state [hidden_size]
    Tensor xb_;           // buffer [hidden_size]
    Tensor xb2_;          // buffer [hidden_size]
    Tensor q_;            // query   [num_heads * head_dim]
    Tensor k_;            // key     [num_kv_heads * head_dim]
    Tensor v_;            // value   [num_kv_heads * head_dim]
    Tensor att_;          // attention scores [num_heads, max_context]
    Tensor ffn_gate_;     // FFN gate output [intermediate_size]
    Tensor ffn_up_;       // FFN up output [intermediate_size]
    Tensor ffn_down_;     // FFN down output [hidden_size]
    Tensor logits_;       // output logits [vocab_size]

    bool loaded_ = false;
    std::atomic<bool> cancelled_{false};
    std::string requested_backend_ = "auto";

    // Backend
    std::unique_ptr<Backend> backend_;

    // GGUF file handle (keeps mmap alive)
    std::unique_ptr<GGUFFile> gguf_;
};

} // namespace corelm
