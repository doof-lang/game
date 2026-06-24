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

class NativeSimpleModelBatch {
public:
    static doof::Result<std::shared_ptr<NativeSimpleModelBatch>, std::string> create(int64_t metalDeviceHandle, int32_t capacity);
    NativeSimpleModelBatch(void* device, void* instanceBuffer, int32_t capacity);
    ~NativeSimpleModelBatch();

    int32_t capacity() const;
    int32_t count() const;
    void setCount(int32_t count);
    void setInstance(
        int32_t slot,
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
        double m33,
        double red,
        double green,
        double blue,
        double alpha,
        double whiteBlend,
        double uvOffsetX,
        double uvOffsetY,
        double uvScaleX,
        double uvScaleY
    );
    int64_t metalInstanceBufferHandle() const;

private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};

class NativeSpaceDust {
public:
    NativeSpaceDust(void* device, void* particleBuffer, int32_t particleCount);
    ~NativeSpaceDust();

    int32_t particleCount() const;
    int64_t metalDeviceHandle() const;
    int64_t metalParticleBufferHandle() const;

private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};

class NativeSpaceDustBuilder : public std::enable_shared_from_this<NativeSpaceDustBuilder> {
public:
    static std::shared_ptr<NativeSpaceDustBuilder> create();
    NativeSpaceDustBuilder();
    ~NativeSpaceDustBuilder();

    std::shared_ptr<NativeSpaceDustBuilder> addParticle(double x, double y, double z, double brightness);
    doof::Result<std::shared_ptr<NativeSpaceDust>, std::string> build(int64_t metalDeviceHandle);

private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};

class NativeShaderBuffer {
public:
    static doof::Result<std::shared_ptr<NativeShaderBuffer>, std::string> create(
        int64_t metalDeviceHandle,
        const std::shared_ptr<std::vector<uint8_t>>& data
    );
    NativeShaderBuffer(void* device, void* buffer, int32_t byteLength);
    ~NativeShaderBuffer();

    int32_t byteLength() const;
    int64_t metalBufferHandle() const;

private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};

class NativeShaderPipeline {
public:
    static doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string> create(
        int64_t metalDeviceHandle,
        const std::string& source,
        const std::string& vertexFunction,
        const std::string& fragmentFunction,
        const std::shared_ptr<std::vector<int32_t>>& attributeIndices,
        const std::shared_ptr<std::vector<int32_t>>& attributeBuffers,
        const std::shared_ptr<std::vector<int32_t>>& attributeOffsets,
        const std::shared_ptr<std::vector<int32_t>>& attributeFormats,
        const std::shared_ptr<std::vector<int32_t>>& layoutBuffers,
        const std::shared_ptr<std::vector<int32_t>>& layoutStrides,
        const std::shared_ptr<std::vector<int32_t>>& layoutStepFunctions,
        const std::shared_ptr<std::vector<int32_t>>& layoutStepRates
    );
    NativeShaderPipeline(
        void* device,
        void* library,
        void* vertexDescriptor,
        std::string vertexFunction,
        std::string fragmentFunction
    );
    ~NativeShaderPipeline();

    doof::Result<int64_t, std::string> metalPipelineHandle(int32_t blendMode, bool hasDepthAttachment);

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

void drawNativeSimpleModelBatch(
    std::shared_ptr<NativeSimpleMesh> mesh,
    std::shared_ptr<NativeSimpleModelBatch> batch,
    int64_t metalTextureHandle,
    bool textured,
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
    double fovYRadians,
    double exposure,
    double rotationM00,
    double rotationM01,
    double rotationM02,
    double rotationM10,
    double rotationM11,
    double rotationM12,
    double rotationM20,
    double rotationM21,
    double rotationM22
);

void drawNativeSpaceDust(
    std::shared_ptr<NativeSpaceDust> dust,
    int64_t metalRenderCommandEncoderHandle,
    int64_t metalDeviceHandle,
    bool hasDepthAttachment,
    int32_t pixelWidth,
    int32_t pixelHeight,
    double cameraX,
    double cameraY,
    double cameraZ,
    double fieldSize,
    double particleSize,
    double fadeStart,
    double fadeEnd,
    double opacity,
    double red,
    double green,
    double blue,
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

doof::Result<void, std::string> drawNativeShader(
    std::shared_ptr<NativeShaderPipeline> pipeline,
    const std::shared_ptr<std::vector<int32_t>>& vertexBufferIndices,
    const std::shared_ptr<std::vector<int64_t>>& vertexBufferHandles,
    const std::shared_ptr<std::vector<int32_t>>& vertexBufferOffsets,
    const std::shared_ptr<std::vector<int32_t>>& vertexBytesIndices,
    const std::shared_ptr<std::vector<int64_t>>& vertexBytesHandles,
    const std::shared_ptr<std::vector<int32_t>>& vertexBytesOffsets,
    const std::shared_ptr<std::vector<int32_t>>& fragmentBytesIndices,
    const std::shared_ptr<std::vector<int64_t>>& fragmentBytesHandles,
    const std::shared_ptr<std::vector<int32_t>>& fragmentBytesOffsets,
    const std::shared_ptr<std::vector<int32_t>>& fragmentTextureIndices,
    const std::shared_ptr<std::vector<int64_t>>& fragmentTextureHandles,
    int64_t indexBufferHandle,
    int32_t indexCount,
    int32_t vertexCount,
    int32_t instanceCount,
    int64_t metalRenderCommandEncoderHandle,
    int32_t blendMode,
    bool hasDepthAttachment
);

}  // namespace doof_game
