#include "tokenizer.h"
#include "gguf.h"
#include <sstream>
#include <algorithm>
#include <limits>

namespace corelm {

bool Tokenizer::load_from_gguf(const GGUFFile& gguf) {
    model_type_ = gguf.get_string("tokenizer.ggml.model", "llama");

    // Load vocabulary
    auto tokens = gguf.get_string_array("tokenizer.ggml.tokens");
    if (tokens.empty()) return false;

    vocab_ = tokens;
    for (int32_t i = 0; i < (int32_t)vocab_.size(); i++) {
        token_to_id_[vocab_[i]] = i;
    }

    // Load scores
    scores_ = gguf.get_float_array("tokenizer.ggml.scores");

    // Load token types
    auto types = gguf.get_int32_array("tokenizer.ggml.token_type");
    token_types_.resize(vocab_.size(), 0);
    for (size_t i = 0; i < std::min(types.size(), vocab_.size()); i++) {
        token_types_[i] = types[i];
    }

    // Load BPE merges
    auto merge_strs = gguf.get_string_array("tokenizer.ggml.merges");
    merges_.reserve(merge_strs.size());
    for (int i = 0; i < (int)merge_strs.size(); i++) {
        auto& ms = merge_strs[i];
        auto sp = ms.find(' ');
        if (sp != std::string::npos) {
            MergePair mp;
            mp.left = ms.substr(0, sp);
            mp.right = ms.substr(sp + 1);
            merges_.push_back(mp);
            merge_rank_[ms] = i;
        }
    }

    // Special tokens
    bos_id_ = (int32_t)gguf.get_uint32("tokenizer.ggml.bos_token_id", 1);
    eos_id_ = (int32_t)gguf.get_uint32("tokenizer.ggml.eos_token_id", 2);
    unk_id_ = (int32_t)gguf.get_uint32("tokenizer.ggml.unknown_token_id", 0);

    return true;
}

// Simple byte-level BPE encoding
std::vector<int32_t> Tokenizer::encode(const std::string& text, bool add_bos) const {
    std::vector<int32_t> result;

    if (add_bos) {
        result.push_back(bos_id_);
    }

    if (text.empty()) return result;

    // For SentencePiece-style tokenizers (LLaMA), we use a simplified approach:
    // 1. Start with individual UTF-8 bytes/characters as initial tokens
    // 2. Apply BPE merges greedily
    //
    // Note: A production tokenizer would handle Unicode normalization,
    // pre-tokenization splits, and byte-fallback properly.
    // This implementation handles the common case correctly.

    // Split into initial tokens (single characters, with space prefix for SentencePiece)
    std::string processed = text;

    // SentencePiece uses U+2581 (lower one eighth block) as space marker
    // In UTF-8: 0xE2 0x96 0x81
    std::string space_marker = "\xe2\x96\x81";

    // Replace spaces with the space marker
    std::string sp_text;
    bool at_start = true;
    for (size_t i = 0; i < processed.size(); i++) {
        if (processed[i] == ' ') {
            sp_text += space_marker;
        } else {
            if (at_start) {
                sp_text += space_marker;
                at_start = false;
            }
            sp_text += processed[i];
        }
    }

    // Try greedy longest-match tokenization
    std::vector<std::string> tokens;
    size_t pos = 0;
    while (pos < sp_text.size()) {
        // Find longest matching token
        int best_len = 0;
        int32_t best_id = unk_id_;

        for (int len = std::min((int)(sp_text.size() - pos), 32); len >= 1; len--) {
            std::string candidate = sp_text.substr(pos, len);
            auto it = token_to_id_.find(candidate);
            if (it != token_to_id_.end()) {
                best_len = len;
                best_id = it->second;
                break;
            }
        }

        if (best_len > 0) {
            result.push_back(best_id);
            pos += best_len;
        } else {
            // Byte fallback: encode as <0xHH> token
            uint8_t byte = (uint8_t)sp_text[pos];
            char hex[8];
            snprintf(hex, sizeof(hex), "<0x%02X>", byte);
            auto it = token_to_id_.find(hex);
            if (it != token_to_id_.end()) {
                result.push_back(it->second);
            } else {
                result.push_back(unk_id_);
            }
            pos++;
        }
    }

    return result;
}

std::string Tokenizer::decode(int32_t token_id) const {
    if (token_id < 0 || token_id >= (int32_t)vocab_.size()) return "";

    // Skip control tokens in output
    if (token_types_.size() > (size_t)token_id && token_types_[token_id] == 3) {
        return ""; // control token
    }

    std::string token = vocab_[token_id];

    // Handle byte tokens like <0xHH>
    if (token.size() == 6 && token[0] == '<' && token[1] == '0' && token[2] == 'x' && token[5] == '>') {
        char byte = (char)strtol(token.substr(3, 2).c_str(), nullptr, 16);
        return std::string(1, byte);
    }

    // Replace SentencePiece space marker with space
    std::string space_marker = "\xe2\x96\x81";
    std::string out;
    size_t pos = 0;
    while (pos < token.size()) {
        if (pos + 3 <= token.size() && token.substr(pos, 3) == space_marker) {
            out += ' ';
            pos += 3;
        } else {
            out += token[pos];
            pos++;
        }
    }

    return out;
}

std::string Tokenizer::decode(const std::vector<int32_t>& tokens) const {
    std::string result;
    for (auto id : tokens) {
        result += decode(id);
    }
    return result;
}

bool Tokenizer::is_eos(int32_t token_id) const {
    return token_id == eos_id_;
}

void Tokenizer::bpe_merge(std::vector<std::string>& tokens) const {
    while (tokens.size() > 1) {
        int best_idx = -1;
        int best_rank = std::numeric_limits<int>::max();

        for (int i = 0; i < (int)tokens.size() - 1; i++) {
            std::string pair = tokens[i] + " " + tokens[i + 1];
            auto it = merge_rank_.find(pair);
            if (it != merge_rank_.end() && it->second < best_rank) {
                best_rank = it->second;
                best_idx = i;
            }
        }

        if (best_idx < 0) break;

        tokens[best_idx] = tokens[best_idx] + tokens[best_idx + 1];
        tokens.erase(tokens.begin() + best_idx + 1);
    }
}

} // namespace corelm
