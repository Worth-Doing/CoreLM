#include "backend.h"
#include "cpu/cpu_ops.h"
#include "metal/metal_backend.h"

namespace corelm {

// ── CPUBackend ──────────────────────────────────────────────

bool CPUBackend::supports(OpType /*op*/, DType /*dtype*/) const {
    return true; // CPU supports everything as reference
}

void CPUBackend::matvec(const Tensor& A, const Tensor& x, Tensor& out) {
    cpu::matvec(A, x, out);
}

void CPUBackend::rmsnorm(const Tensor& x, const Tensor& weight, Tensor& out, float eps) {
    cpu::rmsnorm(x, weight, out, eps);
}

void CPUBackend::rope(float* q, float* k, int head_dim, int num_heads, int num_kv_heads, int pos, float theta) {
    cpu::rope(q, k, head_dim, num_heads, num_kv_heads, pos, theta);
}

void CPUBackend::softmax(float* data, int size) {
    cpu::softmax_inplace(data, size);
}

void CPUBackend::silu_inplace(Tensor& x) {
    cpu::silu_inplace(x);
}

void CPUBackend::mul_inplace(Tensor& a, const Tensor& b) {
    cpu::mul_inplace(a, b);
}

void CPUBackend::add_inplace(Tensor& a, const Tensor& b) {
    cpu::add_inplace(a, b);
}

void CPUBackend::embedding_lookup(const Tensor& table, int token_id, Tensor& out) {
    cpu::embedding_lookup(table, token_id, out);
}

// ── Factory ─────────────────────────────────────────────────

std::unique_ptr<Backend> create_backend(const std::string& requested) {
    if (requested == "cpu") {
        return std::make_unique<CPUBackend>();
    }

    // Try Metal if requested or auto
    if (requested == "metal" || requested == "auto" || requested.empty()) {
        auto metal = std::make_unique<MetalBackend>();
        if (metal->init()) {
            return metal;
        }
        // Metal failed — fall back to CPU
        if (requested == "metal") {
            // Explicitly requested Metal but failed
            return nullptr;
        }
    }

    return std::make_unique<CPUBackend>();
}

} // namespace corelm
