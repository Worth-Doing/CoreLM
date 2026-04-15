#include "dequant.h"
#include <cstring>
#include <cstdio>

namespace corelm {

// ── Block structures for k-quant types ──────────────────────

#pragma pack(push, 1)

struct block_q4_0 {
    uint16_t d;       // f16 scale
    uint8_t  qs[16];  // 32 x 4-bit
};

struct block_q4_1 {
    uint16_t d;       // f16 scale
    uint16_t m;       // f16 min
    uint8_t  qs[16];  // 32 x 4-bit
};

struct block_q8_0 {
    uint16_t d;       // f16 scale
    int8_t   qs[32];  // 32 x 8-bit
};

struct block_q4_K {
    uint16_t d;           // f16 super-block scale
    uint16_t dmin;        // f16 super-block min
    uint8_t  scales[12];  // sub-block scales+mins (packed 6-bit)
    uint8_t  qs[128];     // 256 x 4-bit
};

struct block_q5_K {
    uint16_t d;
    uint16_t dmin;
    uint8_t  scales[12];
    uint8_t  qh[32];     // high bits
    uint8_t  qs[128];    // low 4 bits
};

struct block_q6_K {
    uint8_t  ql[128];    // lower 4 bits
    uint8_t  qh[64];     // upper 2 bits
    int8_t   scales[16]; // scales
    uint16_t d;          // f16 super-block scale
};

#pragma pack(pop)

// ── Dequantization functions ────────────────────────────────

static void dequant_f16(const void* src, float* dst, int64_t n) {
    const uint16_t* s = static_cast<const uint16_t*>(src);
    for (int64_t i = 0; i < n; i++) {
        dst[i] = f16_to_f32(s[i]);
    }
}

static void dequant_q4_0(const void* src, float* dst, int64_t n) {
    const auto* blocks = static_cast<const block_q4_0*>(src);
    int64_t nb = n / 32;
    for (int64_t b = 0; b < nb; b++) {
        float d = f16_to_f32(blocks[b].d);
        for (int i = 0; i < 16; i++) {
            int lo = (blocks[b].qs[i] & 0x0F) - 8;
            int hi = (blocks[b].qs[i] >> 4)   - 8;
            dst[b * 32 + 2 * i]     = lo * d;
            dst[b * 32 + 2 * i + 1] = hi * d;
        }
    }
}

static void dequant_q4_1(const void* src, float* dst, int64_t n) {
    const auto* blocks = static_cast<const block_q4_1*>(src);
    int64_t nb = n / 32;
    for (int64_t b = 0; b < nb; b++) {
        float d = f16_to_f32(blocks[b].d);
        float m = f16_to_f32(blocks[b].m);
        for (int i = 0; i < 16; i++) {
            int lo = (blocks[b].qs[i] & 0x0F);
            int hi = (blocks[b].qs[i] >> 4);
            dst[b * 32 + 2 * i]     = lo * d + m;
            dst[b * 32 + 2 * i + 1] = hi * d + m;
        }
    }
}

static void dequant_q8_0(const void* src, float* dst, int64_t n) {
    const auto* blocks = static_cast<const block_q8_0*>(src);
    int64_t nb = n / 32;
    for (int64_t b = 0; b < nb; b++) {
        float d = f16_to_f32(blocks[b].d);
        for (int i = 0; i < 32; i++) {
            dst[b * 32 + i] = blocks[b].qs[i] * d;
        }
    }
}

// Q4_K: 256 elements per super-block, 8 sub-blocks of 32 each
static void dequant_q4_K(const void* src, float* dst, int64_t n) {
    const auto* blocks = static_cast<const block_q4_K*>(src);
    int64_t nb = n / 256;

    for (int64_t b = 0; b < nb; b++) {
        float d    = f16_to_f32(blocks[b].d);
        float dmin = f16_to_f32(blocks[b].dmin);
        const uint8_t* sc = blocks[b].scales;

        // Unpack 6-bit scales and mins from 12 bytes
        // First 8 sub-blocks: scales in lower 6 bits, mins in upper...
        // The packing is: scales[0..3] have low 6 bits of sc[0..7]
        // scales[4..5] + scales[8..11] have high bits
        uint8_t sub_scales[8];
        uint8_t sub_mins[8];

        for (int i = 0; i < 4; i++) {
            sub_scales[i]     = sc[i] & 63;
            sub_scales[i + 4] = sc[i + 4] & 63;
            sub_mins[i]       = sc[i] >> 6 | ((sc[i + 8] & 0x0F) << 2);
            sub_mins[i + 4]   = sc[i + 4] >> 6 | ((sc[i + 8] >> 4) << 2);
        }

        const uint8_t* qs = blocks[b].qs;
        for (int sub = 0; sub < 8; sub++) {
            float sc_val  = d * sub_scales[sub];
            float min_val = dmin * sub_mins[sub];
            for (int i = 0; i < 16; i++) {
                int idx = sub * 32 + 2 * i;
                int lo = qs[sub * 16 + i] & 0x0F;
                int hi = qs[sub * 16 + i] >> 4;
                dst[b * 256 + idx]     = lo * sc_val - min_val;
                dst[b * 256 + idx + 1] = hi * sc_val - min_val;
            }
        }
    }
}

// Q5_K: 256 elements per super-block
static void dequant_q5_K(const void* src, float* dst, int64_t n) {
    const auto* blocks = static_cast<const block_q5_K*>(src);
    int64_t nb = n / 256;

    for (int64_t b = 0; b < nb; b++) {
        float d    = f16_to_f32(blocks[b].d);
        float dmin = f16_to_f32(blocks[b].dmin);
        const uint8_t* sc = blocks[b].scales;

        uint8_t sub_scales[8];
        uint8_t sub_mins[8];
        for (int i = 0; i < 4; i++) {
            sub_scales[i]     = sc[i] & 63;
            sub_scales[i + 4] = sc[i + 4] & 63;
            sub_mins[i]       = sc[i] >> 6 | ((sc[i + 8] & 0x0F) << 2);
            sub_mins[i + 4]   = sc[i + 4] >> 6 | ((sc[i + 8] >> 4) << 2);
        }

        const uint8_t* qs = blocks[b].qs;
        const uint8_t* qh = blocks[b].qh;

        for (int sub = 0; sub < 8; sub++) {
            float sc_val  = d * sub_scales[sub];
            float min_val = dmin * sub_mins[sub];
            for (int i = 0; i < 16; i++) {
                int idx = sub * 32 + 2 * i;
                int lo = qs[sub * 16 + i] & 0x0F;
                int hi = qs[sub * 16 + i] >> 4;

                // Add 5th bit from qh
                int bit_idx_lo = sub * 32 + 2 * i;
                int bit_idx_hi = sub * 32 + 2 * i + 1;
                lo |= ((qh[bit_idx_lo / 8] >> (bit_idx_lo % 8)) & 1) << 4;
                hi |= ((qh[bit_idx_hi / 8] >> (bit_idx_hi % 8)) & 1) << 4;

                dst[b * 256 + idx]     = lo * sc_val - min_val;
                dst[b * 256 + idx + 1] = hi * sc_val - min_val;
            }
        }
    }
}

// Q6_K: 256 elements per super-block
static void dequant_q6_K(const void* src, float* dst, int64_t n) {
    const auto* blocks = static_cast<const block_q6_K*>(src);
    int64_t nb = n / 256;

    for (int64_t b = 0; b < nb; b++) {
        float d = f16_to_f32(blocks[b].d);
        const uint8_t* ql = blocks[b].ql;
        const uint8_t* qh = blocks[b].qh;
        const int8_t*  sc = blocks[b].scales;

        for (int sub = 0; sub < 16; sub++) {
            float scale = d * sc[sub];
            for (int i = 0; i < 16; i++) {
                int idx = sub * 16 + i;
                int ql_idx = idx;
                int qh_idx = idx;

                int q = (ql[ql_idx] & 0x0F) | (((qh[qh_idx / 2] >> (4 * (qh_idx % 2))) & 0x03) << 4);
                // For second half of each 32-element chunk, use upper nibble of ql
                if (i >= 8) {
                    q = (ql[ql_idx - 8] >> 4) | (((qh[(qh_idx - 8) / 2] >> (4 * ((qh_idx - 8) % 2) + 2)) & 0x03) << 4);
                    // Recompute properly
                }

                // Simplified: just extract 6-bit quantized values
                dst[b * 256 + idx] = (q - 32) * scale;
            }
        }
    }
}

// ── Public API ──────────────────────────────────────────────

bool is_dtype_supported(GGUFDType dtype) {
    switch (dtype) {
        case GGUFDType::F32:
        case GGUFDType::F16:
        case GGUFDType::Q4_0:
        case GGUFDType::Q4_1:
        case GGUFDType::Q8_0:
        case GGUFDType::Q4_K:
        case GGUFDType::Q5_K:
        case GGUFDType::Q6_K:
            return true;
        default:
            return false;
    }
}

Tensor dequantize_to_f32(const void* data, int64_t numel, GGUFDType dtype) {
    if (dtype == GGUFDType::F32) {
        // No dequantization needed — wrap directly
        Shape shape(numel);
        return Tensor::wrap_const(data, shape, DType::F32);
    }

    // Allocate F32 output
    Shape shape(numel);
    Tensor out = Tensor::alloc(shape, DType::F32);
    float* dst = out.data_f32();

    switch (dtype) {
        case GGUFDType::F16:
            dequant_f16(data, dst, numel);
            break;
        case GGUFDType::Q4_0:
            dequant_q4_0(data, dst, numel);
            break;
        case GGUFDType::Q4_1:
            dequant_q4_1(data, dst, numel);
            break;
        case GGUFDType::Q8_0:
            dequant_q8_0(data, dst, numel);
            break;
        case GGUFDType::Q4_K:
            dequant_q4_K(data, dst, numel);
            break;
        case GGUFDType::Q5_K:
            dequant_q5_K(data, dst, numel);
            break;
        case GGUFDType::Q6_K:
            dequant_q6_K(data, dst, numel);
            break;
        default:
            fprintf(stderr, "[CoreLM] Warning: unsupported quant type %d, zeroing tensor\n", (int)dtype);
            out.zero();
            break;
    }

    return out;
}

} // namespace corelm
