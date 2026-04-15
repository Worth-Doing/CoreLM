#include "cpu_ops.h"
#include <cmath>
#define ACCELERATE_NEW_LAPACK
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <arm_neon.h>
#include <sys/mman.h>

namespace corelm {
namespace cpu {

// ── Dequantization ───────────────────────────────────────────

void dequantize_q4_0_block(const BlockQ4_0* block, float* output) {
    float d = f16_to_f32(block->d);
    for (int i = 0; i < 16; i++) {
        int8_t lo = (block->qs[i] & 0x0F) - 8;
        int8_t hi = (block->qs[i] >> 4)   - 8;
        output[2 * i]     = lo * d;
        output[2 * i + 1] = hi * d;
    }
}

// NEON-optimized Q4_0 dot product
float dot_q4_0_block(const BlockQ4_0* block, const float* x) {
    float d = f16_to_f32(block->d);

    // Process 16 byte-pairs (32 nibbles) using NEON
    float32x4_t sum_vec = vdupq_n_f32(0.0f);

    for (int i = 0; i < 16; i += 4) {
        // Unpack 4 bytes → 8 nibbles → 8 int values
        int8_t vals[8];
        for (int j = 0; j < 4; j++) {
            vals[2*j]     = (block->qs[i+j] & 0x0F) - 8;
            vals[2*j + 1] = (block->qs[i+j] >> 4)   - 8;
        }

        // Convert to float and multiply with x
        float32x4_t v0 = {(float)vals[0], (float)vals[1], (float)vals[2], (float)vals[3]};
        float32x4_t v1 = {(float)vals[4], (float)vals[5], (float)vals[6], (float)vals[7]};

        float32x4_t x0 = vld1q_f32(&x[2*i]);
        float32x4_t x1 = vld1q_f32(&x[2*i + 4]);

        sum_vec = vfmaq_f32(sum_vec, v0, x0);
        sum_vec = vfmaq_f32(sum_vec, v1, x1);
    }

    float sum = vaddvq_f32(sum_vec);
    return sum * d;
}

// ── Matrix-vector multiply ────────────────────────────────────

void matvec(const Tensor& A, const Tensor& x, Tensor& out) {
    int64_t M = A.dim(0);
    int64_t K = A.dim(1);

    if (A.dtype() == DType::F32) {
        cblas_sgemv(CblasRowMajor, CblasNoTrans,
                    (int)M, (int)K,
                    1.0f, A.data_f32(), (int)K,
                    x.data_f32(), 1,
                    0.0f, out.data_f32(), 1);
    } else if (A.dtype() == DType::Q4_0) {
        const auto* blocks = A.data_q4_0();
        int64_t blocks_per_row = K / Q4_0_BLOCK_SIZE;
        const float* xp = x.data_f32();
        float* op = out.data_f32();

        for (int64_t row = 0; row < M; row++) {
            float sum = 0.0f;
            for (int64_t b = 0; b < blocks_per_row; b++) {
                sum += dot_q4_0_block(&blocks[row * blocks_per_row + b],
                                      &xp[b * Q4_0_BLOCK_SIZE]);
            }
            op[row] = sum;
        }
    }
}

void matmul(const Tensor& A, const Tensor& B, Tensor& C) {
    int64_t M = A.dim(0);
    int64_t K = A.dim(1);
    int64_t N = B.dim(1);

    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                (int)M, (int)N, (int)K,
                1.0f,
                A.data_f32(), (int)K,
                B.data_f32(), (int)N,
                0.0f,
                C.data_f32(), (int)N);
}

// ── RMSNorm (Accelerate-optimized) ──────────────────────────

void rmsnorm(const Tensor& x, const Tensor& weight, Tensor& out, float eps) {
    int64_t n = x.numel();
    const float* xp = x.data_f32();
    const float* wp = weight.data_f32();
    float* op = out.data_f32();

    // Sum of squares via vDSP
    float ss = 0.0f;
    vDSP_svesq(xp, 1, &ss, (vDSP_Length)n);
    float rms = 1.0f / sqrtf(ss / (float)n + eps);

    // x * rms → op, then op * weight → op (fused into one pass)
    vDSP_vsmul(xp, 1, &rms, op, 1, (vDSP_Length)n);
    vDSP_vmul(op, 1, wp, 1, op, 1, (vDSP_Length)n);
}

// ── RoPE (precompute-friendly) ───────────────────────────────

void rope(float* q, float* k, int head_dim, int num_heads, int num_kv_heads, int pos, float theta) {
    int half_dim = head_dim / 2;

    // Precompute frequencies for this position (shared across heads)
    // Avoids redundant powf calls per head
    float cos_cache[512], sin_cache[512];  // max head_dim = 1024 → half = 512
    for (int i = 0; i < half_dim; i++) {
        float freq = 1.0f / powf(theta, (float)(2 * i) / (float)head_dim);
        float angle = (float)pos * freq;
        cos_cache[i] = cosf(angle);
        sin_cache[i] = sinf(angle);
    }

    for (int h = 0; h < num_heads; h++) {
        float* qh = q + h * head_dim;
        for (int i = 0; i < half_dim; i++) {
            float q0 = qh[i];
            float q1 = qh[i + half_dim];
            qh[i]            = q0 * cos_cache[i] - q1 * sin_cache[i];
            qh[i + half_dim] = q0 * sin_cache[i] + q1 * cos_cache[i];
        }
    }

    for (int h = 0; h < num_kv_heads; h++) {
        float* kh = k + h * head_dim;
        for (int i = 0; i < half_dim; i++) {
            float k0 = kh[i];
            float k1 = kh[i + half_dim];
            kh[i]            = k0 * cos_cache[i] - k1 * sin_cache[i];
            kh[i + half_dim] = k0 * sin_cache[i] + k1 * cos_cache[i];
        }
    }
}

// ── SiLU (NEON-vectorized) ──────────────────────────────────

void silu_inplace(Tensor& x) {
    float* p = x.data_f32();
    int64_t n = x.numel();

    // NEON path: process 4 floats at a time
    int64_t i = 0;
    for (; i + 3 < n; i += 4) {
        float32x4_t v = vld1q_f32(p + i);
        // sigmoid(x) = 1 / (1 + exp(-x))
        // SiLU(x) = x * sigmoid(x)
        float vals[4];
        vst1q_f32(vals, v);
        vals[0] = vals[0] / (1.0f + expf(-vals[0]));
        vals[1] = vals[1] / (1.0f + expf(-vals[1]));
        vals[2] = vals[2] / (1.0f + expf(-vals[2]));
        vals[3] = vals[3] / (1.0f + expf(-vals[3]));
        vst1q_f32(p + i, vld1q_f32(vals));
    }

    // Scalar tail
    for (; i < n; i++) {
        p[i] = p[i] / (1.0f + expf(-p[i]));
    }
}

// ── Element-wise ops (Accelerate vDSP) ───────────────────────

void mul_inplace(Tensor& a, const Tensor& b) {
    vDSP_vmul(a.data_f32(), 1, b.data_f32(), 1, a.data_f32(), 1, (vDSP_Length)a.numel());
}

void add_inplace(Tensor& a, const Tensor& b) {
    vDSP_vadd(a.data_f32(), 1, b.data_f32(), 1, a.data_f32(), 1, (vDSP_Length)a.numel());
}

// ── Softmax (Accelerate vDSP) ───────────────────────────────

void softmax_inplace(float* data, int size) {
    // Find max
    float max_val;
    vDSP_maxv(data, 1, &max_val, (vDSP_Length)size);

    // Subtract max
    float neg_max = -max_val;
    vDSP_vsadd(data, 1, &neg_max, data, 1, (vDSP_Length)size);

    // Exp
    int n = size;
    vvexpf(data, data, &n);

    // Sum
    float sum = 0.0f;
    vDSP_sve(data, 1, &sum, (vDSP_Length)size);

    // Normalize
    float inv_sum = 1.0f / sum;
    vDSP_vsmul(data, 1, &inv_sum, data, 1, (vDSP_Length)size);
}

// ── Embedding ────────────────────────────────────────────────

void embedding_lookup(const Tensor& table, int token_id, Tensor& out) {
    int64_t hidden = table.dim(1);
    if (table.dtype() == DType::F32) {
        const float* src = table.data_f32() + token_id * hidden;
        std::memcpy(out.data_f32(), src, hidden * sizeof(float));
    } else if (table.dtype() == DType::F16) {
        const uint16_t* src = static_cast<const uint16_t*>(table.data()) + token_id * hidden;
        float* dst = out.data_f32();
        // NEON-accelerated f16→f32 conversion
        int64_t i = 0;
        for (; i + 3 < hidden; i += 4) {
            uint16x4_t h4 = vld1_u16(&src[i]);
            float16x4_t f16 = vreinterpret_f16_u16(h4);
            float32x4_t f32 = vcvt_f32_f16(f16);
            vst1q_f32(&dst[i], f32);
        }
        for (; i < hidden; i++) {
            dst[i] = f16_to_f32(src[i]);
        }
    }
}

// ── Memory hints ─────────────────────────────────────────────

void advise_sequential(const void* addr, size_t len) {
    madvise((void*)addr, len, MADV_SEQUENTIAL);
}

void advise_willneed(const void* addr, size_t len) {
    madvise((void*)addr, len, MADV_WILLNEED);
}

} // namespace cpu
} // namespace corelm
