#pragma once

#include "../../tensor/tensor.h"

namespace corelm {
namespace cpu {

// ── Core math operations ──────────────────────────────────────

// Matrix-vector multiply: out[M] = A[M, K] @ x[K]
// A can be F32 or Q4_0, x and out must be F32
void matvec(const Tensor& A, const Tensor& x, Tensor& out);

// General matmul: C[M, N] = A[M, K] @ B[K, N]
// All F32
void matmul(const Tensor& A, const Tensor& B, Tensor& C);

// ── Normalization ─────────────────────────────────────────────

// RMSNorm: out[n] = (x[n] / rms(x)) * weight[n]
void rmsnorm(const Tensor& x, const Tensor& weight, Tensor& out, float eps);

// ── Positional encoding ──────────────────────────────────────

// RoPE in-place: rotate q and k by position
void rope(float* q, float* k, int head_dim, int num_heads, int num_kv_heads, int pos, float theta);

// ── Activation ────────────────────────────────────────────────

// SiLU in-place: x = x * sigmoid(x)
void silu_inplace(Tensor& x);

// ── Element-wise ──────────────────────────────────────────────

// out = a * b (element-wise)
void mul_inplace(Tensor& a, const Tensor& b);

// out = a + b (element-wise)
void add_inplace(Tensor& a, const Tensor& b);

// ── Attention ─────────────────────────────────────────────────

// Softmax in-place over last dimension
void softmax_inplace(float* data, int size);

// ── Dequantization ───────────────────────────────────────────

// Dequantize Q4_0 block to float buffer
void dequantize_q4_0_block(const BlockQ4_0* block, float* output);

// Dot product of Q4_0 block with float vector
float dot_q4_0_block(const BlockQ4_0* block, const float* x);

// ── Embedding ────────────────────────────────────────────────

// Copy embedding row: out[hidden] = embedding_table[token_id * hidden, ...]
void embedding_lookup(const Tensor& table, int token_id, Tensor& out);

} // namespace cpu
} // namespace corelm
