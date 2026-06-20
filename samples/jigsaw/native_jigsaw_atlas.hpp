#pragma once

#include "doof_runtime.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <memory>
#include <new>
#include <string>
#include <vector>

namespace doof_game_jigsaw {

// Composes already-decoded straight-alpha RGBA pixels. Image decoding, colour
// normalization, and ownership remain in std/image; this helper only accelerates
// the sample's pixel-addressing loop.
inline doof::Result<std::shared_ptr<std::vector<uint8_t>>, std::string> composeJigsawAtlas(
    const std::shared_ptr<std::vector<uint8_t>>& photo,
    int32_t photoWidth,
    int32_t photoHeight,
    const std::shared_ptr<std::vector<uint8_t>>& mask,
    int32_t maskWidth,
    int32_t maskHeight,
    int32_t columns,
    int32_t rows
) {
    if (photoWidth <= 0 || photoHeight <= 0 || maskWidth <= 0 || maskHeight <= 0) {
        return doof::Result<std::shared_ptr<std::vector<uint8_t>>, std::string>::failure(
            "Jigsaw source images must have positive dimensions"
        );
    }
    if (columns <= 0 || rows <= 0 || maskWidth % columns != 0 || maskHeight % rows != 0) {
        return doof::Result<std::shared_ptr<std::vector<uint8_t>>, std::string>::failure(
            "Jigsaw grid must divide the mask atlas dimensions"
        );
    }

    const size_t photoPixelCount = static_cast<size_t>(photoWidth) * static_cast<size_t>(photoHeight);
    const size_t maskPixelCount = static_cast<size_t>(maskWidth) * static_cast<size_t>(maskHeight);
    if (photoPixelCount > std::numeric_limits<size_t>::max() / 4u ||
        maskPixelCount > std::numeric_limits<size_t>::max() / 4u ||
        !photo || photo->size() != photoPixelCount * 4u ||
        !mask || mask->size() != maskPixelCount * 4u) {
        return doof::Result<std::shared_ptr<std::vector<uint8_t>>, std::string>::failure(
            "Jigsaw source pixel payload has an invalid size"
        );
    }

    const int32_t cellWidth = maskWidth / columns;
    const int32_t cellHeight = maskHeight / rows;
    const int32_t cropSide = std::min(photoWidth, photoHeight);
    const int32_t cropX = (photoWidth - cropSide) / 2;
    const int32_t cropY = (photoHeight - cropSide) / 2;

    try {
        std::vector<int32_t> photoXs(static_cast<size_t>(maskWidth));
        std::vector<int32_t> photoYs(static_cast<size_t>(maskHeight));
        for (int32_t x = 0; x < maskWidth; ++x) {
            const int32_t column = x / cellWidth;
            const double localU = static_cast<double>(x % cellWidth) / static_cast<double>(cellWidth);
            const double sourceGridX = static_cast<double>(column) + (localU - 0.25) * 2.0;
            const double sourceX = std::clamp(sourceGridX / static_cast<double>(columns), 0.0, 1.0);
            photoXs[static_cast<size_t>(x)] = cropX + std::clamp(
                static_cast<int32_t>(std::floor(sourceX * static_cast<double>(cropSide))),
                0,
                cropSide - 1
            );
        }
        for (int32_t y = 0; y < maskHeight; ++y) {
            const int32_t row = y / cellHeight;
            const double localV = static_cast<double>(y % cellHeight) / static_cast<double>(cellHeight);
            const double sourceGridY = static_cast<double>(row) + (localV - 0.25) * 2.0;
            const double sourceY = std::clamp(sourceGridY / static_cast<double>(rows), 0.0, 1.0);
            photoYs[static_cast<size_t>(y)] = cropY + std::clamp(
                static_cast<int32_t>(std::floor(sourceY * static_cast<double>(cropSide))),
                0,
                cropSide - 1
            );
        }

        auto output = std::make_shared<std::vector<uint8_t>>(maskPixelCount * 4u);
        for (int32_t y = 0; y < maskHeight; ++y) {
            const size_t photoRow = static_cast<size_t>(photoYs[static_cast<size_t>(y)]) *
                static_cast<size_t>(photoWidth);
            const size_t maskRow = static_cast<size_t>(y) * static_cast<size_t>(maskWidth);
            for (int32_t x = 0; x < maskWidth; ++x) {
                const size_t photoOffset = (photoRow + static_cast<size_t>(photoXs[static_cast<size_t>(x)])) * 4u;
                const size_t outputOffset = (maskRow + static_cast<size_t>(x)) * 4u;
                (*output)[outputOffset] = (*photo)[photoOffset];
                (*output)[outputOffset + 1u] = (*photo)[photoOffset + 1u];
                (*output)[outputOffset + 2u] = (*photo)[photoOffset + 2u];
                (*output)[outputOffset + 3u] = std::max(
                    (*mask)[outputOffset],
                    std::max((*mask)[outputOffset + 1u], (*mask)[outputOffset + 2u])
                );
            }
        }
        return doof::Result<std::shared_ptr<std::vector<uint8_t>>, std::string>::success(output);
    } catch (const std::bad_alloc&) {
        return doof::Result<std::shared_ptr<std::vector<uint8_t>>, std::string>::failure(
            "Not enough memory to compose the jigsaw atlas"
        );
    }
}

}  // namespace doof_game_jigsaw
