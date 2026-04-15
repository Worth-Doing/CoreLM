#import "metal_backend.h"
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include <cstring>
#include "../cpu/cpu_ops.h"

namespace corelm {

// ── Internal implementation ─────────────────────────────────

struct MetalBackend::Impl {
    id<MTLDevice>              device          = nil;
    id<MTLCommandQueue>        queue           = nil;
    id<MTLLibrary>             library         = nil;

    // Pipeline states for each kernel
    id<MTLComputePipelineState> pso_matvec_q4_0   = nil;
    id<MTLComputePipelineState> pso_matvec_f32    = nil;
    id<MTLComputePipelineState> pso_rmsnorm       = nil;
    id<MTLComputePipelineState> pso_rope           = nil;
    id<MTLComputePipelineState> pso_silu           = nil;
    id<MTLComputePipelineState> pso_elem_mul       = nil;
    id<MTLComputePipelineState> pso_elem_add       = nil;

    bool createPipeline(id<MTLFunction> fn, id<MTLComputePipelineState>* pso) {
        NSError* error = nil;
        *pso = [device newComputePipelineStateWithFunction:fn error:&error];
        if (error) {
            NSLog(@"[CoreLM Metal] Pipeline error: %@", error);
            return false;
        }
        return true;
    }

    // Create a shared-memory buffer wrapping existing CPU data
    id<MTLBuffer> wrapBuffer(const void* data, size_t size) {
        // Use MTLResourceStorageModeShared — unified memory, no copies needed
        return [device newBufferWithBytesNoCopy:(void*)data
                                        length:size
                                       options:MTLResourceStorageModeShared
                                   deallocator:nil];
    }

    // Create a temporary buffer
    id<MTLBuffer> allocBuffer(size_t size) {
        return [device newBufferWithLength:size
                                  options:MTLResourceStorageModeShared];
    }
};

// ── Lifecycle ───────────────────────────────────────────────

MetalBackend::MetalBackend() {
    impl_ = new Impl();
}

MetalBackend::~MetalBackend() {
    delete impl_;
}

bool MetalBackend::init(const std::string& shader_path) {
    @autoreleasepool {
        impl_->device = MTLCreateSystemDefaultDevice();
        if (!impl_->device) {
            return false;
        }

        impl_->queue = [impl_->device newCommandQueue];
        if (!impl_->queue) {
            return false;
        }

        // Load shader library
        NSError* error = nil;
        if (!shader_path.empty()) {
            NSString* path = [NSString stringWithUTF8String:shader_path.c_str()];
            NSURL* url = [NSURL fileURLWithPath:path];
            impl_->library = [impl_->device newLibraryWithURL:url error:&error];
        }

        if (!impl_->library) {
            // Try loading from default library (embedded in app bundle)
            impl_->library = [impl_->device newDefaultLibrary];
        }

        if (!impl_->library) {
            // Try compiling from source at known path
            NSString* srcPath = nil;
            NSArray* searchPaths = @[
                @"metal/kernels.metal",
                @"../engine/metal/kernels.metal",
                @"../../engine/metal/kernels.metal",
            ];
            for (NSString* p in searchPaths) {
                if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                    srcPath = p;
                    break;
                }
            }

            if (srcPath) {
                NSString* src = [NSString stringWithContentsOfFile:srcPath
                                                         encoding:NSUTF8StringEncoding
                                                            error:&error];
                if (src) {
                    MTLCompileOptions* opts = [[MTLCompileOptions alloc] init];
                    opts.fastMathEnabled = YES;
                    impl_->library = [impl_->device newLibraryWithSource:src options:opts error:&error];
                }
            }
        }

        if (!impl_->library) {
            NSLog(@"[CoreLM Metal] Could not load shader library: %@", error);
            return false;
        }

        // Create pipeline states for each kernel
        auto makePSO = [&](const char* name, id<MTLComputePipelineState>* pso) -> bool {
            NSString* fnName = [NSString stringWithUTF8String:name];
            id<MTLFunction> fn = [impl_->library newFunctionWithName:fnName];
            if (!fn) {
                NSLog(@"[CoreLM Metal] Function not found: %s", name);
                return false;
            }
            return impl_->createPipeline(fn, pso);
        };

        bool ok = true;
        ok &= makePSO("matvec_q4_0",     &impl_->pso_matvec_q4_0);
        ok &= makePSO("matvec_f32",      &impl_->pso_matvec_f32);
        ok &= makePSO("rmsnorm",         &impl_->pso_rmsnorm);
        ok &= makePSO("rope_apply",      &impl_->pso_rope);
        ok &= makePSO("silu_inplace",    &impl_->pso_silu);
        ok &= makePSO("elementwise_mul", &impl_->pso_elem_mul);
        ok &= makePSO("elementwise_add", &impl_->pso_elem_add);

        if (!ok) {
            NSLog(@"[CoreLM Metal] Some pipeline states failed to compile");
            return false;
        }

        available_ = true;
        NSLog(@"[CoreLM Metal] Initialized on %@", impl_->device.name);
        return true;
    }
}

// ── Capability ──────────────────────────────────────────────

bool MetalBackend::supports(OpType op, DType dtype) const {
    if (!available_) return false;

    switch (op) {
        case OpType::MatVec:
            return dtype == DType::F32 || dtype == DType::Q4_0;
        case OpType::RMSNorm:
        case OpType::SiLU:
        case OpType::ElementMul:
        case OpType::ElementAdd:
            return dtype == DType::F32;
        case OpType::RoPE:
        case OpType::Softmax:
            return true;
        case OpType::Embedding:
            return false; // CPU for now — simple memcpy, not worth GPU dispatch
    }
    return false;
}

// ── Sync ────────────────────────────────────────────────────

void MetalBackend::synchronize() {
    // Each dispatch already waits. For batched dispatch, this would wait on a fence.
}

// ── Helper: dispatch a compute kernel ───────────────────────

static void dispatch_1d(id<MTLCommandQueue> queue,
                         id<MTLComputePipelineState> pso,
                         NSArray<id<MTLBuffer>>* buffers,
                         uint grid_size) {
    @autoreleasepool {
        id<MTLCommandBuffer> cmd = [queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        [enc setComputePipelineState:pso];

        for (NSUInteger i = 0; i < buffers.count; i++) {
            [enc setBuffer:buffers[i] offset:0 atIndex:i];
        }

        NSUInteger threadGroupSize = MIN(pso.maxTotalThreadsPerThreadgroup, (NSUInteger)grid_size);
        MTLSize tgs = MTLSizeMake(threadGroupSize, 1, 1);
        MTLSize grid = MTLSizeMake(grid_size, 1, 1);
        [enc dispatchThreads:grid threadsPerThreadgroup:tgs];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];
    }
}

// ── Ops ─────────────────────────────────────────────────────

void MetalBackend::matvec(const Tensor& A, const Tensor& x, Tensor& out) {
    @autoreleasepool {
        int64_t M = A.dim(0);
        int64_t K = A.dim(1);
        uint K_val = (uint)K;

        id<MTLBuffer> bufA, bufX, bufOut, bufK;
        bufX   = impl_->wrapBuffer(x.data(), x.nbytes());
        bufOut = impl_->wrapBuffer(out.data(), out.nbytes());
        bufK   = impl_->allocBuffer(sizeof(uint));
        memcpy(bufK.contents, &K_val, sizeof(uint));

        id<MTLComputePipelineState> pso;
        if (A.dtype() == DType::Q4_0) {
            bufA = impl_->wrapBuffer(A.data(), A.nbytes());
            pso  = impl_->pso_matvec_q4_0;
        } else {
            bufA = impl_->wrapBuffer(A.data(), A.nbytes());
            pso  = impl_->pso_matvec_f32;
        }

        dispatch_1d(impl_->queue, pso, @[bufA, bufX, bufOut, bufK], (uint)M);
    }
}

void MetalBackend::rmsnorm(const Tensor& x, const Tensor& weight, Tensor& out, float eps) {
    @autoreleasepool {
        uint n = (uint)x.numel();

        id<MTLBuffer> bufX = impl_->wrapBuffer(x.data(), x.nbytes());
        id<MTLBuffer> bufW = impl_->wrapBuffer(weight.data(), weight.nbytes());
        id<MTLBuffer> bufO = impl_->wrapBuffer(out.data(), out.nbytes());
        id<MTLBuffer> bufN = impl_->allocBuffer(sizeof(uint));
        id<MTLBuffer> bufE = impl_->allocBuffer(sizeof(float));
        memcpy(bufN.contents, &n, sizeof(uint));
        memcpy(bufE.contents, &eps, sizeof(float));

        dispatch_1d(impl_->queue, impl_->pso_rmsnorm,
                    @[bufX, bufW, bufO, bufN, bufE], n);
    }
}

void MetalBackend::rope(float* q, float* k, int head_dim, int num_heads, int num_kv_heads, int pos, float theta) {
    @autoreleasepool {
        int half_dim = head_dim / 2;
        int total_pairs = num_heads * half_dim;  // max of q and k pairs
        int kv_pairs = num_kv_heads * half_dim;
        int grid = total_pairs > kv_pairs ? total_pairs : kv_pairs;

        size_t q_size = num_heads * head_dim * sizeof(float);
        size_t k_size = num_kv_heads * head_dim * sizeof(float);

        id<MTLBuffer> bufQ  = impl_->wrapBuffer(q, q_size);
        id<MTLBuffer> bufK  = impl_->wrapBuffer(k, k_size);

        id<MTLBuffer> bufHD = impl_->allocBuffer(sizeof(int));
        id<MTLBuffer> bufNH = impl_->allocBuffer(sizeof(int));
        id<MTLBuffer> bufNK = impl_->allocBuffer(sizeof(int));
        id<MTLBuffer> bufP  = impl_->allocBuffer(sizeof(int));
        id<MTLBuffer> bufT  = impl_->allocBuffer(sizeof(float));

        memcpy(bufHD.contents, &head_dim, sizeof(int));
        memcpy(bufNH.contents, &num_heads, sizeof(int));
        memcpy(bufNK.contents, &num_kv_heads, sizeof(int));
        memcpy(bufP.contents, &pos, sizeof(int));
        memcpy(bufT.contents, &theta, sizeof(float));

        dispatch_1d(impl_->queue, impl_->pso_rope,
                    @[bufQ, bufK, bufHD, bufNH, bufNK, bufP, bufT], (uint)grid);
    }
}

void MetalBackend::softmax(float* data, int size) {
    // For small sizes (typical attention seq_len), CPU softmax is faster
    // than GPU dispatch overhead. Use CPU fallback.
    cpu::softmax_inplace(data, size);
}

void MetalBackend::silu_inplace(Tensor& x) {
    @autoreleasepool {
        uint n = (uint)x.numel();
        id<MTLBuffer> bufX = impl_->wrapBuffer(x.data(), x.nbytes());
        id<MTLBuffer> bufN = impl_->allocBuffer(sizeof(uint));
        memcpy(bufN.contents, &n, sizeof(uint));

        dispatch_1d(impl_->queue, impl_->pso_silu, @[bufX, bufN], n);
    }
}

void MetalBackend::mul_inplace(Tensor& a, const Tensor& b) {
    @autoreleasepool {
        uint n = (uint)a.numel();
        id<MTLBuffer> bufA = impl_->wrapBuffer(a.data(), a.nbytes());
        id<MTLBuffer> bufB = impl_->wrapBuffer(b.data(), b.nbytes());
        id<MTLBuffer> bufN = impl_->allocBuffer(sizeof(uint));
        memcpy(bufN.contents, &n, sizeof(uint));

        dispatch_1d(impl_->queue, impl_->pso_elem_mul, @[bufA, bufB, bufN], n);
    }
}

void MetalBackend::add_inplace(Tensor& a, const Tensor& b) {
    @autoreleasepool {
        uint n = (uint)a.numel();
        id<MTLBuffer> bufA = impl_->wrapBuffer(a.data(), a.nbytes());
        id<MTLBuffer> bufB = impl_->wrapBuffer(b.data(), b.nbytes());
        id<MTLBuffer> bufN = impl_->allocBuffer(sizeof(uint));
        memcpy(bufN.contents, &n, sizeof(uint));

        dispatch_1d(impl_->queue, impl_->pso_elem_add, @[bufA, bufB, bufN], n);
    }
}

void MetalBackend::embedding_lookup(const Tensor& table, int token_id, Tensor& out) {
    // Embedding lookup is a simple memcpy — CPU is faster than GPU dispatch overhead
    cpu::embedding_lookup(table, token_id, out);
}

} // namespace corelm
