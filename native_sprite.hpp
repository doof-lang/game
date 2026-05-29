#pragma once

#include "doof_runtime.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace doof_game {

class NativeTextureQuadBatch {
public:
    NativeTextureQuadBatch(void* device, void* instanceBuffer, int32_t quadCount);
    ~NativeTextureQuadBatch();

    int32_t quadCount() const;
    int64_t metalInstanceBufferHandle() const;

private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};

class NativeTextureQuadBatchBuilder : public std::enable_shared_from_this<NativeTextureQuadBatchBuilder> {
public:
    static std::shared_ptr<NativeTextureQuadBatchBuilder> create();
    NativeTextureQuadBatchBuilder();
    ~NativeTextureQuadBatchBuilder();

    std::shared_ptr<NativeTextureQuadBatchBuilder> addQuad(
        double x,
        double y,
        double width,
        double height,
        double u0,
        double v0,
        double u1,
        double v1,
        double red,
        double green,
        double blue,
        double alpha
    );
    doof::Result<std::shared_ptr<NativeTextureQuadBatch>, std::string> build(int64_t metalDeviceHandle);

private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};

void drawNativeTextureQuadBatch(
    std::shared_ptr<NativeTextureQuadBatch> batch,
    int64_t metalTextureHandle,
    int64_t metalRenderCommandEncoderHandle,
    int64_t metalDeviceHandle,
    int32_t blendMode,
    bool hasDepthAttachment,
    double m00,
    double m01,
    double m02,
    double m03,
    double m10,
    double m11,
    double m12,
    double m13,
    double m20,
    double m21,
    double m22,
    double m23,
    double m30,
    double m31,
    double m32,
    double m33
);

}  // namespace doof_game
