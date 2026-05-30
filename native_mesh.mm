#include "native_mesh.hpp"

#import <Metal/Metal.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace doof_game {

namespace {

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

struct SimpleMeshUniforms {
    float row0[4];
    float row1[4];
    float row2[4];
    float row3[4];
};

id<MTLRenderPipelineState> simpleMeshPipeline(id<MTLDevice> device, int32_t blendMode, bool hasDepthAttachment, bool textured) {
    if (device == nil) {
        return nil;
    }

    static id<MTLRenderPipelineState> pipelines[8] = {};
    static bool attempted[8] = {};

    int32_t slot = (textured ? 4 : 0) + (blendMode == 1 ? 2 : 0) + (hasDepthAttachment ? 1 : 0);
    if (pipelines[slot] != nil) {
        return pipelines[slot];
    }
    if (attempted[slot]) {
        return nil;
    }
    attempted[slot] = true;

    NSString* source =
        @"#include <metal_stdlib>\n"
        @"using namespace metal;\n"
        @"struct VertexIn { packed_float4 position; packed_float4 color; packed_float2 uv; packed_float4 normal; };\n"
        @"struct Uniforms { float4 row0; float4 row1; float4 row2; float4 row3; };\n"
        @"struct VertexOut { float4 position [[position]]; float4 color; float2 uv; float3 normal; };\n"
        @"vertex VertexOut doof_game_simple_mesh_vertex(const device VertexIn* vertices [[buffer(0)]], constant Uniforms& uniforms [[buffer(1)]], const device uint* indices [[buffer(2)]], uint vertexId [[vertex_id]]) {\n"
        @"  VertexIn meshVertex = vertices[indices[vertexId]];\n"
        @"  float4 p = meshVertex.position;\n"
        @"  VertexOut out;\n"
        @"  out.position = float4(dot(uniforms.row0, p), dot(uniforms.row1, p), dot(uniforms.row2, p), dot(uniforms.row3, p));\n"
        @"  out.color = meshVertex.color;\n"
        @"  out.uv = meshVertex.uv;\n"
        @"  out.normal = meshVertex.normal.xyz;\n"
        @"  return out;\n"
        @"}\n"
        @"float4 doof_game_apply_simple_mesh_light(float4 base, float3 normal) {\n"
        @"  float len = max(length(normal), 0.0001);\n"
        @"  float3 n = normal / len;\n"
        @"  float3 light = normalize(float3(0.35, 0.60, 0.72));\n"
        @"  float amount = 0.25 + 0.75 * max(dot(n, light), 0.0);\n"
        @"  return float4(base.rgb * amount, base.a);\n"
        @"}\n"
        @"fragment float4 doof_game_simple_mesh_fragment(VertexOut in [[stage_in]]) {\n"
        @"  return doof_game_apply_simple_mesh_light(in.color, in.normal);\n"
        @"}\n"
        @"fragment float4 doof_game_textured_simple_mesh_fragment(VertexOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler textureSampler [[sampler(0)]]) {\n"
        @"  return doof_game_apply_simple_mesh_light(tex.sample(textureSampler, in.uv) * in.color, in.normal);\n"
        @"}\n";

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) {
        return nil;
    }

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"doof_game_simple_mesh_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:(textured ? @"doof_game_textured_simple_mesh_fragment" : @"doof_game_simple_mesh_fragment")];
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

    pipelines[slot] = pipeline;
    return pipelines[slot];
}

id<MTLSamplerState> simpleMeshSampler(id<MTLDevice> device) {
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

void drawSimpleMeshInternal(
    std::shared_ptr<NativeSimpleMesh> mesh,
    int64_t metalTextureHandle,
    bool textured,
    int64_t metalRenderCommandEncoderHandle,
    int64_t metalDeviceHandle,
    int32_t blendMode,
    bool hasDepthAttachment,
    const SimpleMeshUniforms& uniforms
) {
    if (!mesh || mesh->indexCount() <= 0) {
        return;
    }

    id<MTLTexture> texture = (__bridge id<MTLTexture>)reinterpret_cast<void*>(metalTextureHandle);
    id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)reinterpret_cast<void*>(metalRenderCommandEncoderHandle);
    id<MTLDevice> device = (__bridge id<MTLDevice>)reinterpret_cast<void*>(metalDeviceHandle);
    id<MTLBuffer> vertexBuffer = (__bridge id<MTLBuffer>)reinterpret_cast<void*>(mesh->metalVertexBufferHandle());
    id<MTLBuffer> indexBuffer = (__bridge id<MTLBuffer>)reinterpret_cast<void*>(mesh->metalIndexBufferHandle());
    if (encoder == nil || device == nil || vertexBuffer == nil || indexBuffer == nil) {
        return;
    }

    id<MTLRenderPipelineState> pipeline = simpleMeshPipeline(device, blendMode, hasDepthAttachment, textured);
    if (pipeline == nil) {
        return;
    }

    if (textured) {
        id<MTLSamplerState> sampler = simpleMeshSampler(device);
        if (texture == nil || sampler == nil) {
            return;
        }
        [encoder setFragmentTexture:texture atIndex:0];
        [encoder setFragmentSamplerState:sampler atIndex:0];
    }

    [encoder setRenderPipelineState:pipeline];
    [encoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder setVertexBuffer:indexBuffer offset:0 atIndex:2];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:static_cast<NSUInteger>(mesh->indexCount())];
}

SimpleMeshUniforms makeSimpleMeshUniforms(
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
    return SimpleMeshUniforms {
        { static_cast<float>(m00), static_cast<float>(m01), static_cast<float>(m02), static_cast<float>(m03) },
        { static_cast<float>(m10), static_cast<float>(m11), static_cast<float>(m12), static_cast<float>(m13) },
        { static_cast<float>(m20), static_cast<float>(m21), static_cast<float>(m22), static_cast<float>(m23) },
        { static_cast<float>(m30), static_cast<float>(m31), static_cast<float>(m32), static_cast<float>(m33) },
    };
}

}  // namespace

struct NativeSimpleMesh::Impl {
    id<MTLDevice> device = nil;
    id<MTLBuffer> vertexBuffer = nil;
    id<MTLBuffer> indexBuffer = nil;
    int32_t vertexCount = 0;
    int32_t indexCount = 0;

    Impl(void* rawDevice, void* rawVertexBuffer, void* rawIndexBuffer, int32_t vertexCount, int32_t indexCount)
        : device((__bridge id<MTLDevice>)rawDevice),
          vertexBuffer((__bridge id<MTLBuffer>)rawVertexBuffer),
          indexBuffer((__bridge id<MTLBuffer>)rawIndexBuffer),
          vertexCount(vertexCount),
          indexCount(indexCount) {
        [device retain];
        [vertexBuffer retain];
        [indexBuffer retain];
    }

    ~Impl() {
        [indexBuffer release];
        [vertexBuffer release];
        [device release];
    }
};

struct NativeSimpleMeshBuilder::Impl {
    std::vector<SimpleMeshVertex> vertices;
    std::vector<uint32_t> indices;
};

NativeSimpleMesh::NativeSimpleMesh(void* device, void* vertexBuffer, void* indexBuffer, int32_t vertexCount, int32_t indexCount)
    : impl_(std::make_shared<Impl>(device, vertexBuffer, indexBuffer, vertexCount, indexCount)) {}

NativeSimpleMesh::~NativeSimpleMesh() = default;

int32_t NativeSimpleMesh::vertexCount() const {
    return impl_->vertexCount;
}

int32_t NativeSimpleMesh::indexCount() const {
    return impl_->indexCount;
}

int64_t NativeSimpleMesh::metalDeviceHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->device);
}

int64_t NativeSimpleMesh::metalVertexBufferHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->vertexBuffer);
}

int64_t NativeSimpleMesh::metalIndexBufferHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->indexBuffer);
}

std::shared_ptr<NativeSimpleMeshBuilder> NativeSimpleMeshBuilder::create() {
    return std::make_shared<NativeSimpleMeshBuilder>();
}

NativeSimpleMeshBuilder::NativeSimpleMeshBuilder()
    : impl_(std::make_shared<Impl>()) {}

NativeSimpleMeshBuilder::~NativeSimpleMeshBuilder() = default;

int32_t NativeSimpleMeshBuilder::addVertex(
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
) {
    impl_->vertices.push_back(SimpleMeshVertex {
        static_cast<float>(x),
        static_cast<float>(y),
        static_cast<float>(z),
        1.0f,
        static_cast<float>(red),
        static_cast<float>(green),
        static_cast<float>(blue),
        static_cast<float>(alpha),
        static_cast<float>(u),
        static_cast<float>(v),
        static_cast<float>(normalX),
        static_cast<float>(normalY),
        static_cast<float>(normalZ),
        0.0f,
    });
    return static_cast<int32_t>(impl_->vertices.size() - 1);
}

std::shared_ptr<NativeSimpleMeshBuilder> NativeSimpleMeshBuilder::addTriangle(int32_t a, int32_t b, int32_t c) {
    impl_->indices.push_back(static_cast<uint32_t>(a));
    impl_->indices.push_back(static_cast<uint32_t>(b));
    impl_->indices.push_back(static_cast<uint32_t>(c));
    return shared_from_this();
}

doof::Result<std::shared_ptr<NativeSimpleMesh>, std::string> NativeSimpleMeshBuilder::build(int64_t metalDeviceHandle) {
    id<MTLDevice> device = (__bridge id<MTLDevice>)reinterpret_cast<void*>(metalDeviceHandle);
    if (device == nil) {
        return doof::Result<std::shared_ptr<NativeSimpleMesh>, std::string>::failure("Metal device handle is invalid");
    }

    if (impl_->vertices.empty()) {
        return doof::Result<std::shared_ptr<NativeSimpleMesh>, std::string>::failure("Simple mesh has no vertices");
    }

    if (impl_->indices.empty()) {
        return doof::Result<std::shared_ptr<NativeSimpleMesh>, std::string>::failure("Simple mesh has no triangles");
    }

    if (impl_->indices.size() % 3 != 0) {
        return doof::Result<std::shared_ptr<NativeSimpleMesh>, std::string>::failure("Simple mesh index count must be divisible by 3");
    }

    for (uint32_t index : impl_->indices) {
        if (index >= impl_->vertices.size()) {
            return doof::Result<std::shared_ptr<NativeSimpleMesh>, std::string>::failure("Simple mesh triangle index is out of range");
        }
    }

    id<MTLBuffer> vertexBuffer = [device newBufferWithBytes:impl_->vertices.data()
                                                     length:impl_->vertices.size() * sizeof(SimpleMeshVertex)
                                                    options:MTLResourceStorageModeShared];
    if (vertexBuffer == nil) {
        return doof::Result<std::shared_ptr<NativeSimpleMesh>, std::string>::failure("Failed to create simple mesh vertex buffer");
    }

    id<MTLBuffer> indexBuffer = [device newBufferWithBytes:impl_->indices.data()
                                                    length:impl_->indices.size() * sizeof(uint32_t)
                                                   options:MTLResourceStorageModeShared];
    if (indexBuffer == nil) {
        [vertexBuffer release];
        return doof::Result<std::shared_ptr<NativeSimpleMesh>, std::string>::failure("Failed to create simple mesh index buffer");
    }

    auto mesh = std::make_shared<NativeSimpleMesh>(
        (__bridge void*)device,
        (__bridge void*)vertexBuffer,
        (__bridge void*)indexBuffer,
        static_cast<int32_t>(impl_->vertices.size()),
        static_cast<int32_t>(impl_->indices.size())
    );

    [indexBuffer release];
    [vertexBuffer release];

    return doof::Result<std::shared_ptr<NativeSimpleMesh>, std::string>::success(mesh);
}

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
) {
    drawSimpleMeshInternal(
        mesh,
        0,
        false,
        metalRenderCommandEncoderHandle,
        metalDeviceHandle,
        blendMode,
        hasDepthAttachment,
        makeSimpleMeshUniforms(m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33)
    );
}

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
) {
    drawSimpleMeshInternal(
        mesh,
        metalTextureHandle,
        true,
        metalRenderCommandEncoderHandle,
        metalDeviceHandle,
        blendMode,
        hasDepthAttachment,
        makeSimpleMeshUniforms(m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33)
    );
}

}  // namespace doof_game
