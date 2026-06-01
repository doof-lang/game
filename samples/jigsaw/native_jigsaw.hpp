#pragma once

#include "doof_runtime.hpp"

#include <cstdint>
#include <string>

namespace doof_game_jigsaw {

doof::Result<void, std::string> buildJigsawAtlas(
    const std::string& photoPath,
    const std::string& maskAtlasPath,
    const std::string& outputPath,
    int32_t columns,
    int32_t rows
);

}  // namespace doof_game_jigsaw
