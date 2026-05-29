#include "native_sprite.hpp"

#import <Metal/Metal.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace doof_game {

namespace {

struct TextureQuadInstance {
    float x;
    float y;
    float width;
    float height;
    float u0;
    float v0;
    float u1;
    float v1;
    float r;
    float g;
    float b;
    float a;
};

struct TextureQuadUniforms {
    float row0[4];
    float row1[4];
    float row2[4];
    float row3[4];
};

id<MTLRenderPipelineState> textureQuadBatchPipeline(id<MTLDevice> device, int32_t blendMode, bool hasDepthAttachment) {
    if (device == nil) {
        return nil;
    }

    static id<MTLRenderPipelineState> opaqueNoDepth = nil;
    static id<MTLRenderPipelineState> alphaNoDepth = nil;
    static id<MTLRenderPipelineState> opaqueDepth = nil;
    static id<MTLRenderPipelineState> alphaDepth = nil;
    static bool opaqueNoDepthAttempted = false;
    static bool alphaNoDepthAttempted = false;
    static bool opaqueDepthAttempted = false;
    static bool alphaDepthAttempted = false;

    id<MTLRenderPipelineState>* slot = nullptr;
    bool* attempted = nullptr;
    if (blendMode == 1 && hasDepthAttachment) {
        slot = &alphaDepth;
        attempted = &alphaDepthAttempted;
    } else if (blendMode == 1) {
        slot = &alphaNoDepth;
        attempted = &alphaNoDepthAttempted;
    } else if (hasDepthAttachment) {
        slot = &opaqueDepth;
        attempted = &opaqueDepthAttempted;
    } else {
        slot = &opaqueNoDepth;
        attempted = &opaqueNoDepthAttempted;
    }

    if (*slot != nil) {
        return *slot;
    }
    if (*attempted) {
        return nil;
    }
    *attempted = true;

    NSString* source =
        @"#include <metal_stdlib>\n"
        @"using namespace metal;\n"
        @"struct Instance { float4 rect; float4 uv; float4 tint; };\n"
        @"struct Uniforms { float4 row0; float4 row1; float4 row2; float4 row3; };\n"
        @"struct VertexOut { float4 position [[position]]; float2 uv; float4 tint; };\n"
        @"vertex VertexOut doof_game_texture_quad_batch_vertex(const device Instance* instances [[buffer(0)]], constant Uniforms& uniforms [[buffer(1)]], uint vertexId [[vertex_id]], uint instanceId [[instance_id]]) {\n"
        @"  uint cornerId = vertexId;\n"
        @"  Instance inst = instances[instanceId];\n"
        @"  float cornerX = (cornerId == 1 || cornerId == 3 || cornerId == 4) ? 1.0 : 0.0;\n"
        @"  float cornerY = (cornerId == 2 || cornerId == 4 || cornerId == 5) ? 1.0 : 0.0;\n"
        @"  float2 corner = float2(cornerX, cornerY);\n"
        @"  float4 p = float4(inst.rect.x + corner.x * inst.rect.z, inst.rect.y + corner.y * inst.rect.w, 0.0, 1.0);\n"
        @"  VertexOut out;\n"
        @"  out.position = float4(dot(uniforms.row0, p), dot(uniforms.row1, p), dot(uniforms.row2, p), dot(uniforms.row3, p));\n"
        @"  out.uv = float2(mix(inst.uv.x, inst.uv.z, corner.x), mix(inst.uv.y, inst.uv.w, corner.y));\n"
        @"  out.tint = inst.tint;\n"
        @"  return out;\n"
        @"}\n"
        @"fragment float4 doof_game_texture_quad_batch_fragment(VertexOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler textureSampler [[sampler(0)]]) {\n"
        @"  return tex.sample(textureSampler, in.uv) * in.tint;\n"
        @"}\n";

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) {
        return nil;
    }

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"doof_game_texture_quad_batch_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"doof_game_texture_quad_batch_fragment"];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    if (hasDepthAttachment) {
        descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    }

    if (blendMode == 1) {
        descriptor.colorAttachments[0].blendingEnabled = YES;
        descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    }

    id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    [descriptor.vertexFunction release];
    [descriptor.fragmentFunction release];
    [descriptor release];
    [library release];
    if (pipeline == nil) {
        return nil;
    }

    *slot = pipeline;
    return *slot;
}

id<MTLSamplerState> textureQuadBatchSampler(id<MTLDevice> device) {
    static id<MTLSamplerState> sampler = nil;
    if (sampler != nil || device == nil) {
        return sampler;
    }

    MTLSamplerDescriptor* descriptor = [[MTLSamplerDescriptor alloc] init];
    descriptor.minFilter = MTLSamplerMinMagFilterLinear;
    descriptor.magFilter = MTLSamplerMinMagFilterLinear;
    descriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
    descriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
    sampler = [device newSamplerStateWithDescriptor:descriptor];
    [descriptor release];
    return sampler;
}

}  // namespace

struct NativeTextureQuadBatch::Impl {
    id<MTLDevice> device = nil;
    id<MTLBuffer> instanceBuffer = nil;
    int32_t quadCount = 0;

    Impl(void* rawDevice, void* rawInstanceBuffer, int32_t quadCount)
        : device((__bridge id<MTLDevice>)rawDevice),
          instanceBuffer((__bridge id<MTLBuffer>)rawInstanceBuffer),
          quadCount(quadCount) {
        [device retain];
        [instanceBuffer retain];
    }

    ~Impl() {
        [instanceBuffer release];
        [device release];
    }
};

struct NativeTextureQuadBatchBuilder::Impl {
    std::vector<TextureQuadInstance> instances;
};

NativeTextureQuadBatch::NativeTextureQuadBatch(void* device, void* instanceBuffer, int32_t quadCount)
    : impl_(std::make_shared<Impl>(device, instanceBuffer, quadCount)) {}

NativeTextureQuadBatch::~NativeTextureQuadBatch() = default;

int32_t NativeTextureQuadBatch::quadCount() const {
    return impl_->quadCount;
}

int64_t NativeTextureQuadBatch::metalInstanceBufferHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->instanceBuffer);
}

std::shared_ptr<NativeTextureQuadBatchBuilder> NativeTextureQuadBatchBuilder::create() {
    return std::make_shared<NativeTextureQuadBatchBuilder>();
}

NativeTextureQuadBatchBuilder::NativeTextureQuadBatchBuilder()
    : impl_(std::make_shared<Impl>()) {}

NativeTextureQuadBatchBuilder::~NativeTextureQuadBatchBuilder() = default;

std::shared_ptr<NativeTextureQuadBatchBuilder> NativeTextureQuadBatchBuilder::addQuad(
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
) {
    impl_->instances.push_back(TextureQuadInstance {
        static_cast<float>(x),
        static_cast<float>(y),
        static_cast<float>(width),
        static_cast<float>(height),
        static_cast<float>(u0),
        static_cast<float>(v0),
        static_cast<float>(u1),
        static_cast<float>(v1),
        static_cast<float>(red),
        static_cast<float>(green),
        static_cast<float>(blue),
        static_cast<float>(alpha),
    });
    return shared_from_this();
}

doof::Result<std::shared_ptr<NativeTextureQuadBatch>, std::string> NativeTextureQuadBatchBuilder::build(int64_t metalDeviceHandle) {
    id<MTLDevice> device = (__bridge id<MTLDevice>)reinterpret_cast<void*>(metalDeviceHandle);
    if (device == nil) {
        return doof::Result<std::shared_ptr<NativeTextureQuadBatch>, std::string>::failure("Metal device handle is invalid");
    }

    if (impl_->instances.empty()) {
        return doof::Result<std::shared_ptr<NativeTextureQuadBatch>, std::string>::failure("Texture quad batch has no quads");
    }

    id<MTLBuffer> instanceBuffer = [device newBufferWithBytes:impl_->instances.data()
                                                       length:impl_->instances.size() * sizeof(TextureQuadInstance)
                                                      options:MTLResourceStorageModeShared];
    if (instanceBuffer == nil) {
        return doof::Result<std::shared_ptr<NativeTextureQuadBatch>, std::string>::failure("Failed to create texture quad instance buffer");
    }

    auto batch = std::make_shared<NativeTextureQuadBatch>(
        (__bridge void*)device,
        (__bridge void*)instanceBuffer,
        static_cast<int32_t>(impl_->instances.size())
    );

    [instanceBuffer release];

    return doof::Result<std::shared_ptr<NativeTextureQuadBatch>, std::string>::success(batch);
}

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
) {
    if (!batch || batch->quadCount() <= 0) {
        return;
    }

    id<MTLTexture> texture = (__bridge id<MTLTexture>)reinterpret_cast<void*>(metalTextureHandle);
    id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)reinterpret_cast<void*>(metalRenderCommandEncoderHandle);
    id<MTLDevice> device = (__bridge id<MTLDevice>)reinterpret_cast<void*>(metalDeviceHandle);
    id<MTLBuffer> instanceBuffer = (__bridge id<MTLBuffer>)reinterpret_cast<void*>(batch->metalInstanceBufferHandle());
    if (texture == nil || encoder == nil || device == nil || instanceBuffer == nil) {
        return;
    }

    id<MTLRenderPipelineState> pipeline = textureQuadBatchPipeline(device, blendMode, hasDepthAttachment);
    id<MTLSamplerState> sampler = textureQuadBatchSampler(device);
    if (pipeline == nil || sampler == nil) {
        return;
    }

    TextureQuadUniforms uniforms = {
        { static_cast<float>(m00), static_cast<float>(m01), static_cast<float>(m02), static_cast<float>(m03) },
        { static_cast<float>(m10), static_cast<float>(m11), static_cast<float>(m12), static_cast<float>(m13) },
        { static_cast<float>(m20), static_cast<float>(m21), static_cast<float>(m22), static_cast<float>(m23) },
        { static_cast<float>(m30), static_cast<float>(m31), static_cast<float>(m32), static_cast<float>(m33) },
    };

    [encoder setRenderPipelineState:pipeline];
    [encoder setVertexBuffer:instanceBuffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder setFragmentTexture:texture atIndex:0];
    [encoder setFragmentSamplerState:sampler atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6
              instanceCount:static_cast<NSUInteger>(batch->quadCount())];
}

}  // namespace doof_game
