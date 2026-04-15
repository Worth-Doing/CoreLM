#pragma once

#include <cstdint>
#include <string>
#include <vector>
#include <unordered_map>
#include <variant>
#include <memory>

namespace corelm {

// GGUF metadata value types
enum class GGUFValueType : uint32_t {
    UINT8   = 0,
    INT8    = 1,
    UINT16  = 2,
    INT16   = 3,
    UINT32  = 4,
    INT32   = 5,
    FLOAT32 = 6,
    BOOL    = 7,
    STRING  = 8,
    ARRAY   = 9,
    UINT64  = 10,
    INT64   = 11,
    FLOAT64 = 12,
};

// GGUF tensor data types (maps to quantization schemes)
enum class GGUFDType : uint32_t {
    F32     = 0,
    F16     = 1,
    Q4_0    = 2,
    Q4_1    = 3,
    Q5_0    = 6,
    Q5_1    = 7,
    Q8_0    = 8,
    Q8_1    = 9,
    Q2_K    = 10,
    Q3_K    = 11,
    Q4_K    = 12,
    Q5_K    = 13,
    Q6_K    = 14,
    Q8_K    = 15,
    IQ2_XXS = 16,
    IQ2_XS  = 17,
    IQ3_XXS = 18,
    IQ1_S   = 19,
    IQ4_NL  = 20,
    IQ3_S   = 21,
    IQ2_S   = 22,
    IQ4_XS  = 23,
    I8      = 24,
    I16     = 25,
    I32     = 26,
    I64     = 27,
    F64     = 28,
    IQ1_M   = 29,
};

// Size of one block for quantized types, or element size for non-quantized
size_t gguf_dtype_block_size(GGUFDType dt);
size_t gguf_dtype_type_size(GGUFDType dt);  // bytes per block
const char* gguf_dtype_name(GGUFDType dt);

using GGUFValue = std::variant<
    uint8_t, int8_t, uint16_t, int16_t,
    uint32_t, int32_t, float,
    bool, std::string,
    uint64_t, int64_t, double,
    std::vector<std::string>,    // string arrays
    std::vector<float>,          // float arrays
    std::vector<int32_t>,        // int arrays
    std::vector<uint32_t>        // uint arrays
>;

struct GGUFTensorInfo {
    std::string name;
    uint32_t    ndim = 0;
    int64_t     shape[4] = {};
    GGUFDType   dtype = GGUFDType::F32;
    uint64_t    offset = 0;  // relative to data section start
    size_t      nbytes = 0;  // computed total bytes
};

struct GGUFFile {
    uint32_t version = 0;
    uint64_t tensor_count = 0;
    uint64_t metadata_kv_count = 0;

    std::unordered_map<std::string, GGUFValue> metadata;
    std::vector<GGUFTensorInfo> tensors;
    std::unordered_map<std::string, size_t> tensor_index; // name -> index in tensors

    // Memory-mapped data
    const uint8_t* data_base = nullptr;  // start of tensor data section
    size_t file_size = 0;

    // Helpers
    bool has_key(const std::string& key) const;

    std::string get_string(const std::string& key, const std::string& default_val = "") const;
    uint32_t    get_uint32(const std::string& key, uint32_t default_val = 0) const;
    int32_t     get_int32(const std::string& key, int32_t default_val = 0) const;
    uint64_t    get_uint64(const std::string& key, uint64_t default_val = 0) const;
    float       get_float(const std::string& key, float default_val = 0.0f) const;
    bool        get_bool(const std::string& key, bool default_val = false) const;

    std::vector<std::string> get_string_array(const std::string& key) const;
    std::vector<float>       get_float_array(const std::string& key) const;
    std::vector<int32_t>     get_int32_array(const std::string& key) const;

    const GGUFTensorInfo* find_tensor(const std::string& name) const;
    const void* tensor_data(const std::string& name) const;
};

// Parse a GGUF file (memory maps the file)
struct GGUFParseResult {
    bool success = false;
    std::string error;
    std::unique_ptr<GGUFFile> file;
};

GGUFParseResult gguf_parse(const std::string& path);

// Validate a GGUF file for CoreLM compatibility (llama arch, supported quant)
struct GGUFValidateResult {
    bool valid = false;
    std::string error;
    std::string architecture;
    std::string model_name;
    std::string quantization;
    uint64_t file_size = 0;
};

GGUFValidateResult gguf_validate(const std::string& path);

} // namespace corelm
