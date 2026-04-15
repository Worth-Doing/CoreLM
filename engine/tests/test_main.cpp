#include <cstdio>
#include <cmath>
#include <cassert>
#include <vector>
#include <string>

#include "corelm.h"
#include "tensor/tensor.h"
#include "backends/cpu/cpu_ops.h"
#include "sampling/sampler.h"
#include "kv_cache/kv_cache.h"

using namespace corelm;

static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) \
    do { printf("  %-50s", name); } while(0)

#define PASS() \
    do { printf("PASS\n"); tests_passed++; } while(0)

#define FAIL(msg) \
    do { printf("FAIL: %s\n", msg); tests_failed++; } while(0)

#define ASSERT_EQ(a, b, msg) \
    do { if ((a) != (b)) { FAIL(msg); return; } } while(0)

#define ASSERT_NEAR(a, b, tol, msg) \
    do { if (std::fabs((a) - (b)) > (tol)) { FAIL(msg); return; } } while(0)

// ── Tensor tests ────────────────────────────────────────────

void test_tensor_alloc() {
    TEST("tensor: alloc F32");
    auto t = Tensor::alloc(Shape(3, 4), DType::F32);
    ASSERT_EQ(t.numel(), 12, "wrong numel");
    ASSERT_EQ(t.nbytes(), 48u, "wrong nbytes");
    ASSERT_EQ(t.ndim(), 2, "wrong ndim");
    ASSERT_EQ(t.dim(0), 3, "wrong dim 0");
    ASSERT_EQ(t.dim(1), 4, "wrong dim 1");
    PASS();
}

void test_tensor_fill() {
    TEST("tensor: fill and read");
    auto t = Tensor::alloc(Shape(5), DType::F32);
    t.fill(3.14f);
    ASSERT_NEAR(t.data_f32()[0], 3.14f, 1e-6, "wrong value");
    ASSERT_NEAR(t.data_f32()[4], 3.14f, 1e-6, "wrong value");
    PASS();
}

void test_tensor_zero() {
    TEST("tensor: zero");
    auto t = Tensor::alloc(Shape(10), DType::F32);
    t.fill(42.0f);
    t.zero();
    ASSERT_NEAR(t.data_f32()[0], 0.0f, 1e-8, "not zero");
    ASSERT_NEAR(t.data_f32()[9], 0.0f, 1e-8, "not zero");
    PASS();
}

void test_tensor_q4_0() {
    TEST("tensor: Q4_0 alloc");
    auto t = Tensor::alloc(Shape(64), DType::Q4_0);
    // 64 elements = 2 blocks = 36 bytes
    ASSERT_EQ(t.nblocks(), 2, "wrong nblocks");
    ASSERT_EQ(t.nbytes(), 36u, "wrong nbytes for Q4_0");
    PASS();
}

// ── F16 conversion tests ────────────────────────────────────

void test_f16_conversion() {
    TEST("f16: roundtrip conversion");
    float vals[] = {0.0f, 1.0f, -1.0f, 0.5f, 65504.0f, -0.001f};
    for (float v : vals) {
        uint16_t h = f32_to_f16(v);
        float back = f16_to_f32(h);
        if (std::fabs(v) > 0) {
            float rel_err = std::fabs(back - v) / std::fabs(v);
            if (rel_err > 0.01f) { FAIL("f16 roundtrip error"); return; }
        }
    }
    PASS();
}

// ── Q4_0 dequantization tests ───────────────────────────────

void test_dequant_q4_0() {
    TEST("dequant: Q4_0 block");
    BlockQ4_0 block;
    block.d = f32_to_f16(0.5f);
    // All nibbles = 0x88 → lo=0, hi=8 → values: (0-8)*0.5=-4, (8-8)*0.5=0
    for (int i = 0; i < 16; i++) block.qs[i] = 0x08;

    float output[32];
    cpu::dequantize_q4_0_block(&block, output);

    // qs[i] = 0x08: lo = 8-8=0, hi = 0-8=-8
    float d = f16_to_f32(block.d);
    ASSERT_NEAR(output[0], 0 * d, 1e-4, "wrong dequant value 0");
    ASSERT_NEAR(output[1], -8 * d, 1e-4, "wrong dequant value 1");
    PASS();
}

// ── RMSNorm test ────────────────────────────────────────────

void test_rmsnorm() {
    TEST("rmsnorm: basic");
    auto x = Tensor::alloc(Shape(4), DType::F32);
    auto w = Tensor::alloc(Shape(4), DType::F32);
    auto out = Tensor::alloc(Shape(4), DType::F32);

    x.data_f32()[0] = 1.0f;
    x.data_f32()[1] = 2.0f;
    x.data_f32()[2] = 3.0f;
    x.data_f32()[3] = 4.0f;
    w.fill(1.0f);

    cpu::rmsnorm(x, w, out, 1e-5f);

    // rms = sqrt((1+4+9+16)/4) = sqrt(7.5) ≈ 2.7386
    // normalized = x / rms
    float rms = sqrtf(30.0f / 4.0f + 1e-5f);
    ASSERT_NEAR(out.data_f32()[0], 1.0f / rms, 1e-4, "rmsnorm wrong");
    ASSERT_NEAR(out.data_f32()[3], 4.0f / rms, 1e-4, "rmsnorm wrong");
    PASS();
}

// ── Softmax test ────────────────────────────────────────────

void test_softmax() {
    TEST("softmax: basic");
    float data[4] = {1.0f, 2.0f, 3.0f, 4.0f};
    cpu::softmax_inplace(data, 4);

    float sum = data[0] + data[1] + data[2] + data[3];
    ASSERT_NEAR(sum, 1.0f, 1e-5, "softmax doesn't sum to 1");

    // Should be monotonically increasing
    for (int i = 0; i < 3; i++) {
        if (data[i] >= data[i+1]) { FAIL("softmax not monotonic"); return; }
    }
    PASS();
}

// ── SiLU test ───────────────────────────────────────────────

void test_silu() {
    TEST("silu: basic");
    auto t = Tensor::alloc(Shape(3), DType::F32);
    t.data_f32()[0] = 0.0f;
    t.data_f32()[1] = 1.0f;
    t.data_f32()[2] = -1.0f;

    cpu::silu_inplace(t);

    ASSERT_NEAR(t.data_f32()[0], 0.0f, 1e-5, "silu(0) wrong");
    // silu(1) = 1 * sigmoid(1) = 1 * 0.7311 = 0.7311
    ASSERT_NEAR(t.data_f32()[1], 0.7311f, 1e-3, "silu(1) wrong");
    // silu(-1) = -1 * sigmoid(-1) = -1 * 0.2689 = -0.2689
    ASSERT_NEAR(t.data_f32()[2], -0.2689f, 1e-3, "silu(-1) wrong");
    PASS();
}

// ── Sampler tests ───────────────────────────────────────────

void test_sampler_greedy() {
    TEST("sampler: greedy");
    Sampler sampler;
    SamplerConfig cfg;
    cfg.temperature = 0.0f;
    sampler.init(cfg);

    float logits[5] = {1.0f, 3.0f, 2.0f, 5.0f, 0.0f};
    int32_t token = sampler.sample(logits, 5);
    ASSERT_EQ(token, 3, "greedy should pick index 3 (highest logit)");
    PASS();
}

void test_sampler_temperature() {
    TEST("sampler: temperature sampling");
    Sampler sampler;
    SamplerConfig cfg;
    cfg.temperature = 0.7f;
    cfg.top_k = -1;
    cfg.top_p = 1.0f;
    cfg.seed = 42;
    sampler.init(cfg);

    float logits[5] = {1.0f, 3.0f, 2.0f, 5.0f, 0.0f};
    int32_t token = sampler.sample(logits, 5);
    // With seed=42, result is deterministic — just verify it's valid
    if (token < 0 || token >= 5) { FAIL("invalid token"); return; }
    PASS();
}

// ── KV Cache tests ──────────────────────────────────────────

void test_kv_cache() {
    TEST("kv_cache: init and update");
    KVCache cache;
    cache.init(2, 128, 4, 64); // 2 layers, 128 context, 4 kv heads, head_dim=64

    ASSERT_EQ(cache.num_layers(), 2, "wrong num_layers");
    ASSERT_EQ(cache.max_context(), 128, "wrong max_context");

    // Write some key data at position 0, layer 0
    std::vector<float> k_data(4 * 64, 1.0f); // num_kv_heads * head_dim
    std::vector<float> v_data(4 * 64, 2.0f);
    cache.update(0, 0, k_data.data(), v_data.data());

    // Read back
    const float* k = cache.key_at(0, 0, 0);
    const float* v = cache.value_at(0, 0, 0);
    ASSERT_NEAR(k[0], 1.0f, 1e-6, "k wrong");
    ASSERT_NEAR(v[0], 2.0f, 1e-6, "v wrong");
    PASS();
}

void test_kv_cache_reset() {
    TEST("kv_cache: reset");
    KVCache cache;
    cache.init(1, 64, 2, 32);

    std::vector<float> data(2 * 32, 5.0f);
    cache.update(0, 0, data.data(), data.data());
    cache.reset();

    const float* k = cache.key_at(0, 0, 0);
    ASSERT_NEAR(k[0], 0.0f, 1e-6, "reset didn't zero");
    PASS();
}

// ── Matvec test ─────────────────────────────────────────────

void test_matvec_f32() {
    TEST("matvec: F32 basic");
    // 2x3 matrix @ 3-vector = 2-vector
    auto A = Tensor::alloc(Shape(2, 3), DType::F32);
    auto x = Tensor::alloc(Shape(3), DType::F32);
    auto out = Tensor::alloc(Shape(2), DType::F32);

    float* ap = A.data_f32();
    ap[0] = 1; ap[1] = 2; ap[2] = 3;  // row 0
    ap[3] = 4; ap[4] = 5; ap[5] = 6;  // row 1

    float* xp = x.data_f32();
    xp[0] = 1; xp[1] = 1; xp[2] = 1;

    cpu::matvec(A, x, out);

    ASSERT_NEAR(out.data_f32()[0], 6.0f, 1e-4, "matvec row 0 wrong");
    ASSERT_NEAR(out.data_f32()[1], 15.0f, 1e-4, "matvec row 1 wrong");
    PASS();
}

// ── C API test ──────────────────────────────────────────────

void test_c_api_context() {
    TEST("c_api: context create/destroy");
    clm_context_t ctx = nullptr;
    auto params = clm_context_default_params();
    auto status = clm_context_create(params, &ctx);
    ASSERT_EQ((int)status, (int)CLM_STATUS_OK, "create failed");
    if (ctx) {
        clm_context_destroy(ctx);
    }
    PASS();
}

void test_c_api_default_params() {
    TEST("c_api: default generation params");
    auto p = clm_generation_default_params();
    ASSERT_NEAR(p.temperature, 0.7f, 1e-6, "wrong default temperature");
    ASSERT_EQ(p.top_k, 40, "wrong default top_k");
    PASS();
}

// ── Main ────────────────────────────────────────────────────

int main() {
    printf("\n=== CoreLM Engine Tests ===\n\n");

    printf("Tensor:\n");
    test_tensor_alloc();
    test_tensor_fill();
    test_tensor_zero();
    test_tensor_q4_0();

    printf("\nF16:\n");
    test_f16_conversion();

    printf("\nDequantization:\n");
    test_dequant_q4_0();

    printf("\nOps:\n");
    test_rmsnorm();
    test_softmax();
    test_silu();
    test_matvec_f32();

    printf("\nSampler:\n");
    test_sampler_greedy();
    test_sampler_temperature();

    printf("\nKV Cache:\n");
    test_kv_cache();
    test_kv_cache_reset();

    printf("\nC API:\n");
    test_c_api_context();
    test_c_api_default_params();

    printf("\n=== Results: %d passed, %d failed ===\n\n", tests_passed, tests_failed);
    return tests_failed > 0 ? 1 : 0;
}
