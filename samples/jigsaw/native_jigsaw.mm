#include "native_jigsaw.hpp"

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <sys/stat.h>
#include <vector>

namespace doof_game_jigsaw {
namespace {

struct ImageData {
    int32_t width = 0;
    int32_t height = 0;
    std::vector<uint8_t> rgba;
};

bool fileMTime(const std::string& path, time_t& out) {
    struct stat info;
    if (stat(path.c_str(), &info) != 0) {
        return false;
    }
    out = info.st_mtime;
    return true;
}

bool outputIsFresh(
    const std::string& photoPath,
    const std::string& maskAtlasPath,
    const std::string& outputPath
) {
    time_t photoTime = 0;
    time_t maskTime = 0;
    time_t outputTime = 0;
    if (!fileMTime(photoPath, photoTime) || !fileMTime(maskAtlasPath, maskTime) || !fileMTime(outputPath, outputTime)) {
        return false;
    }
    return outputTime >= photoTime && outputTime >= maskTime;
}

NSString* nsString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

std::string nsError(NSError* error, const std::string& fallback) {
    if (error == nil) {
        return fallback;
    }
    NSString* description = [error localizedDescription];
    if (description == nil) {
        return fallback;
    }
    return std::string([description UTF8String]);
}

doof::Result<ImageData, std::string> loadRgbaImage(const std::string& path) {
    NSURL* url = [NSURL fileURLWithPath:nsString(path)];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
    if (source == nullptr) {
        return doof::Result<ImageData, std::string>::failure("Failed to open image: " + path);
    }

    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
    CFRelease(source);
    if (image == nullptr) {
        return doof::Result<ImageData, std::string>::failure("Failed to decode image: " + path);
    }

    const size_t width = CGImageGetWidth(image);
    const size_t height = CGImageGetHeight(image);
    if (width == 0 || height == 0) {
        CGImageRelease(image);
        return doof::Result<ImageData, std::string>::failure("Image is empty: " + path);
    }

    ImageData data;
    data.width = static_cast<int32_t>(width);
    data.height = static_cast<int32_t>(height);
    data.rgba.resize(width * height * 4);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        data.rgba.data(),
        width,
        height,
        8,
        width * 4,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(colorSpace);
    if (context == nullptr) {
        CGImageRelease(image);
        return doof::Result<ImageData, std::string>::failure("Failed to create decode context: " + path);
    }

    CGContextDrawImage(context, CGRectMake(0, 0, static_cast<CGFloat>(width), static_cast<CGFloat>(height)), image);
    CGContextRelease(context);
    CGImageRelease(image);

    return doof::Result<ImageData, std::string>::success(data);
}

uint8_t sampleMask(const ImageData& mask, int32_t x, int32_t y) {
    x = std::clamp(x, 0, mask.width - 1);
    y = std::clamp(y, 0, mask.height - 1);
    const size_t offset = (static_cast<size_t>(y) * mask.width + x) * 4;
    return std::max(mask.rgba[offset], std::max(mask.rgba[offset + 1], mask.rgba[offset + 2]));
}

void samplePhoto(const ImageData& photo, double nx, double ny, uint8_t* out) {
    const int32_t cropSide = std::min(photo.width, photo.height);
    const int32_t cropX = (photo.width - cropSide) / 2;
    const int32_t cropY = (photo.height - cropSide) / 2;
    const double clampedX = std::clamp(nx, 0.0, 1.0);
    const double clampedY = std::clamp(ny, 0.0, 1.0);
    const int32_t x = cropX + std::clamp(static_cast<int32_t>(std::floor(clampedX * static_cast<double>(cropSide))), 0, cropSide - 1);
    const int32_t y = cropY + std::clamp(static_cast<int32_t>(std::floor(clampedY * static_cast<double>(cropSide))), 0, cropSide - 1);
    const size_t offset = (static_cast<size_t>(y) * photo.width + x) * 4;
    out[0] = photo.rgba[offset];
    out[1] = photo.rgba[offset + 1];
    out[2] = photo.rgba[offset + 2];
    out[3] = photo.rgba[offset + 3];
}

doof::Result<void, std::string> writePng(const std::string& outputPath, int32_t width, int32_t height, const std::vector<uint8_t>& rgba) {
    NSString* outputNsPath = nsString(outputPath);
    NSString* directory = [outputNsPath stringByDeletingLastPathComponent];
    NSError* error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        return doof::Result<void, std::string>::failure("Failed to create output directory: " + nsError(error, outputPath));
    }

    CGDataProviderRef provider = CGDataProviderCreateWithData(nullptr, rgba.data(), rgba.size(), nullptr);
    if (provider == nullptr) {
        return doof::Result<void, std::string>::failure("Failed to create PNG data provider");
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(
        static_cast<size_t>(width),
        static_cast<size_t>(height),
        8,
        32,
        static_cast<size_t>(width) * 4,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
        provider,
        nullptr,
        false,
        kCGRenderingIntentDefault
    );
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    if (image == nullptr) {
        return doof::Result<void, std::string>::failure("Failed to create output image");
    }

    NSURL* outputUrl = [NSURL fileURLWithPath:outputNsPath];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)outputUrl, CFSTR("public.png"), 1, nullptr);
    if (destination == nullptr) {
        CGImageRelease(image);
        return doof::Result<void, std::string>::failure("Failed to create PNG destination: " + outputPath);
    }

    CGImageDestinationAddImage(destination, image, nullptr);
    const bool ok = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CGImageRelease(image);

    if (!ok) {
        return doof::Result<void, std::string>::failure("Failed to write PNG: " + outputPath);
    }

    return doof::Result<void, std::string>::success();
}

}  // namespace

doof::Result<void, std::string> buildJigsawAtlas(
    const std::string& photoPath,
    const std::string& maskAtlasPath,
    const std::string& outputPath,
    int32_t columns,
    int32_t rows
) {
    if (columns <= 0 || rows <= 0) {
        return doof::Result<void, std::string>::failure("Jigsaw atlas dimensions must be positive");
    }

    if (outputIsFresh(photoPath, maskAtlasPath, outputPath)) {
        return doof::Result<void, std::string>::success();
    }

    auto photoResult = loadRgbaImage(photoPath);
    if (photoResult.isFailure()) {
        return doof::Result<void, std::string>::failure(photoResult.error());
    }
    auto maskResult = loadRgbaImage(maskAtlasPath);
    if (maskResult.isFailure()) {
        return doof::Result<void, std::string>::failure(maskResult.error());
    }

    const ImageData& photo = photoResult.value();
    const ImageData& mask = maskResult.value();
    if (mask.width % columns != 0 || mask.height % rows != 0) {
        return doof::Result<void, std::string>::failure("Mask atlas size is not divisible by requested grid");
    }

    const int32_t cellWidth = mask.width / columns;
    const int32_t cellHeight = mask.height / rows;
    if (cellWidth <= 0 || cellHeight <= 0) {
        return doof::Result<void, std::string>::failure("Mask atlas cells are empty");
    }

    std::vector<uint8_t> output(static_cast<size_t>(mask.width) * mask.height * 4, 0);
    for (int32_t y = 0; y < mask.height; ++y) {
        const int32_t row = y / cellHeight;
        const int32_t localY = y % cellHeight;
        const double localV = static_cast<double>(localY) / static_cast<double>(cellHeight);
        const double sourceGridY = static_cast<double>(row) + (localV - 0.25) * 2.0;
        const double sourceY = sourceGridY / static_cast<double>(rows);

        for (int32_t x = 0; x < mask.width; ++x) {
            const int32_t column = x / cellWidth;
            const int32_t localX = x % cellWidth;
            const double localU = static_cast<double>(localX) / static_cast<double>(cellWidth);
            const double sourceGridX = static_cast<double>(column) + (localU - 0.25) * 2.0;
            const double sourceX = sourceGridX / static_cast<double>(columns);

            const size_t offset = (static_cast<size_t>(y) * mask.width + x) * 4;
            samplePhoto(photo, sourceX, sourceY, &output[offset]);
            output[offset + 3] = sampleMask(mask, x, y);
        }
    }

    return writePng(outputPath, mask.width, mask.height, output);
}

}  // namespace doof_game_jigsaw
