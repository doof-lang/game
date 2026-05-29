#include "native_mesh.hpp"

#import <Metal/Metal.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace doof_game {

namespace {

struct ColorMeshVertex {
    float x;
    float y;
    float z;
    float w;
    float r;
    float g;
    float b;
    float a;
};

struct ColorMeshUniforms {
    float row0[4];
    float row1[4];
    float row2[4];
    float row3[4];
};

id<MTLRenderPipelineState> colorMeshPipeline(id<MTLDevice> device, int32_t blendMode, bool hasDepthAttachment) {
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
        @"struct VertexIn { packed_float4 position; packed_float4 color; };\n"
        @"struct Uniforms { float4 row0; float4 row1; float4 row2; float4 row3; };\n"
        @"struct VertexOut { float4 position [[position]]; float4 color; };\n"
        @"vertex VertexOut doof_game_color_mesh_vertex(const device VertexIn* vertices [[buffer(0)]], constant Uniforms& uniforms [[buffer(1)]], const device uint* indices [[buffer(2)]], uint vertexId [[vertex_id]]) {\n"
        @"  VertexIn meshVertex = vertices[indices[vertexId]];\n"
        @"  float4 p = meshVertex.position;\n"
        @"  VertexOut out;\n"
        @"  out.position = float4(dot(uniforms.row0, p), dot(uniforms.row1, p), dot(uniforms.row2, p), dot(uniforms.row3, p));\n"
        @"  out.color = meshVertex.color;\n"
        @"  return out;\n"
        @"}\n"
        @"fragment float4 doof_game_color_mesh_fragment(VertexOut in [[stage_in]]) {\n"
        @"  return in.color;\n"
        @"}\n";

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) {
        return nil;
    }

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"doof_game_color_mesh_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"doof_game_color_mesh_fragment"];
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

}  // namespace

struct NativeColorMesh::Impl {
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

struct NativeColorMeshBuilder::Impl {
    std::vector<ColorMeshVertex> vertices;
    std::vector<uint32_t> indices;
};

NativeColorMesh::NativeColorMesh(void* device, void* vertexBuffer, void* indexBuffer, int32_t vertexCount, int32_t indexCount)
    : impl_(std::make_shared<Impl>(device, vertexBuffer, indexBuffer, vertexCount, indexCount)) {}

NativeColorMesh::~NativeColorMesh() = default;

int32_t NativeColorMesh::vertexCount() const {
    return impl_->vertexCount;
}

int32_t NativeColorMesh::indexCount() const {
    return impl_->indexCount;
}

int64_t NativeColorMesh::metalDeviceHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->device);
}

int64_t NativeColorMesh::metalVertexBufferHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->vertexBuffer);
}

int64_t NativeColorMesh::metalIndexBufferHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->indexBuffer);
}

std::shared_ptr<NativeColorMeshBuilder> NativeColorMeshBuilder::create() {
    return std::make_shared<NativeColorMeshBuilder>();
}

NativeColorMeshBuilder::NativeColorMeshBuilder()
    : impl_(std::make_shared<Impl>()) {}

NativeColorMeshBuilder::~NativeColorMeshBuilder() = default;

int32_t NativeColorMeshBuilder::addVertex(
    double x,
    double y,
    double z,
    double red,
    double green,
    double blue,
    double alpha
) {
    impl_->vertices.push_back(ColorMeshVertex {
        static_cast<float>(x),
        static_cast<float>(y),
        static_cast<float>(z),
        1.0f,
        static_cast<float>(red),
        static_cast<float>(green),
        static_cast<float>(blue),
        static_cast<float>(alpha),
    });
    return static_cast<int32_t>(impl_->vertices.size() - 1);
}

std::shared_ptr<NativeColorMeshBuilder> NativeColorMeshBuilder::addTriangle(int32_t a, int32_t b, int32_t c) {
    impl_->indices.push_back(static_cast<uint32_t>(a));
    impl_->indices.push_back(static_cast<uint32_t>(b));
    impl_->indices.push_back(static_cast<uint32_t>(c));
    return shared_from_this();
}

doof::Result<std::shared_ptr<NativeColorMesh>, std::string> NativeColorMeshBuilder::build(int64_t metalDeviceHandle) {
    id<MTLDevice> device = (__bridge id<MTLDevice>)reinterpret_cast<void*>(metalDeviceHandle);
    if (device == nil) {
        return doof::Result<std::shared_ptr<NativeColorMesh>, std::string>::failure("Metal device handle is invalid");
    }

    if (impl_->vertices.empty()) {
        return doof::Result<std::shared_ptr<NativeColorMesh>, std::string>::failure("Color mesh has no vertices");
    }

    if (impl_->indices.empty()) {
        return doof::Result<std::shared_ptr<NativeColorMesh>, std::string>::failure("Color mesh has no triangles");
    }

    for (uint32_t index : impl_->indices) {
        if (index >= impl_->vertices.size()) {
            return doof::Result<std::shared_ptr<NativeColorMesh>, std::string>::failure("Color mesh triangle index is out of range");
        }
    }

    id<MTLBuffer> vertexBuffer = [device newBufferWithBytes:impl_->vertices.data()
                                                     length:impl_->vertices.size() * sizeof(ColorMeshVertex)
                                                    options:MTLResourceStorageModeShared];
    if (vertexBuffer == nil) {
        return doof::Result<std::shared_ptr<NativeColorMesh>, std::string>::failure("Failed to create color mesh vertex buffer");
    }

    id<MTLBuffer> indexBuffer = [device newBufferWithBytes:impl_->indices.data()
                                                    length:impl_->indices.size() * sizeof(uint32_t)
                                                   options:MTLResourceStorageModeShared];
    if (indexBuffer == nil) {
        [vertexBuffer release];
        return doof::Result<std::shared_ptr<NativeColorMesh>, std::string>::failure("Failed to create color mesh index buffer");
    }

    auto mesh = std::make_shared<NativeColorMesh>(
        (__bridge void*)device,
        (__bridge void*)vertexBuffer,
        (__bridge void*)indexBuffer,
        static_cast<int32_t>(impl_->vertices.size()),
        static_cast<int32_t>(impl_->indices.size())
    );

    [indexBuffer release];
    [vertexBuffer release];

    return doof::Result<std::shared_ptr<NativeColorMesh>, std::string>::success(mesh);
}

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
) {
    if (!mesh || mesh->indexCount() <= 0) {
        return;
    }

    id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)reinterpret_cast<void*>(metalRenderCommandEncoderHandle);
    id<MTLDevice> device = (__bridge id<MTLDevice>)reinterpret_cast<void*>(metalDeviceHandle);
    id<MTLBuffer> vertexBuffer = (__bridge id<MTLBuffer>)reinterpret_cast<void*>(mesh->metalVertexBufferHandle());
    id<MTLBuffer> indexBuffer = (__bridge id<MTLBuffer>)reinterpret_cast<void*>(mesh->metalIndexBufferHandle());
    if (encoder == nil || device == nil || vertexBuffer == nil || indexBuffer == nil) {
        return;
    }

    id<MTLRenderPipelineState> pipeline = colorMeshPipeline(device, blendMode, hasDepthAttachment);
    if (pipeline == nil) {
        return;
    }

    ColorMeshUniforms uniforms = {
        {
            static_cast<float>(m00),
            static_cast<float>(m01),
            static_cast<float>(m02),
            static_cast<float>(m03),
        },
        {
            static_cast<float>(m10),
            static_cast<float>(m11),
            static_cast<float>(m12),
            static_cast<float>(m13),
        },
        {
            static_cast<float>(m20),
            static_cast<float>(m21),
            static_cast<float>(m22),
            static_cast<float>(m23),
        },
        {
            static_cast<float>(m30),
            static_cast<float>(m31),
            static_cast<float>(m32),
            static_cast<float>(m33),
        },
    };

    [encoder setRenderPipelineState:pipeline];
    [encoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder setVertexBuffer:indexBuffer offset:0 atIndex:2];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:static_cast<NSUInteger>(mesh->indexCount())];
}

}  // namespace doof_game
