#pragma once

#include "../backend.h"

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#endif

namespace corelm {

class MetalBackend : public Backend {
public:
    MetalBackend();
    ~MetalBackend();

    bool init(const std::string& shader_path = "");

    std::string name() const override { return "Metal (Apple GPU)"; }
    bool supports(OpType op, DType dtype) const override;

    void matvec(const Tensor& A, const Tensor& x, Tensor& out) override;
    void rmsnorm(const Tensor& x, const Tensor& weight, Tensor& out, float eps) override;
    void rope(float* q, float* k, int head_dim, int num_heads, int num_kv_heads, int pos, float theta) override;
    void softmax(float* data, int size) override;
    void silu_inplace(Tensor& x) override;
    void mul_inplace(Tensor& a, const Tensor& b) override;
    void add_inplace(Tensor& a, const Tensor& b) override;
    void embedding_lookup(const Tensor& table, int token_id, Tensor& out) override;

    void synchronize() override;

    bool is_available() const { return available_; }

private:
    struct Impl;
    Impl* impl_ = nullptr;
    bool available_ = false;
};

} // namespace corelm
