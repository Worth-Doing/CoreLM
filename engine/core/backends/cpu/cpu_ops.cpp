#include "cpu_ops.h"
#include <cmath>
#define ACCELERATE_NEW_LAPACK
#include <Accelerate/Accelerate.h>
#include <algorithm>

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

float dot_q4_0_block(const BlockQ4_0* block, const float* x) {
    float d = f16_to_f32(block->d);
    float sum = 0.0f;
    for (int i = 0; i < 16; i++) {
        int8_t lo = (block->qs[i] & 0x0F) - 8;
        int8_t hi = (block->qs[i] >> 4)   - 8;
        sum += lo * x[2 * i] + hi * x[2 * i + 1];
    }
    return sum * d;
}

// ── Matrix-vector multiply ────────────────────────────────────

void matvec(const Tensor& A, const Tensor& x, Tensor& out) {
    int64_t M = A.dim(0);
    int64_t K = A.dim(1);

    if (A.dtype() == DType::F32) {
        // Use Accelerate BLAS: out = A @ x
        cblas_sgemv(CblasRowMajor, CblasNoTrans,
                    (int)M, (int)K,
                    1.0f, A.data_f32(), (int)K,
                    x.data_f32(), 1,
                    0.0f, out.data_f32(), 1);
    } else if (A.dtype() == DType::Q4_0) {
        // Quantized matrix-vector: iterate over rows
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

// ── RMSNorm ──────────────────────────────────────────────────

void rmsnorm(const Tensor& x, const Tensor& weight, Tensor& out, float eps) {
    int64_t n = x.numel();
    const float* xp = x.data_f32();
    const float* wp = weight.data_f32();
    float* op = out.data_f32();

    // Compute sum of squares
    float ss = 0.0f;
    vDSP_svesq(xp, 1, &ss, (vDSP_Length)n);
    ss = 1.0f / sqrtf(ss / (float)n + eps);

    // Scale and multiply by weight
    for (int64_t i = 0; i < n; i++) {
        op[i] = xp[i] * ss * wp[i];
    }
}

// ── RoPE ─────────────────────────────────────────────────────

void rope(float* q, float* k, int head_dim, int num_heads, int num_kv_heads, int pos, float theta) {
    int half_dim = head_dim / 2;

    for (int h = 0; h < num_heads; h++) {
        float* qh = q + h * head_dim;
        for (int i = 0; i < half_dim; i++) {
            float freq = 1.0f / powf(theta, (float)(2 * i) / (float)head_dim);
            float angle = (float)pos * freq;
            float cos_val = cosf(angle);
            float sin_val = sinf(angle);

            float q0 = qh[i];
            float q1 = qh[i + half_dim];
            qh[i]            = q0 * cos_val - q1 * sin_val;
            qh[i + half_dim] = q0 * sin_val + q1 * cos_val;
        }
    }

    for (int h = 0; h < num_kv_heads; h++) {
        float* kh = k + h * head_dim;
        for (int i = 0; i < half_dim; i++) {
            float freq = 1.0f / powf(theta, (float)(2 * i) / (float)head_dim);
            float angle = (float)pos * freq;
            float cos_val = cosf(angle);
            float sin_val = sinf(angle);

            float k0 = kh[i];
            float k1 = kh[i + half_dim];
            kh[i]            = k0 * cos_val - k1 * sin_val;
            kh[i + half_dim] = k0 * sin_val + k1 * cos_val;
        }
    }
}

// ── SiLU ─────────────────────────────────────────────────────

void silu_inplace(Tensor& x) {
    float* p = x.data_f32();
    int64_t n = x.numel();
    for (int64_t i = 0; i < n; i++) {
        p[i] = p[i] / (1.0f + expf(-p[i]));
    }
}

// ── Element-wise ops ─────────────────────────────────────────

void mul_inplace(Tensor& a, const Tensor& b) {
    vDSP_vmul(a.data_f32(), 1, b.data_f32(), 1, a.data_f32(), 1, (vDSP_Length)a.numel());
}

void add_inplace(Tensor& a, const Tensor& b) {
    vDSP_vadd(a.data_f32(), 1, b.data_f32(), 1, a.data_f32(), 1, (vDSP_Length)a.numel());
}

// ── Softmax ──────────────────────────────────────────────────

void softmax_inplace(float* data, int size) {
    float max_val = *std::max_element(data, data + size);

    float sum = 0.0f;
    for (int i = 0; i < size; i++) {
        data[i] = expf(data[i] - max_val);
        sum += data[i];
    }
    float inv_sum = 1.0f / sum;
    for (int i = 0; i < size; i++) {
        data[i] *= inv_sum;
    }
}

// ── Embedding ────────────────────────────────────────────────

void embedding_lookup(const Tensor& table, int token_id, Tensor& out) {
    int64_t hidden = table.dim(1);
    if (table.dtype() == DType::F32) {
        const float* src = table.data_f32() + token_id * hidden;
        std::memcpy(out.data_f32(), src, hidden * sizeof(float));
    } else if (table.dtype() == DType::F16) {
        // F16 embedding table
        const uint16_t* src = static_cast<const uint16_t*>(table.data()) + token_id * hidden;
        float* dst = out.data_f32();
        for (int64_t i = 0; i < hidden; i++) {
            dst[i] = f16_to_f32(src[i]);
        }
    }
}

} // namespace cpu
} // namespace corelm
