#pragma once

#include "doof_runtime.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace doof_game {

class NativeSimpleMesh {
public:
    NativeSimpleMesh(void* device, void* vertexBuffer, void* indexBuffer, int32_t vertexCount, int32_t indexCount);
    ~NativeSimpleMesh();

    int32_t vertexCount() const;
    int32_t indexCount() const;
    int64_t metalDeviceHandle() const;
    int64_t metalVertexBufferHandle() const;
    int64_t metalIndexBufferHandle() const;

private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};

class NativeSimpleMeshBuilder : public std::enable_shared_from_this<NativeSimpleMeshBuilder> {
public:
    static std::shared_ptr<NativeSimpleMeshBuilder> create();
    NativeSimpleMeshBuilder();
    ~NativeSimpleMeshBuilder();

    int32_t addVertex(
        double x,
        double y,
        double z,
        double red,
        double green,
        double blue,
        double alpha,
        double u,
        double v,
        double normalX,
        double normalY,
        double normalZ
    );
    std::shared_ptr<NativeSimpleMeshBuilder> addTriangle(int32_t a, int32_t b, int32_t c);
    doof::Result<std::shared_ptr<NativeSimpleMesh>, std::string> build(int64_t metalDeviceHandle);

private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};

void drawNativeSimpleMesh(
    std::shared_ptr<NativeSimpleMesh> mesh,
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

void drawNativeTexturedSimpleMesh(
    std::shared_ptr<NativeSimpleMesh> mesh,
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

void drawNativeEquirectangularSkyMap(
    int64_t metalTextureHandle,
    int64_t metalRenderCommandEncoderHandle,
    int64_t metalDeviceHandle,
    bool hasDepthAttachment,
    int32_t pixelWidth,
    int32_t pixelHeight,
    double yawRadians,
    double pitchRadians,
    double fovYRadians,
    double exposure
);

}  // namespace doof_game
