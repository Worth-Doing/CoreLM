#include "sampler.h"
#include <algorithm>
#include <cmath>
#include <numeric>
#include <limits>

namespace corelm {

void Sampler::init(const SamplerConfig& config) {
    config_ = config;
    if (config_.seed == 0) {
        std::random_device rd;
        rng_.seed(rd());
    } else {
        rng_.seed(static_cast<unsigned>(config_.seed));
    }
}

int32_t Sampler::sample(float* logits, int vocab_size) {
    // Greedy if temperature is near zero
    if (config_.temperature < 0.01f) {
        return greedy(logits, vocab_size);
    }

    apply_temperature(logits, vocab_size);

    if (config_.top_k > 0 && config_.top_k < vocab_size) {
        apply_top_k(logits, vocab_size, config_.top_k);
    }

    return apply_top_p_and_sample(logits, vocab_size, config_.top_p);
}

void Sampler::apply_repeat_penalty(float* logits, int vocab_size,
                                    const std::vector<int32_t>& recent_tokens) {
    if (config_.repeat_penalty <= 1.0f) return;

    for (int32_t tok : recent_tokens) {
        if (tok >= 0 && tok < vocab_size) {
            if (logits[tok] > 0) {
                logits[tok] /= config_.repeat_penalty;
            } else {
                logits[tok] *= config_.repeat_penalty;
            }
        }
    }
}

void Sampler::apply_temperature(float* logits, int n) {
    float inv_temp = 1.0f / config_.temperature;
    for (int i = 0; i < n; i++) {
        logits[i] *= inv_temp;
    }
}

void Sampler::apply_top_k(float* logits, int n, int k) {
    // Find k-th largest value, set everything below to -inf
    std::vector<float> sorted(logits, logits + n);
    std::partial_sort(sorted.begin(), sorted.begin() + k, sorted.end(), std::greater<float>());
    float threshold = sorted[k - 1];

    for (int i = 0; i < n; i++) {
        if (logits[i] < threshold) {
            logits[i] = -1e30f;
        }
    }
}

int32_t Sampler::apply_top_p_and_sample(float* logits, int n, float p) {
    // Softmax
    float max_val = *std::max_element(logits, logits + n);
    float sum = 0.0f;
    for (int i = 0; i < n; i++) {
        logits[i] = expf(logits[i] - max_val);
        sum += logits[i];
    }
    float inv_sum = 1.0f / sum;
    for (int i = 0; i < n; i++) {
        logits[i] *= inv_sum;
    }

    // Sort indices by probability descending
    std::vector<int> indices(n);
    std::iota(indices.begin(), indices.end(), 0);
    std::partial_sort(indices.begin(), indices.begin() + std::min(n, 256), indices.end(),
                      [&](int a, int b) { return logits[a] > logits[b]; });

    // Top-p nucleus filtering
    float cumulative = 0.0f;
    int cutoff = n;
    for (int i = 0; i < n; i++) {
        cumulative += logits[indices[i]];
        if (cumulative >= p) {
            cutoff = i + 1;
            break;
        }
    }

    // Renormalize
    float renorm_sum = 0.0f;
    for (int i = 0; i < cutoff; i++) {
        renorm_sum += logits[indices[i]];
    }

    // Sample
    std::uniform_real_distribution<float> dist(0.0f, renorm_sum);
    float r = dist(rng_);
    float acc = 0.0f;
    for (int i = 0; i < cutoff; i++) {
        acc += logits[indices[i]];
        if (acc >= r) {
            return indices[i];
        }
    }

    return indices[0];
}

int32_t Sampler::greedy(const float* logits, int n) {
    return (int32_t)std::distance(logits, std::max_element(logits, logits + n));
}

} // namespace corelm
