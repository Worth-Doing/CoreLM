#pragma once

#include <cstdint>
#include <string>
#include "gguf.h"

namespace corelm {

struct ModelConfig {
    std::string architecture;
    std::string name;
    std::string quantization;

    uint32_t vocab_size         = 0;
    uint32_t hidden_size        = 0;
    uint32_t intermediate_size  = 0;
    uint32_t num_layers         = 0;
    uint32_t num_heads          = 0;
    uint32_t num_kv_heads       = 0;
    uint32_t head_dim           = 0;
    uint32_t max_context_length = 0;

    float    rms_norm_eps       = 1e-5f;
    float    rope_theta         = 10000.0f;

    // Derived
    uint32_t kv_head_dim() const { return head_dim; }
    uint32_t gqa_ratio() const { return num_heads / num_kv_heads; }

    static ModelConfig from_gguf(const GGUFFile& gguf);
};

} // namespace corelm
