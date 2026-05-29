#pragma once

#include "doof_runtime.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace doof_game {

class NativeColorMesh {
public:
    NativeColorMesh(void* device, void* vertexBuffer, void* indexBuffer, int32_t vertexCount, int32_t indexCount);
    ~NativeColorMesh();

    int32_t vertexCount() const;
    int32_t indexCount() const;
    int64_t metalDeviceHandle() const;
    int64_t metalVertexBufferHandle() const;
    int64_t metalIndexBufferHandle() const;

private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};

class NativeColorMeshBuilder : public std::enable_shared_from_this<NativeColorMeshBuilder> {
public:
    static std::shared_ptr<NativeColorMeshBuilder> create();
    NativeColorMeshBuilder();
    ~NativeColorMeshBuilder();

    int32_t addVertex(double x, double y, double z, double red, double green, double blue, double alpha);
    std::shared_ptr<NativeColorMeshBuilder> addTriangle(int32_t a, int32_t b, int32_t c);
    doof::Result<std::shared_ptr<NativeColorMesh>, std::string> build(int64_t metalDeviceHandle);

private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};

void drawNativeColorMesh(
    std::shared_ptr<NativeColorMesh> mesh,
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
