#include "kv_cache.h"
#include <cstring>

namespace corelm {

void KVCache::init(int num_layers, int max_context, int num_kv_heads, int head_dim) {
    num_layers_   = num_layers;
    max_context_  = max_context;
    num_kv_heads_ = num_kv_heads;
    head_dim_     = head_dim;
    current_pos_  = 0;

    key_cache_.resize(num_layers);
    value_cache_.resize(num_layers);

    Shape slab_shape(num_kv_heads, max_context, head_dim);

    for (int l = 0; l < num_layers; l++) {
        key_cache_[l]   = Tensor::alloc(slab_shape, DType::F32);
        value_cache_[l] = Tensor::alloc(slab_shape, DType::F32);
        key_cache_[l].zero();
        value_cache_[l].zero();
    }
}

void KVCache::reset() {
    current_pos_ = 0;
    for (int l = 0; l < num_layers_; l++) {
        key_cache_[l].zero();
        value_cache_[l].zero();
    }
}

void KVCache::update(int layer, int pos, const float* key, const float* value) {
    // key/value layout: [num_kv_heads * head_dim]
    // Cache layout per layer: [num_kv_heads, max_context, head_dim]
    float* k = key_cache_[layer].data_f32();
    float* v = value_cache_[layer].data_f32();

    for (int h = 0; h < num_kv_heads_; h++) {
        int src_offset = h * head_dim_;
        int dst_offset = h * max_context_ * head_dim_ + pos * head_dim_;
        std::memcpy(k + dst_offset, key + src_offset, head_dim_ * sizeof(float));
        std::memcpy(v + dst_offset, value + src_offset, head_dim_ * sizeof(float));
    }
}

const float* KVCache::key_at(int layer, int head, int pos) const {
    return key_cache_[layer].data_f32() + head * max_context_ * head_dim_ + pos * head_dim_;
}

const float* KVCache::value_at(int layer, int head, int pos) const {
    return value_cache_[layer].data_f32() + head * max_context_ * head_dim_ + pos * head_dim_;
}

float* KVCache::key_slab(int layer) {
    return key_cache_[layer].data_f32();
}

float* KVCache::value_slab(int layer) {
    return value_cache_[layer].data_f32();
}

int64_t KVCache::memory_bytes() const {
    return 2 * num_layers_ * slab_size() * sizeof(float);
}

} // namespace corelm
