#pragma once

#include "doof_runtime.hpp"

#include <cstdint>
#include <memory>
#include <vector>

namespace doof_game {

// Compressed source data is kept native so the intrinsic font does not inflate
// generated Doof code or require runtime asset files.
std::shared_ptr<std::vector<uint8_t>> intrinsicFontGzip();
std::shared_ptr<std::vector<uint8_t>> intrinsicFontAlpha4Gzip();

}  // namespace doof_game
