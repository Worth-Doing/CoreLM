#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <cstdint>

namespace corelm {

struct GGUFFile;

class Tokenizer {
public:
    bool load_from_gguf(const GGUFFile& gguf);

    // Encode text to token ids
    std::vector<int32_t> encode(const std::string& text, bool add_bos = true) const;

    // Decode single token id to text
    std::string decode(int32_t token_id) const;

    // Decode multiple token ids
    std::string decode(const std::vector<int32_t>& tokens) const;

    int32_t bos_token() const { return bos_id_; }
    int32_t eos_token() const { return eos_id_; }
    int32_t vocab_size() const { return (int32_t)vocab_.size(); }

    bool is_eos(int32_t token_id) const;

private:
    // BPE merge step
    void bpe_merge(std::vector<std::string>& tokens) const;

    std::vector<std::string> vocab_;                   // id -> token string
    std::unordered_map<std::string, int32_t> token_to_id_;
    std::vector<float> scores_;                        // token scores (for BPE priority)
    std::vector<int32_t> token_types_;                 // 0=normal, 1=unknown, 2=control, 3=user_defined, etc.

    // BPE merge rules
    struct MergePair {
        std::string left;
        std::string right;
    };
    std::vector<MergePair> merges_;
    std::unordered_map<std::string, int> merge_rank_;  // "left right" -> rank

    int32_t bos_id_ = 1;
    int32_t eos_id_ = 2;
    int32_t unk_id_ = 0;

    std::string model_type_;  // "llama", "gpt2", etc.
};

} // namespace corelm
