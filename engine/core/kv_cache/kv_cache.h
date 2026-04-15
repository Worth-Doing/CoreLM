#pragma once

#include "../tensor/tensor.h"
#include <cstdint>

namespace corelm {

class KVCache {
public:
    void init(int num_layers, int max_context, int num_kv_heads, int head_dim);
    void reset();

    // Write key/value for a given layer and position
    void update(int layer, int pos, const float* key, const float* value);

    // Get key/value buffer for a given layer (all positions up to current)
    const float* key_at(int layer, int head, int pos) const;
    const float* value_at(int layer, int head, int pos) const;

    // Full key/value slabs for a layer (contiguous: [num_kv_heads, max_context, head_dim])
    float* key_slab(int layer);
    float* value_slab(int layer);

    // Metrics
    int num_layers() const { return num_layers_; }
    int max_context() const { return max_context_; }
    int current_pos() const { return current_pos_; }
    int num_kv_heads() const { return num_kv_heads_; }
    int head_dim() const { return head_dim_; }
    int64_t memory_bytes() const;

    void set_pos(int pos) { current_pos_ = pos; }

private:
    int num_layers_   = 0;
    int max_context_  = 0;
    int num_kv_heads_ = 0;
    int head_dim_     = 0;
    int current_pos_  = 0;

    // Storage: one contiguous allocation per layer for keys, one for values
    // Layout per layer: [num_kv_heads, max_context, head_dim]
    std::vector<Tensor> key_cache_;
    std::vector<Tensor> value_cache_;

    int64_t slab_size() const {
        return (int64_t)num_kv_heads_ * max_context_ * head_dim_;
    }
};

} // namespace corelm
