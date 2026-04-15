#include "model_config.h"

namespace corelm {

ModelConfig ModelConfig::from_gguf(const GGUFFile& gguf) {
    ModelConfig cfg;

    cfg.architecture = gguf.get_string("general.architecture", "unknown");
    cfg.name = gguf.get_string("general.name", "unknown");

    // Architecture-specific keys (llama.* namespace)
    std::string arch = cfg.architecture;

    cfg.vocab_size         = gguf.get_uint32(arch + ".vocab_size",
                             gguf.get_uint32("tokenizer.ggml.tokens", 32000)); // fallback
    cfg.hidden_size        = gguf.get_uint32(arch + ".embedding_length", 4096);
    cfg.intermediate_size  = gguf.get_uint32(arch + ".feed_forward_length", 11008);
    cfg.num_layers         = gguf.get_uint32(arch + ".block_count", 32);
    cfg.num_heads          = gguf.get_uint32(arch + ".attention.head_count", 32);
    cfg.num_kv_heads       = gguf.get_uint32(arch + ".attention.head_count_kv", cfg.num_heads);
    cfg.max_context_length = gguf.get_uint32(arch + ".context_length", 4096);

    cfg.head_dim = cfg.hidden_size / cfg.num_heads;

    cfg.rms_norm_eps = gguf.get_float(arch + ".attention.layer_norm_rms_epsilon", 1e-5f);
    cfg.rope_theta   = gguf.get_float(arch + ".rope.freq_base", 10000.0f);

    // Determine quantization
    for (auto& t : gguf.tensors) {
        if (t.name.find(".weight") != std::string::npos && t.dtype != GGUFDType::F32) {
            cfg.quantization = gguf_dtype_name(t.dtype);
            break;
        }
    }
    if (cfg.quantization.empty()) cfg.quantization = "F32";

    return cfg;
}

} // namespace corelm
