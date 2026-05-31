#pragma once

#include "native_mesh.hpp"

#import <Metal/Metal.h>

#include <cstdint>

namespace doof_game {
namespace native_mesh {

struct SimpleMeshVertex {
    float x;
    float y;
    float z;
    float w;
    float r;
    float g;
    float b;
    float a;
    float u;
    float v;
    float nx;
    float ny;
    float nz;
    float nw;
};

struct SpaceDustParticle {
    float x;
    float y;
    float z;
    float brightness;
};

struct MatrixUniforms {
    float row0[4];
    float row1[4];
    float row2[4];
    float row3[4];
};

template <typename T>
T bridgeMetalHandle(int64_t handle) {
    return (__bridge T)reinterpret_cast<void*>(handle);
}

template <typename T>
int64_t metalHandle(T object) {
    return reinterpret_cast<int64_t>((__bridge void*)object);
}

inline void configureAlphaBlending(MTLRenderPipelineColorAttachmentDescriptor* attachment) {
    attachment.blendingEnabled = YES;
    attachment.rgbBlendOperation = MTLBlendOperationAdd;
    attachment.alphaBlendOperation = MTLBlendOperationAdd;
    attachment.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    attachment.sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    attachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    attachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
}

inline void configureDepthAttachment(MTLRenderPipelineDescriptor* descriptor, bool hasDepthAttachment) {
    if (hasDepthAttachment) {
        descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    }
}

inline MatrixUniforms makeMatrixUniforms(
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
) {
    return MatrixUniforms {
        { static_cast<float>(m00), static_cast<float>(m01), static_cast<float>(m02), static_cast<float>(m03) },
        { static_cast<float>(m10), static_cast<float>(m11), static_cast<float>(m12), static_cast<float>(m13) },
        { static_cast<float>(m20), static_cast<float>(m21), static_cast<float>(m22), static_cast<float>(m23) },
        { static_cast<float>(m30), static_cast<float>(m31), static_cast<float>(m32), static_cast<float>(m33) },
    };
}

id<MTLSamplerState> linearSampler(id<MTLDevice> device, MTLSamplerAddressMode sAddressMode);

}  // namespace native_mesh
}  // namespace doof_game
