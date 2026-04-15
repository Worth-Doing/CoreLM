#pragma once

#include "../tensor/tensor.h"
#include <string>
#include <memory>

namespace corelm {

// Operation types for capability reporting
enum class OpType {
    MatVec,
    RMSNorm,
    RoPE,
    Softmax,
    SiLU,
    ElementMul,
    ElementAdd,
    Embedding,
};

class Backend {
public:
    virtual ~Backend() = default;

    virtual std::string name() const = 0;
    virtual bool supports(OpType op, DType dtype) const = 0;

    // Core ops
    virtual void matvec(const Tensor& A, const Tensor& x, Tensor& out) = 0;
    virtual void rmsnorm(const Tensor& x, const Tensor& weight, Tensor& out, float eps) = 0;
    virtual void rope(float* q, float* k, int head_dim, int num_heads, int num_kv_heads, int pos, float theta) = 0;
    virtual void softmax(float* data, int size) = 0;
    virtual void silu_inplace(Tensor& x) = 0;
    virtual void mul_inplace(Tensor& a, const Tensor& b) = 0;
    virtual void add_inplace(Tensor& a, const Tensor& b) = 0;
    virtual void embedding_lookup(const Tensor& table, int token_id, Tensor& out) = 0;

    // Synchronize async ops (Metal command buffers, etc.)
    virtual void synchronize() {}
};

// CPU backend using Accelerate
class CPUBackend : public Backend {
public:
    std::string name() const override { return "CPU (Accelerate)"; }
    bool supports(OpType op, DType dtype) const override;

    void matvec(const Tensor& A, const Tensor& x, Tensor& out) override;
    void rmsnorm(const Tensor& x, const Tensor& weight, Tensor& out, float eps) override;
    void rope(float* q, float* k, int head_dim, int num_heads, int num_kv_heads, int pos, float theta) override;
    void softmax(float* data, int size) override;
    void silu_inplace(Tensor& x) override;
    void mul_inplace(Tensor& a, const Tensor& b) override;
    void add_inplace(Tensor& a, const Tensor& b) override;
    void embedding_lookup(const Tensor& table, int token_id, Tensor& out) override;
};

// Factory
std::unique_ptr<Backend> create_backend(const std::string& name);

} // namespace corelm
