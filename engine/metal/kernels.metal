#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────
// Q4_0 block structure (matches C++ BlockQ4_0)
// ─────────────────────────────────────────────────────────────

struct BlockQ4_0 {
    half   d;           // scale
    uchar  qs[16];      // 32 x 4-bit quantized values
};

// ─────────────────────────────────────────────────────────────
// Matrix-vector multiply: Q4_0 quantized matrix @ F32 vector
// Each thread computes one output row
// A[M, K/32 blocks] @ x[K] = out[M]
// ─────────────────────────────────────────────────────────────

kernel void matvec_q4_0(
    device const BlockQ4_0* A      [[buffer(0)]],
    device const float*     x      [[buffer(1)]],
    device float*           out    [[buffer(2)]],
    constant uint&          K      [[buffer(3)]],  // number of columns (elements, not blocks)
    uint                    row    [[thread_position_in_grid]])
{
    uint blocks_per_row = K / 32;
    float sum = 0.0f;

    for (uint b = 0; b < blocks_per_row; b++) {
        device const BlockQ4_0& block = A[row * blocks_per_row + b];
        float d = float(block.d);
        uint base = b * 32;

        for (uint i = 0; i < 16; i++) {
            int lo = int(block.qs[i] & 0x0F) - 8;
            int hi = int(block.qs[i] >> 4)   - 8;
            sum += float(lo) * x[base + 2*i]     * d;
            sum += float(hi) * x[base + 2*i + 1] * d;
        }
    }

    out[row] = sum;
}

// ─────────────────────────────────────────────────────────────
// Matrix-vector multiply: F32 matrix @ F32 vector
// Each thread computes one output row
// ─────────────────────────────────────────────────────────────

kernel void matvec_f32(
    device const float* A       [[buffer(0)]],
    device const float* x       [[buffer(1)]],
    device float*       out     [[buffer(2)]],
    constant uint&      K       [[buffer(3)]],
    uint                row     [[thread_position_in_grid]])
{
    float sum = 0.0f;
    uint offset = row * K;
    for (uint i = 0; i < K; i++) {
        sum += A[offset + i] * x[i];
    }
    out[row] = sum;
}

// ─────────────────────────────────────────────────────────────
// RMSNorm: out[i] = (x[i] / rms) * weight[i]
// Two-pass: first compute sum-of-squares, then normalize
// ─────────────────────────────────────────────────────────────

kernel void rmsnorm(
    device const float* x       [[buffer(0)]],
    device const float* weight  [[buffer(1)]],
    device float*       out     [[buffer(2)]],
    constant uint&      n       [[buffer(3)]],
    constant float&     eps     [[buffer(4)]],
    uint                tid     [[thread_position_in_grid]])
{
    // Each thread handles one element, but needs the global RMS
    // For simplicity, compute RMS redundantly per thread (n is small: hidden_size)
    // A production kernel would use threadgroup reduction
    if (tid >= n) return;

    float ss = 0.0f;
    for (uint i = 0; i < n; i++) {
        ss += x[i] * x[i];
    }
    float rms = 1.0f / sqrt(ss / float(n) + eps);

    out[tid] = x[tid] * rms * weight[tid];
}

// ─────────────────────────────────────────────────────────────
// RoPE: Apply rotary positional encoding in-place
// Each thread handles one (cos, sin) pair for one head
// ─────────────────────────────────────────────────────────────

kernel void rope_apply(
    device float*       q         [[buffer(0)]],
    device float*       k         [[buffer(1)]],
    constant int&       head_dim  [[buffer(2)]],
    constant int&       num_heads [[buffer(3)]],
    constant int&       num_kv_h  [[buffer(4)]],
    constant int&       pos       [[buffer(5)]],
    constant float&     theta     [[buffer(6)]],
    uint                tid       [[thread_position_in_grid]])
{
    int half_dim = head_dim / 2;
    int total_q_pairs = num_heads * half_dim;
    int total_k_pairs = num_kv_h * half_dim;

    if (tid < uint(total_q_pairs)) {
        int head = tid / half_dim;
        int i = tid % half_dim;

        float freq = 1.0f / pow(theta, float(2 * i) / float(head_dim));
        float angle = float(pos) * freq;
        float cos_val = cos(angle);
        float sin_val = sin(angle);

        int idx0 = head * head_dim + i;
        int idx1 = head * head_dim + i + half_dim;

        float q0 = q[idx0];
        float q1 = q[idx1];
        q[idx0] = q0 * cos_val - q1 * sin_val;
        q[idx1] = q0 * sin_val + q1 * cos_val;
    }

    if (tid < uint(total_k_pairs)) {
        int head = tid / half_dim;
        int i = tid % half_dim;

        float freq = 1.0f / pow(theta, float(2 * i) / float(head_dim));
        float angle = float(pos) * freq;
        float cos_val = cos(angle);
        float sin_val = sin(angle);

        int idx0 = head * head_dim + i;
        int idx1 = head * head_dim + i + half_dim;

        float k0 = k[idx0];
        float k1 = k[idx1];
        k[idx0] = k0 * cos_val - k1 * sin_val;
        k[idx1] = k0 * sin_val + k1 * cos_val;
    }
}

// ─────────────────────────────────────────────────────────────
// SiLU in-place: x[i] = x[i] * sigmoid(x[i])
// ─────────────────────────────────────────────────────────────

kernel void silu_inplace(
    device float* x     [[buffer(0)]],
    constant uint& n    [[buffer(1)]],
    uint tid            [[thread_position_in_grid]])
{
    if (tid >= n) return;
    float v = x[tid];
    x[tid] = v / (1.0f + exp(-v));
}

// ─────────────────────────────────────────────────────────────
// Element-wise multiply in-place: a[i] *= b[i]
// ─────────────────────────────────────────────────────────────

kernel void elementwise_mul(
    device float*       a   [[buffer(0)]],
    device const float* b   [[buffer(1)]],
    constant uint&      n   [[buffer(2)]],
    uint                tid [[thread_position_in_grid]])
{
    if (tid >= n) return;
    a[tid] *= b[tid];
}

// ─────────────────────────────────────────────────────────────
// Element-wise add in-place: a[i] += b[i]
// ─────────────────────────────────────────────────────────────

kernel void elementwise_add(
    device float*       a   [[buffer(0)]],
    device const float* b   [[buffer(1)]],
    constant uint&      n   [[buffer(2)]],
    uint                tid [[thread_position_in_grid]])
{
    if (tid >= n) return;
    a[tid] += b[tid];
}

// ─────────────────────────────────────────────────────────────
// Softmax: Two-pass — find max, then exp and normalize
// Single threadgroup version for sequence lengths up to ~4096
// ─────────────────────────────────────────────────────────────

kernel void softmax_pass1_max(
    device const float* input   [[buffer(0)]],
    device float*       scratch [[buffer(1)]],  // [0] = max
    constant uint&      n       [[buffer(2)]],
    uint                tid     [[thread_position_in_grid]],
    uint                tcount  [[threads_per_grid]])
{
    // Each thread finds local max, then atomic max
    float local_max = -1e30f;
    for (uint i = tid; i < n; i += tcount) {
        local_max = max(local_max, input[i]);
    }

    // Simple: write max via threadgroup — for small n this is fine
    // For production, use proper reduction
    threadgroup float shared_max;
    if (tid == 0) shared_max = -1e30f;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Naive: just loop if we're thread 0
    if (tid == 0) {
        for (uint i = 0; i < n; i++) {
            shared_max = max(shared_max, input[i]);
        }
        scratch[0] = shared_max;
    }
}

kernel void softmax_pass2_exp_sum(
    device const float* input   [[buffer(0)]],
    device float*       output  [[buffer(1)]],
    device float*       scratch [[buffer(2)]],  // [0] = max, [1] = sum
    constant uint&      n       [[buffer(3)]],
    uint                tid     [[thread_position_in_grid]])
{
    if (tid >= n) return;
    float max_val = scratch[0];
    float e = exp(input[tid] - max_val);
    output[tid] = e;

    // Sum via thread 0 (simple for small n)
    if (tid == 0) {
        float s = 0.0f;
        for (uint i = 0; i < n; i++) {
            s += exp(input[i] - max_val);
        }
        scratch[1] = s;
    }
}

kernel void softmax_pass3_normalize(
    device float*       data    [[buffer(0)]],
    device const float* scratch [[buffer(1)]],  // [1] = sum
    constant uint&      n       [[buffer(2)]],
    uint                tid     [[thread_position_in_grid]])
{
    if (tid >= n) return;
    data[tid] /= scratch[1];
}
