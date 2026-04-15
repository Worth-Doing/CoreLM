#pragma once

#include <cstdint>
#include <vector>
#include <random>

namespace corelm {

struct SamplerConfig {
    float    temperature    = 0.7f;
    int32_t  top_k          = 40;
    float    top_p          = 0.95f;
    float    repeat_penalty = 1.1f;
    uint64_t seed           = 0;      // 0 = random
};

class Sampler {
public:
    void init(const SamplerConfig& config);

    // Sample a token from logits
    int32_t sample(float* logits, int vocab_size);

    // Apply repetition penalty (modifies logits in-place)
    void apply_repeat_penalty(float* logits, int vocab_size,
                              const std::vector<int32_t>& recent_tokens);

private:
    SamplerConfig config_;
    std::mt19937 rng_;

    void apply_temperature(float* logits, int n);
    void apply_top_k(float* logits, int n, int k);
    int32_t apply_top_p_and_sample(float* logits, int n, float p);
    int32_t greedy(const float* logits, int n);
};

} // namespace corelm
