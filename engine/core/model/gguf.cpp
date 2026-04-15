#include "gguf.h"
#include <fstream>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstring>

namespace corelm {

// GGUF format constants
static constexpr uint32_t GGUF_MAGIC = 0x46475547; // "GGUF" in little-endian
static constexpr uint32_t GGUF_VERSION_3 = 3;

size_t gguf_dtype_block_size(GGUFDType dt) {
    switch (dt) {
        case GGUFDType::F32:  return 1;
        case GGUFDType::F16:  return 1;
        case GGUFDType::Q4_0: return 32;
        case GGUFDType::Q4_1: return 32;
        case GGUFDType::Q5_0: return 32;
        case GGUFDType::Q5_1: return 32;
        case GGUFDType::Q8_0: return 32;
        case GGUFDType::Q8_1: return 32;
        case GGUFDType::Q2_K: return 256;
        case GGUFDType::Q3_K: return 256;
        case GGUFDType::Q4_K: return 256;
        case GGUFDType::Q5_K: return 256;
        case GGUFDType::Q6_K: return 256;
        case GGUFDType::Q8_K: return 256;
        case GGUFDType::I8:   return 1;
        case GGUFDType::I16:  return 1;
        case GGUFDType::I32:  return 1;
        case GGUFDType::I64:  return 1;
        case GGUFDType::F64:  return 1;
        default: return 0;
    }
}

size_t gguf_dtype_type_size(GGUFDType dt) {
    switch (dt) {
        case GGUFDType::F32:  return 4;
        case GGUFDType::F16:  return 2;
        case GGUFDType::Q4_0: return 18;    // 2 + 16
        case GGUFDType::Q4_1: return 20;    // 2 + 2 + 16
        case GGUFDType::Q5_0: return 22;    // 2 + 4 + 16
        case GGUFDType::Q5_1: return 24;
        case GGUFDType::Q8_0: return 34;    // 2 + 32
        case GGUFDType::Q8_1: return 40;
        case GGUFDType::Q2_K: return 84;
        case GGUFDType::Q3_K: return 110;
        case GGUFDType::Q4_K: return 144;
        case GGUFDType::Q5_K: return 176;
        case GGUFDType::Q6_K: return 210;
        case GGUFDType::Q8_K: return 292;
        case GGUFDType::I8:   return 1;
        case GGUFDType::I16:  return 2;
        case GGUFDType::I32:  return 4;
        case GGUFDType::I64:  return 8;
        case GGUFDType::F64:  return 8;
        default: return 0;
    }
}

const char* gguf_dtype_name(GGUFDType dt) {
    switch (dt) {
        case GGUFDType::F32:  return "F32";
        case GGUFDType::F16:  return "F16";
        case GGUFDType::Q4_0: return "Q4_0";
        case GGUFDType::Q4_1: return "Q4_1";
        case GGUFDType::Q5_0: return "Q5_0";
        case GGUFDType::Q5_1: return "Q5_1";
        case GGUFDType::Q8_0: return "Q8_0";
        case GGUFDType::Q4_K: return "Q4_K";
        case GGUFDType::Q5_K: return "Q5_K";
        case GGUFDType::Q6_K: return "Q6_K";
        default: return "unknown";
    }
}

// Binary reader helper
class BinaryReader {
public:
    BinaryReader(const uint8_t* data, size_t size) : data_(data), size_(size), pos_(0) {}

    bool has(size_t n) const { return pos_ + n <= size_; }
    size_t pos() const { return pos_; }

    template<typename T>
    T read() {
        if (!has(sizeof(T))) throw std::runtime_error("unexpected end of file");
        T val;
        std::memcpy(&val, data_ + pos_, sizeof(T));
        pos_ += sizeof(T);
        return val;
    }

    std::string read_string() {
        uint64_t len = read<uint64_t>();
        if (!has(len)) throw std::runtime_error("string extends past end of file");
        std::string s(reinterpret_cast<const char*>(data_ + pos_), len);
        pos_ += len;
        return s;
    }

    void skip(size_t n) {
        if (!has(n)) throw std::runtime_error("skip extends past end of file");
        pos_ += n;
    }

    void align(size_t alignment) {
        size_t r = pos_ % alignment;
        if (r != 0) pos_ += alignment - r;
    }

    const uint8_t* ptr() const { return data_ + pos_; }

private:
    const uint8_t* data_;
    size_t size_;
    size_t pos_;
};

// Read a GGUF metadata value
static GGUFValue read_value(BinaryReader& reader, GGUFValueType type) {
    switch (type) {
        case GGUFValueType::UINT8:   return reader.read<uint8_t>();
        case GGUFValueType::INT8:    return reader.read<int8_t>();
        case GGUFValueType::UINT16:  return reader.read<uint16_t>();
        case GGUFValueType::INT16:   return reader.read<int16_t>();
        case GGUFValueType::UINT32:  return reader.read<uint32_t>();
        case GGUFValueType::INT32:   return reader.read<int32_t>();
        case GGUFValueType::FLOAT32: return reader.read<float>();
        case GGUFValueType::BOOL:    return (bool)reader.read<uint8_t>();
        case GGUFValueType::STRING:  return reader.read_string();
        case GGUFValueType::UINT64:  return reader.read<uint64_t>();
        case GGUFValueType::INT64:   return reader.read<int64_t>();
        case GGUFValueType::FLOAT64: return reader.read<double>();
        case GGUFValueType::ARRAY: {
            auto elem_type = static_cast<GGUFValueType>(reader.read<uint32_t>());
            uint64_t count = reader.read<uint64_t>();

            if (elem_type == GGUFValueType::STRING) {
                std::vector<std::string> arr;
                arr.reserve(count);
                for (uint64_t i = 0; i < count; i++) {
                    arr.push_back(reader.read_string());
                }
                return arr;
            } else if (elem_type == GGUFValueType::FLOAT32) {
                std::vector<float> arr(count);
                for (uint64_t i = 0; i < count; i++) {
                    arr[i] = reader.read<float>();
                }
                return arr;
            } else if (elem_type == GGUFValueType::INT32) {
                std::vector<int32_t> arr(count);
                for (uint64_t i = 0; i < count; i++) {
                    arr[i] = reader.read<int32_t>();
                }
                return arr;
            } else if (elem_type == GGUFValueType::UINT32) {
                std::vector<uint32_t> arr(count);
                for (uint64_t i = 0; i < count; i++) {
                    arr[i] = reader.read<uint32_t>();
                }
                return arr;
            } else {
                // For other array types, read and discard
                for (uint64_t i = 0; i < count; i++) {
                    read_value(reader, elem_type);
                }
                return std::vector<int32_t>{}; // empty placeholder
            }
        }
    }
    throw std::runtime_error("unknown GGUF value type");
}

// GGUFFile accessor methods
bool GGUFFile::has_key(const std::string& key) const {
    return metadata.count(key) > 0;
}

std::string GGUFFile::get_string(const std::string& key, const std::string& default_val) const {
    auto it = metadata.find(key);
    if (it == metadata.end()) return default_val;
    if (auto* v = std::get_if<std::string>(&it->second)) return *v;
    return default_val;
}

uint32_t GGUFFile::get_uint32(const std::string& key, uint32_t default_val) const {
    auto it = metadata.find(key);
    if (it == metadata.end()) return default_val;
    if (auto* v = std::get_if<uint32_t>(&it->second)) return *v;
    if (auto* v = std::get_if<int32_t>(&it->second)) return static_cast<uint32_t>(*v);
    if (auto* v = std::get_if<uint64_t>(&it->second)) return static_cast<uint32_t>(*v);
    return default_val;
}

int32_t GGUFFile::get_int32(const std::string& key, int32_t default_val) const {
    auto it = metadata.find(key);
    if (it == metadata.end()) return default_val;
    if (auto* v = std::get_if<int32_t>(&it->second)) return *v;
    if (auto* v = std::get_if<uint32_t>(&it->second)) return static_cast<int32_t>(*v);
    return default_val;
}

uint64_t GGUFFile::get_uint64(const std::string& key, uint64_t default_val) const {
    auto it = metadata.find(key);
    if (it == metadata.end()) return default_val;
    if (auto* v = std::get_if<uint64_t>(&it->second)) return *v;
    if (auto* v = std::get_if<uint32_t>(&it->second)) return *v;
    if (auto* v = std::get_if<int32_t>(&it->second)) return static_cast<uint64_t>(*v);
    return default_val;
}

float GGUFFile::get_float(const std::string& key, float default_val) const {
    auto it = metadata.find(key);
    if (it == metadata.end()) return default_val;
    if (auto* v = std::get_if<float>(&it->second)) return *v;
    if (auto* v = std::get_if<double>(&it->second)) return static_cast<float>(*v);
    return default_val;
}

bool GGUFFile::get_bool(const std::string& key, bool default_val) const {
    auto it = metadata.find(key);
    if (it == metadata.end()) return default_val;
    if (auto* v = std::get_if<bool>(&it->second)) return *v;
    return default_val;
}

std::vector<std::string> GGUFFile::get_string_array(const std::string& key) const {
    auto it = metadata.find(key);
    if (it == metadata.end()) return {};
    if (auto* v = std::get_if<std::vector<std::string>>(&it->second)) return *v;
    return {};
}

std::vector<float> GGUFFile::get_float_array(const std::string& key) const {
    auto it = metadata.find(key);
    if (it == metadata.end()) return {};
    if (auto* v = std::get_if<std::vector<float>>(&it->second)) return *v;
    return {};
}

std::vector<int32_t> GGUFFile::get_int32_array(const std::string& key) const {
    auto it = metadata.find(key);
    if (it == metadata.end()) return {};
    if (auto* v = std::get_if<std::vector<int32_t>>(&it->second)) return *v;
    return {};
}

const GGUFTensorInfo* GGUFFile::find_tensor(const std::string& name) const {
    auto it = tensor_index.find(name);
    if (it == tensor_index.end()) return nullptr;
    return &tensors[it->second];
}

const void* GGUFFile::tensor_data(const std::string& name) const {
    auto* info = find_tensor(name);
    if (!info || !data_base) return nullptr;
    return data_base + info->offset;
}

// Main parser

// RAII wrapper for mmap'd file
struct MappedFile {
    void*  data = MAP_FAILED;
    size_t size = 0;
    int    fd   = -1;

    ~MappedFile() {
        if (data != MAP_FAILED) munmap(data, size);
        if (fd >= 0) close(fd);
    }
};

GGUFParseResult gguf_parse(const std::string& path) {
    GGUFParseResult result;

    // Open and mmap
    auto mapped = std::make_shared<MappedFile>();
    mapped->fd = open(path.c_str(), O_RDONLY);
    if (mapped->fd < 0) {
        result.error = "cannot open file: " + path;
        return result;
    }

    struct stat st;
    if (fstat(mapped->fd, &st) < 0) {
        result.error = "cannot stat file";
        return result;
    }
    mapped->size = st.st_size;

    mapped->data = mmap(nullptr, mapped->size, PROT_READ, MAP_PRIVATE, mapped->fd, 0);
    if (mapped->data == MAP_FAILED) {
        result.error = "mmap failed";
        return result;
    }

    try {
        BinaryReader reader(static_cast<const uint8_t*>(mapped->data), mapped->size);

        // Header
        uint32_t magic = reader.read<uint32_t>();
        if (magic != GGUF_MAGIC) {
            result.error = "invalid GGUF magic";
            return result;
        }

        auto file = std::make_unique<GGUFFile>();
        file->file_size = mapped->size;

        file->version = reader.read<uint32_t>();
        if (file->version < GGUF_VERSION_3) {
            result.error = "unsupported GGUF version: " + std::to_string(file->version);
            return result;
        }

        file->tensor_count = reader.read<uint64_t>();
        file->metadata_kv_count = reader.read<uint64_t>();

        // Metadata
        for (uint64_t i = 0; i < file->metadata_kv_count; i++) {
            std::string key = reader.read_string();
            auto value_type = static_cast<GGUFValueType>(reader.read<uint32_t>());
            GGUFValue value = read_value(reader, value_type);
            file->metadata[key] = std::move(value);
        }

        // Tensor descriptors
        file->tensors.resize(file->tensor_count);
        for (uint64_t i = 0; i < file->tensor_count; i++) {
            auto& ti = file->tensors[i];
            ti.name = reader.read_string();
            ti.ndim = reader.read<uint32_t>();
            for (uint32_t d = 0; d < ti.ndim && d < 4; d++) {
                ti.shape[d] = reader.read<int64_t>();
            }
            ti.dtype = static_cast<GGUFDType>(reader.read<uint32_t>());
            ti.offset = reader.read<uint64_t>();

            // Compute nbytes
            int64_t numel = 1;
            for (uint32_t d = 0; d < ti.ndim; d++) numel *= ti.shape[d];
            size_t block_size = gguf_dtype_block_size(ti.dtype);
            size_t type_size = gguf_dtype_type_size(ti.dtype);
            if (block_size > 0 && type_size > 0) {
                ti.nbytes = ((numel + block_size - 1) / block_size) * type_size;
            }

            file->tensor_index[ti.name] = i;
        }

        // Align to 32 bytes for data section
        reader.align(32);
        file->data_base = static_cast<const uint8_t*>(mapped->data) + reader.pos();

        // Keep the mapping alive (store the shared_ptr in a way accessible to GGUFFile)
        // We use a static map keyed by data_base pointer as a simple approach
        // Actually, we'll store it via a custom destructor-based mechanism
        // For now, leak the mapping intentionally — it lives for the process lifetime
        // which is correct for model weights (memory-mapped, OS manages paging)
        mapped.reset(new MappedFile(*mapped)); // prevent destruction
        // Prevent RAII cleanup — the mmap stays alive
        auto* leak = new std::shared_ptr<MappedFile>(mapped);
        (void)leak;

        result.file = std::move(file);
        result.success = true;

    } catch (const std::exception& e) {
        result.error = std::string("parse error: ") + e.what();
    }

    return result;
}

GGUFValidateResult gguf_validate(const std::string& path) {
    GGUFValidateResult result;

    auto parse = gguf_parse(path);
    if (!parse.success) {
        result.error = parse.error;
        return result;
    }

    auto& f = *parse.file;
    result.file_size = f.file_size;
    result.architecture = f.get_string("general.architecture");
    result.model_name = f.get_string("general.name");

    // Check architecture
    if (result.architecture != "llama") {
        result.error = "unsupported architecture: " + result.architecture + " (expected llama)";
        return result;
    }

    // Determine quantization from tensor types
    if (!f.tensors.empty()) {
        // Look at the first attention weight tensor to determine quant type
        for (auto& t : f.tensors) {
            if (t.name.find("attn_q.weight") != std::string::npos ||
                t.name.find("attn_output.weight") != std::string::npos) {
                result.quantization = gguf_dtype_name(t.dtype);
                break;
            }
        }
        if (result.quantization.empty()) {
            result.quantization = gguf_dtype_name(f.tensors[0].dtype);
        }
    }

    // Check we support this quantization
    bool supported = (result.quantization == "Q4_0" ||
                      result.quantization == "F16" ||
                      result.quantization == "F32");
    if (!supported) {
        result.error = "unsupported quantization: " + result.quantization;
        return result;
    }

    result.valid = true;
    return result;
}

} // namespace corelm
