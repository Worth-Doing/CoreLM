#pragma once

#include <cstdint>
#include <cstddef>
#include <vector>
#include <string>
#include <memory>
#include <cassert>
#include <cstring>
#include <cmath>

namespace corelm {

enum class DType : uint32_t {
    F32   = 0,
    F16   = 1,
    Q4_0  = 2,
    Q4_K_M = 3,
    Q8_0  = 8,
    I32   = 10,
};

inline size_t dtype_size(DType dt) {
    switch (dt) {
        case DType::F32:  return 4;
        case DType::F16:  return 2;
        case DType::I32:  return 4;
        case DType::Q4_0: return 0; // block-quantized, use block size
        case DType::Q4_K_M: return 0;
        case DType::Q8_0: return 0;
    }
    return 0;
}

inline const char* dtype_name(DType dt) {
    switch (dt) {
        case DType::F32:    return "F32";
        case DType::F16:    return "F16";
        case DType::Q4_0:   return "Q4_0";
        case DType::Q4_K_M: return "Q4_K_M";
        case DType::Q8_0:   return "Q8_0";
        case DType::I32:    return "I32";
    }
    return "unknown";
}

// Q4_0: 32 weights per block, 18 bytes per block
static constexpr int Q4_0_BLOCK_SIZE = 32;
static constexpr int Q4_0_BLOCK_BYTES = 18; // 2 (f16 scale) + 16 (32 x 4-bit)

struct BlockQ4_0 {
    uint16_t d;        // f16 scale
    uint8_t  qs[16];   // 32 x 4-bit quantized values
};
static_assert(sizeof(BlockQ4_0) == Q4_0_BLOCK_BYTES, "BlockQ4_0 size mismatch");

// Shape: up to 4 dimensions
static constexpr int MAX_DIMS = 4;

struct Shape {
    int64_t dims[MAX_DIMS] = {0, 0, 0, 0};
    int     ndim = 0;

    Shape() = default;
    Shape(int64_t d0) : ndim(1) { dims[0] = d0; }
    Shape(int64_t d0, int64_t d1) : ndim(2) { dims[0] = d0; dims[1] = d1; }
    Shape(int64_t d0, int64_t d1, int64_t d2) : ndim(3) { dims[0] = d0; dims[1] = d1; dims[2] = d2; }
    Shape(int64_t d0, int64_t d1, int64_t d2, int64_t d3) : ndim(4) { dims[0] = d0; dims[1] = d1; dims[2] = d2; dims[3] = d3; }

    int64_t operator[](int i) const { assert(i < ndim); return dims[i]; }
    int64_t& operator[](int i) { assert(i < ndim); return dims[i]; }

    int64_t numel() const {
        if (ndim == 0) return 0;
        int64_t n = 1;
        for (int i = 0; i < ndim; i++) n *= dims[i];
        return n;
    }

    bool operator==(const Shape& other) const {
        if (ndim != other.ndim) return false;
        for (int i = 0; i < ndim; i++) {
            if (dims[i] != other.dims[i]) return false;
        }
        return true;
    }
};

class Tensor {
public:
    Tensor() = default;

    // Allocate owned buffer
    static Tensor alloc(Shape shape, DType dtype);

    // Wrap external buffer (non-owning)
    static Tensor wrap(void* data, Shape shape, DType dtype);

    // Wrap const external buffer (non-owning, read-only)
    static Tensor wrap_const(const void* data, Shape shape, DType dtype);

    // Accessors
    const Shape& shape() const { return shape_; }
    DType dtype() const { return dtype_; }
    int ndim() const { return shape_.ndim; }
    int64_t dim(int i) const { return shape_[i]; }
    int64_t numel() const { return shape_.numel(); }

    void* data() { return data_; }
    const void* data() const { return data_; }

    float* data_f32() { assert(dtype_ == DType::F32); return static_cast<float*>(data_); }
    const float* data_f32() const { assert(dtype_ == DType::F32); return static_cast<const float*>(data_); }

    int32_t* data_i32() { assert(dtype_ == DType::I32); return static_cast<int32_t*>(data_); }
    const int32_t* data_i32() const { assert(dtype_ == DType::I32); return static_cast<const int32_t*>(data_); }

    const BlockQ4_0* data_q4_0() const { assert(dtype_ == DType::Q4_0); return static_cast<const BlockQ4_0*>(data_); }

    // Size in bytes
    size_t nbytes() const;

    // Number of quantization blocks (for quantized types)
    int64_t nblocks() const;

    bool is_contiguous() const { return true; } // all tensors are contiguous for now
    bool owns_data() const { return buffer_ != nullptr; }

    // Fill with value (F32 only)
    void fill(float value);

    // Fill with zeros
    void zero();

private:
    Shape shape_;
    DType dtype_ = DType::F32;
    void* data_ = nullptr;
    std::shared_ptr<std::vector<uint8_t>> buffer_; // owned storage
};

// Utility: convert f16 (stored as uint16_t) to f32
inline float f16_to_f32(uint16_t h) {
    uint32_t sign = (h & 0x8000) << 16;
    uint32_t expo = (h >> 10) & 0x1F;
    uint32_t mant = h & 0x03FF;

    if (expo == 0) {
        if (mant == 0) {
            uint32_t result = sign;
            float f;
            std::memcpy(&f, &result, 4);
            return f;
        }
        // subnormal
        while (!(mant & 0x0400)) {
            mant <<= 1;
            expo--;
        }
        expo++;
        mant &= ~0x0400;
    } else if (expo == 31) {
        uint32_t result = sign | 0x7F800000 | (mant << 13);
        float f;
        std::memcpy(&f, &result, 4);
        return f;
    }

    expo = expo + (127 - 15);
    uint32_t result = sign | (expo << 23) | (mant << 13);
    float f;
    std::memcpy(&f, &result, 4);
    return f;
}

inline uint16_t f32_to_f16(float f) {
    uint32_t x;
    std::memcpy(&x, &f, 4);

    uint32_t sign = (x >> 16) & 0x8000;
    int expo = ((x >> 23) & 0xFF) - 127 + 15;
    uint32_t mant = x & 0x007FFFFF;

    if (expo <= 0) {
        if (expo < -10) return sign;
        mant |= 0x00800000;
        int shift = 1 - expo + 13;
        mant >>= shift;
        return sign | (mant & 0x03FF);
    }
    if (expo >= 31) {
        return sign | 0x7C00;
    }
    return sign | (expo << 10) | (mant >> 13);
}

} // namespace corelm
