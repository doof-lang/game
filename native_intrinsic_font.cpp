#include "native_intrinsic_font.hpp"

namespace doof_game {
namespace {

#include "native_intrinsic_font_data.inc"

}  // namespace

std::shared_ptr<std::vector<uint8_t>> intrinsicFontGzip() {
    return std::make_shared<std::vector<uint8_t>>(
        inbuilt_fnt_gz,
        inbuilt_fnt_gz + inbuilt_fnt_gz_len
    );
}

std::shared_ptr<std::vector<uint8_t>> intrinsicFontAlpha4Gzip() {
    return std::make_shared<std::vector<uint8_t>>(
        inbuilt_alpha4_gz,
        inbuilt_alpha4_gz + inbuilt_alpha4_gz_len
    );
}

}  // namespace doof_game
