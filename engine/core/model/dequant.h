#pragma once

#include "../tensor/tensor.h"
#include "gguf.h"

namespace corelm {

// Dequantize any GGUF tensor to F32.
// Supports: F32 (passthrough), F16, Q4_0, Q4_1, Q8_0, Q4_K, Q5_K, Q6_K
// Returns an owned F32 tensor (allocates new storage).
// For F32 input, wraps the existing data (no copy).
Tensor dequantize_to_f32(const void* data, int64_t numel, GGUFDType dtype);

// Check if a GGUF dtype is supported for dequantization
bool is_dtype_supported(GGUFDType dtype);

} // namespace corelm
