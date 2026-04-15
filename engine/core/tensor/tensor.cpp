#include "tensor.h"
#include <algorithm>

namespace corelm {

Tensor Tensor::alloc(Shape shape, DType dtype) {
    Tensor t;
    t.shape_ = shape;
    t.dtype_ = dtype;

    size_t bytes = 0;
    if (dtype == DType::Q4_0) {
        int64_t n = shape.numel();
        int64_t blocks = (n + Q4_0_BLOCK_SIZE - 1) / Q4_0_BLOCK_SIZE;
        bytes = blocks * Q4_0_BLOCK_BYTES;
    } else {
        bytes = shape.numel() * dtype_size(dtype);
    }

    t.buffer_ = std::make_shared<std::vector<uint8_t>>(bytes, 0);
    t.data_ = t.buffer_->data();
    return t;
}

Tensor Tensor::wrap(void* data, Shape shape, DType dtype) {
    Tensor t;
    t.shape_ = shape;
    t.dtype_ = dtype;
    t.data_ = data;
    return t;
}

Tensor Tensor::wrap_const(const void* data, Shape shape, DType dtype) {
    Tensor t;
    t.shape_ = shape;
    t.dtype_ = dtype;
    t.data_ = const_cast<void*>(data);
    return t;
}

size_t Tensor::nbytes() const {
    if (dtype_ == DType::Q4_0) {
        return nblocks() * Q4_0_BLOCK_BYTES;
    }
    return numel() * dtype_size(dtype_);
}

int64_t Tensor::nblocks() const {
    if (dtype_ == DType::Q4_0) {
        return (numel() + Q4_0_BLOCK_SIZE - 1) / Q4_0_BLOCK_SIZE;
    }
    return numel(); // for non-quantized, each element is a "block"
}

void Tensor::fill(float value) {
    assert(dtype_ == DType::F32);
    float* ptr = data_f32();
    int64_t n = numel();
    std::fill(ptr, ptr + n, value);
}

void Tensor::zero() {
    std::memset(data_, 0, nbytes());
}

} // namespace corelm
