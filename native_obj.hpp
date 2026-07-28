#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "doof_runtime.hpp"

namespace doof_game {

// Streams tokenized OBJ records without normalizing or splitting the complete
// source string. The source is borrowed for the tokenizer's lifetime; its Doof
// wrapper keeps the source parameter alive until parsing has completed.
class NativeObjTokenizer {
public:
    static std::shared_ptr<NativeObjTokenizer> constructor(const std::string& source) {
        return std::shared_ptr<NativeObjTokenizer>(new NativeObjTokenizer(source));
    }

    bool next() {
        tokens_->clear();

        while (position_ < source_.size()) {
            ++lineNumber_;

            const size_t lineStart = position_;
            size_t lineEnd = lineStart;
            while (lineEnd < source_.size() && source_[lineEnd] != '\n' && source_[lineEnd] != '\r') {
                ++lineEnd;
            }

            position_ = lineEnd;
            if (position_ < source_.size()) {
                if (source_[position_] == '\r' &&
                    position_ + 1 < source_.size() &&
                    source_[position_ + 1] == '\n') {
                    position_ += 2;
                } else {
                    ++position_;
                }
            }

            size_t contentEnd = lineStart;
            while (contentEnd < lineEnd && source_[contentEnd] != '#') {
                ++contentEnd;
            }

            size_t tokenStart = lineStart;
            while (tokenStart < contentEnd) {
                while (tokenStart < contentEnd && isWhitespace(source_[tokenStart])) {
                    ++tokenStart;
                }
                if (tokenStart == contentEnd) {
                    break;
                }

                size_t tokenEnd = tokenStart + 1;
                while (tokenEnd < contentEnd && !isWhitespace(source_[tokenEnd])) {
                    ++tokenEnd;
                }
                tokens_->emplace_back(source_, tokenStart, tokenEnd - tokenStart);
                tokenStart = tokenEnd;
            }

            if (!tokens_->empty()) {
                return true;
            }
        }

        return false;
    }

    int32_t lineNumber() const {
        return lineNumber_;
    }

    std::shared_ptr<std::vector<std::string>> tokens() const {
        return tokens_;
    }

private:
    explicit NativeObjTokenizer(const std::string& source)
        : source_(source),
          tokens_(std::make_shared<std::vector<std::string>>()) {
        tokens_->reserve(8);
    }

    static bool isWhitespace(char value) {
        return value == ' ' || value == '\t' || value == '\f' || value == '\v';
    }

    const std::string& source_;
    std::shared_ptr<std::vector<std::string>> tokens_;
    size_t position_ = 0;
    int32_t lineNumber_ = 0;
};

} // namespace doof_game
