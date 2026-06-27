#include "native_mesh_internal.hpp"

#include <climits>
#include <memory>
#include <string>
#include <vector>

namespace doof_game {
namespace {

using native_mesh::SimpleMeshVertex;

NSString* nsString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

std::string errorMessage(NSError* error, const std::string& fallback) {
    if (error == nil || error.localizedDescription == nil) {
        return fallback;
    }
    return std::string([error.localizedDescription UTF8String]);
}

bool sameSize3(
    const std::shared_ptr<std::vector<int32_t>>& a,
    const std::shared_ptr<std::vector<int64_t>>& b,
    const std::shared_ptr<std::vector<int32_t>>& c
) {
    if (!a || !b || !c) {
        return false;
    }
    return a->size() == b->size() && a->size() == c->size();
}

bool sameSize2(
    const std::shared_ptr<std::vector<int32_t>>& a,
    const std::shared_ptr<std::vector<int64_t>>& b
) {
    if (!a || !b) {
        return false;
    }
    return a->size() == b->size();
}

MTLVertexFormat shaderVertexFormat(int32_t format) {
    switch (format) {
        case 1: return MTLVertexFormatFloat;
        case 2: return MTLVertexFormatFloat2;
        case 3: return MTLVertexFormatFloat3;
        case 4: return MTLVertexFormatFloat4;
        case 5: return MTLVertexFormatUInt;
        case 6: return MTLVertexFormatUChar4Normalized;
        default: return MTLVertexFormatInvalid;
    }
}

MTLVertexStepFunction shaderVertexStepFunction(int32_t stepFunction) {
    switch (stepFunction) {
        case 1: return MTLVertexStepFunctionPerVertex;
        case 2: return MTLVertexStepFunctionPerInstance;
        default: return MTLVertexStepFunctionConstant;
    }
}

doof::Result<void, std::string> bindBuffers(
    id<MTLRenderCommandEncoder> encoder,
    const std::shared_ptr<std::vector<int32_t>>& indices,
    const std::shared_ptr<std::vector<int64_t>>& handles,
    const std::shared_ptr<std::vector<int32_t>>& offsets,
    bool fragment
) {
    if (!sameSize3(indices, handles, offsets)) {
        return doof::Result<void, std::string>::failure("Shader buffer binding arrays must have matching lengths");
    }

    for (size_t i = 0; i < indices->size(); ++i) {
        if ((*indices)[i] < 0 || (*offsets)[i] < 0) {
            return doof::Result<void, std::string>::failure("Shader buffer binding index and offset must be non-negative");
        }
        id<MTLBuffer> buffer = native_mesh::bridgeMetalHandle<id<MTLBuffer>>((*handles)[i]);
        if (buffer == nil) {
            return doof::Result<void, std::string>::failure("Shader buffer binding has an invalid Metal buffer handle");
        }
        NSUInteger offset = static_cast<NSUInteger>((*offsets)[i]);
        NSUInteger index = static_cast<NSUInteger>((*indices)[i]);
        if (fragment) {
            [encoder setFragmentBuffer:buffer offset:offset atIndex:index];
        } else {
            [encoder setVertexBuffer:buffer offset:offset atIndex:index];
        }
    }
    return doof::Result<void, std::string>::success();
}

doof::Result<void, std::string> bindTextures(
    id<MTLRenderCommandEncoder> encoder,
    id<MTLDevice> device,
    const std::shared_ptr<std::vector<int32_t>>& indices,
    const std::shared_ptr<std::vector<int64_t>>& handles
) {
    if (!sameSize2(indices, handles)) {
        return doof::Result<void, std::string>::failure("Shader texture binding arrays must have matching lengths");
    }
    if (indices->empty()) {
        return doof::Result<void, std::string>::success();
    }

    id<MTLSamplerState> sampler = native_mesh::linearSampler(device, MTLSamplerAddressModeClampToEdge);
    if (sampler == nil) {
        return doof::Result<void, std::string>::failure("Failed to create shader texture sampler");
    }

    for (size_t i = 0; i < indices->size(); ++i) {
        if ((*indices)[i] < 0) {
            return doof::Result<void, std::string>::failure("Shader texture binding index must be non-negative");
        }
        id<MTLTexture> texture = native_mesh::bridgeMetalHandle<id<MTLTexture>>((*handles)[i]);
        if (texture == nil) {
            return doof::Result<void, std::string>::failure("Shader texture binding has an invalid Metal texture handle");
        }
        NSUInteger index = static_cast<NSUInteger>((*indices)[i]);
        [encoder setFragmentTexture:texture atIndex:index];
        [encoder setFragmentSamplerState:sampler atIndex:index];
    }
    return doof::Result<void, std::string>::success();
}

struct SimpleModelInstance {
    float row0[4];
    float row1[4];
    float row2[4];
    float row3[4];
    float tint[4];
    float effects[4];
    float uv[4];
};

struct SimpleMeshLightingUniforms {
    float direction[4];
    float levels[4];
};

SimpleMeshLightingUniforms makeSimpleMeshLightingUniforms(
    double ambientLight,
    double directionalLight,
    double lightDirectionX,
    double lightDirectionY,
    double lightDirectionZ
) {
    return SimpleMeshLightingUniforms {
        {
            static_cast<float>(lightDirectionX),
            static_cast<float>(lightDirectionY),
            static_cast<float>(lightDirectionZ),
            0.0f,
        },
        {
            static_cast<float>(ambientLight),
            static_cast<float>(directionalLight),
            0.0f,
            0.0f,
        },
    };
}

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
        @"struct Lighting { float4 direction; float4 levels; };\n"
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
        @"float3 doof_game_simple_mesh_light_direction(constant Lighting& lighting) {\n"
        @"  float len = length(lighting.direction.xyz);\n"
        @"  if (len < 0.0001) { return normalize(float3(0.35, 0.60, 0.72)); }\n"
        @"  return lighting.direction.xyz / len;\n"
        @"}\n"
        @"float4 doof_game_apply_simple_mesh_light(float4 base, float3 normal, constant Lighting& lighting) {\n"
        @"  float len = max(length(normal), 0.0001);\n"
        @"  float3 n = normal / len;\n"
        @"  float ambient = max(lighting.levels.x, 0.0);\n"
        @"  float directional = max(lighting.levels.y, 0.0);\n"
        @"  float amount = ambient + directional * max(dot(n, doof_game_simple_mesh_light_direction(lighting)), 0.0);\n"
        @"  return float4(base.rgb * amount, base.a);\n"
        @"}\n"
        @"fragment float4 doof_game_simple_mesh_fragment(VertexOut in [[stage_in]], constant Lighting& lighting [[buffer(0)]]) {\n"
        @"  return doof_game_apply_simple_mesh_light(in.color, in.normal, lighting);\n"
        @"}\n"
        @"fragment float4 doof_game_textured_simple_mesh_fragment(VertexOut in [[stage_in]], constant Lighting& lighting [[buffer(0)]], texture2d<float> tex [[texture(0)]], sampler textureSampler [[sampler(0)]]) {\n"
        @"  return doof_game_apply_simple_mesh_light(tex.sample(textureSampler, in.uv) * in.color, in.normal, lighting);\n"
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
    native_mesh::configureDepthAttachment(descriptor, hasDepthAttachment);
    if (blendMode == 1) {
        native_mesh::configureAlphaBlending(descriptor.colorAttachments[0]);
    }

    id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    [descriptor.vertexFunction release];
    [descriptor.fragmentFunction release];
    [descriptor release];
    [library release];
    pipelines[slot] = pipeline;
    return pipelines[slot];
}

id<MTLRenderPipelineState> simpleModelBatchPipeline(id<MTLDevice> device, int32_t blendMode, bool hasDepthAttachment, bool textured) {
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
        @"struct Instance { float4 row0; float4 row1; float4 row2; float4 row3; float4 tint; float4 effects; float4 uv; };\n"
        @"struct Uniforms { float4 row0; float4 row1; float4 row2; float4 row3; };\n"
        @"struct Lighting { float4 direction; float4 levels; };\n"
        @"struct VertexOut { float4 position [[position]]; float4 color; float2 uv; float3 normal; float whiteBlend; };\n"
        @"vertex VertexOut doof_game_simple_model_batch_vertex(const device VertexIn* vertices [[buffer(0)]], constant Uniforms& uniforms [[buffer(1)]], const device uint* indices [[buffer(2)]], const device Instance* instances [[buffer(3)]], uint vertexId [[vertex_id]], uint instanceId [[instance_id]]) {\n"
        @"  VertexIn meshVertex = vertices[indices[vertexId]];\n"
        @"  Instance inst = instances[instanceId];\n"
        @"  float4 local = meshVertex.position;\n"
        @"  float4 world = float4(dot(inst.row0, local), dot(inst.row1, local), dot(inst.row2, local), dot(inst.row3, local));\n"
        @"  VertexOut out;\n"
        @"  out.position = float4(dot(uniforms.row0, world), dot(uniforms.row1, world), dot(uniforms.row2, world), dot(uniforms.row3, world));\n"
        @"  out.color = meshVertex.color * inst.tint;\n"
        @"  out.uv = meshVertex.uv * inst.uv.zw + inst.uv.xy;\n"
        @"  out.normal = meshVertex.normal.xyz;\n"
        @"  out.whiteBlend = inst.effects.x;\n"
        @"  return out;\n"
        @"}\n"
        @"float3 doof_game_simple_model_batch_light_direction(constant Lighting& lighting) {\n"
        @"  float len = length(lighting.direction.xyz);\n"
        @"  if (len < 0.0001) { return normalize(float3(0.35, 0.60, 0.72)); }\n"
        @"  return lighting.direction.xyz / len;\n"
        @"}\n"
        @"float4 doof_game_apply_simple_model_batch_light(float4 base, float3 normal, constant Lighting& lighting) {\n"
        @"  float len = max(length(normal), 0.0001);\n"
        @"  float3 n = normal / len;\n"
        @"  float ambient = max(lighting.levels.x, 0.0);\n"
        @"  float directional = max(lighting.levels.y, 0.0);\n"
        @"  float amount = ambient + directional * max(dot(n, doof_game_simple_model_batch_light_direction(lighting)), 0.0);\n"
        @"  return float4(base.rgb * amount, base.a);\n"
        @"}\n"
        @"fragment float4 doof_game_simple_model_batch_fragment(VertexOut in [[stage_in]], constant Lighting& lighting [[buffer(0)]]) {\n"
        @"  return doof_game_apply_simple_model_batch_light(in.color, in.normal, lighting);\n"
        @"}\n"
        @"fragment float4 doof_game_textured_simple_model_batch_fragment(VertexOut in [[stage_in]], constant Lighting& lighting [[buffer(0)]], texture2d<float> tex [[texture(0)]], sampler textureSampler [[sampler(0)]]) {\n"
        @"  float4 sampled = tex.sample(textureSampler, in.uv) * in.color;\n"
        @"  sampled.rgb = mix(sampled.rgb, float3(1.0), clamp(in.whiteBlend, 0.0, 1.0));\n"
        @"  return doof_game_apply_simple_model_batch_light(sampled, in.normal, lighting);\n"
        @"}\n";

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) {
        return nil;
    }

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"doof_game_simple_model_batch_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:(textured ? @"doof_game_textured_simple_model_batch_fragment" : @"doof_game_simple_model_batch_fragment")];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    native_mesh::configureDepthAttachment(descriptor, hasDepthAttachment);
    if (blendMode == 1) {
        native_mesh::configureAlphaBlending(descriptor.colorAttachments[0]);
    }

    id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    [descriptor.vertexFunction release];
    [descriptor.fragmentFunction release];
    [descriptor release];
    [library release];
    pipelines[slot] = pipeline;
    return pipelines[slot];
}

void drawSimpleMeshInternal(
    std::shared_ptr<NativeSimpleMesh> mesh,
    int64_t metalTextureHandle,
    bool textured,
    int64_t metalRenderCommandEncoderHandle,
    int64_t metalDeviceHandle,
    int32_t blendMode,
    bool hasDepthAttachment,
    const native_mesh::MatrixUniforms& uniforms,
    const SimpleMeshLightingUniforms& lighting
) {
    if (!mesh || mesh->indexCount() <= 0) {
        return;
    }

    id<MTLTexture> texture = native_mesh::bridgeMetalHandle<id<MTLTexture>>(metalTextureHandle);
    id<MTLRenderCommandEncoder> encoder = native_mesh::bridgeMetalHandle<id<MTLRenderCommandEncoder>>(metalRenderCommandEncoderHandle);
    id<MTLDevice> device = native_mesh::bridgeMetalHandle<id<MTLDevice>>(metalDeviceHandle);
    id<MTLBuffer> vertexBuffer = native_mesh::bridgeMetalHandle<id<MTLBuffer>>(mesh->metalVertexBufferHandle());
    id<MTLBuffer> indexBuffer = native_mesh::bridgeMetalHandle<id<MTLBuffer>>(mesh->metalIndexBufferHandle());
    if (encoder == nil || device == nil || vertexBuffer == nil || indexBuffer == nil) {
        return;
    }

    id<MTLRenderPipelineState> pipeline = simpleMeshPipeline(device, blendMode, hasDepthAttachment, textured);
    if (pipeline == nil) {
        return;
    }

    if (textured) {
        id<MTLSamplerState> sampler = native_mesh::linearSampler(device, MTLSamplerAddressModeRepeat);
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
    [encoder setFragmentBytes:&lighting length:sizeof(lighting) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:static_cast<NSUInteger>(mesh->indexCount())];
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

struct NativeSimpleModelBatch::Impl {
    id<MTLDevice> device = nil;
    id<MTLBuffer> instanceBuffer = nil;
    int32_t capacity = 0;
    int32_t count = 0;

    Impl(void* rawDevice, void* rawInstanceBuffer, int32_t capacity)
        : device((__bridge id<MTLDevice>)rawDevice),
          instanceBuffer((__bridge id<MTLBuffer>)rawInstanceBuffer),
          capacity(capacity) {
        [device retain];
        [instanceBuffer retain];
    }

    ~Impl() {
        [instanceBuffer release];
        [device release];
    }
};

struct NativeShaderBuffer::Impl {
    id<MTLDevice> device = nil;
    id<MTLBuffer> buffer = nil;
    int32_t byteLength = 0;

    Impl(void* rawDevice, void* rawBuffer, int32_t byteLength)
        : device((__bridge id<MTLDevice>)rawDevice),
          buffer((__bridge id<MTLBuffer>)rawBuffer),
          byteLength(byteLength) {
        [device retain];
        [buffer retain];
    }

    ~Impl() {
        [buffer release];
        [device release];
    }
};

struct NativeShaderPipeline::Impl {
    id<MTLDevice> device = nil;
    id<MTLLibrary> library = nil;
    MTLVertexDescriptor* vertexDescriptor = nil;
    std::string vertexFunction;
    std::string fragmentFunction;
    id<MTLRenderPipelineState> pipelines[4] = {};
    bool attempted[4] = {};
    std::string errors[4];

    Impl(
        void* rawDevice,
        void* rawLibrary,
        void* rawVertexDescriptor,
        std::string vertexFunction,
        std::string fragmentFunction
    )
        : device((__bridge id<MTLDevice>)rawDevice),
          library((__bridge id<MTLLibrary>)rawLibrary),
          vertexDescriptor((__bridge MTLVertexDescriptor*)rawVertexDescriptor),
          vertexFunction(std::move(vertexFunction)),
          fragmentFunction(std::move(fragmentFunction)) {
        [device retain];
        [library retain];
        [vertexDescriptor retain];
    }

    ~Impl() {
        for (id<MTLRenderPipelineState> pipeline : pipelines) {
            [pipeline release];
        }
        [vertexDescriptor release];
        [library release];
        [device release];
    }
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
    return native_mesh::metalHandle(impl_->device);
}

int64_t NativeSimpleMesh::metalVertexBufferHandle() const {
    return native_mesh::metalHandle(impl_->vertexBuffer);
}

int64_t NativeSimpleMesh::metalIndexBufferHandle() const {
    return native_mesh::metalHandle(impl_->indexBuffer);
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
    id<MTLDevice> device = native_mesh::bridgeMetalHandle<id<MTLDevice>>(metalDeviceHandle);
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

doof::Result<std::shared_ptr<NativeSimpleModelBatch>, std::string> NativeSimpleModelBatch::create(int64_t metalDeviceHandle, int32_t capacity) {
    id<MTLDevice> device = native_mesh::bridgeMetalHandle<id<MTLDevice>>(metalDeviceHandle);
    if (device == nil) {
        return doof::Result<std::shared_ptr<NativeSimpleModelBatch>, std::string>::failure("Metal device handle is invalid");
    }

    if (capacity <= 0) {
        return doof::Result<std::shared_ptr<NativeSimpleModelBatch>, std::string>::failure("Simple model batch capacity must be positive");
    }

    id<MTLBuffer> instanceBuffer = [device newBufferWithLength:static_cast<NSUInteger>(capacity) * sizeof(SimpleModelInstance)
                                                       options:MTLResourceStorageModeShared];
    if (instanceBuffer == nil) {
        return doof::Result<std::shared_ptr<NativeSimpleModelBatch>, std::string>::failure("Failed to create simple model batch instance buffer");
    }

    auto batch = std::make_shared<NativeSimpleModelBatch>(
        (__bridge void*)device,
        (__bridge void*)instanceBuffer,
        capacity
    );

    [instanceBuffer release];

    return doof::Result<std::shared_ptr<NativeSimpleModelBatch>, std::string>::success(batch);
}

NativeSimpleModelBatch::NativeSimpleModelBatch(void* device, void* instanceBuffer, int32_t capacity)
    : impl_(std::make_shared<Impl>(device, instanceBuffer, capacity)) {}

NativeSimpleModelBatch::~NativeSimpleModelBatch() = default;

int32_t NativeSimpleModelBatch::capacity() const {
    return impl_->capacity;
}

int32_t NativeSimpleModelBatch::count() const {
    return impl_->count;
}

void NativeSimpleModelBatch::setCount(int32_t count) {
    if (count < 0) {
        impl_->count = 0;
        return;
    }
    if (count > impl_->capacity) {
        impl_->count = impl_->capacity;
        return;
    }
    impl_->count = count;
}

void NativeSimpleModelBatch::setInstance(
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
) {
    if (slot < 0 || slot >= impl_->capacity || impl_->instanceBuffer == nil) {
        return;
    }

    auto* instances = static_cast<SimpleModelInstance*>([impl_->instanceBuffer contents]);
    instances[slot] = SimpleModelInstance {
        { static_cast<float>(m00), static_cast<float>(m01), static_cast<float>(m02), static_cast<float>(m03) },
        { static_cast<float>(m10), static_cast<float>(m11), static_cast<float>(m12), static_cast<float>(m13) },
        { static_cast<float>(m20), static_cast<float>(m21), static_cast<float>(m22), static_cast<float>(m23) },
        { static_cast<float>(m30), static_cast<float>(m31), static_cast<float>(m32), static_cast<float>(m33) },
        { static_cast<float>(red), static_cast<float>(green), static_cast<float>(blue), static_cast<float>(alpha) },
        { static_cast<float>(whiteBlend), 0.0f, 0.0f, 0.0f },
        { static_cast<float>(uvOffsetX), static_cast<float>(uvOffsetY), static_cast<float>(uvScaleX), static_cast<float>(uvScaleY) },
    };
}

int64_t NativeSimpleModelBatch::metalInstanceBufferHandle() const {
    return native_mesh::metalHandle(impl_->instanceBuffer);
}

doof::Result<std::shared_ptr<NativeShaderBuffer>, std::string> NativeShaderBuffer::create(
    int64_t metalDeviceHandle,
    const std::shared_ptr<std::vector<uint8_t>>& data
) {
    id<MTLDevice> device = native_mesh::bridgeMetalHandle<id<MTLDevice>>(metalDeviceHandle);
    if (device == nil) {
        return doof::Result<std::shared_ptr<NativeShaderBuffer>, std::string>::failure("Metal device handle is invalid");
    }

    if (!data || data->empty()) {
        return doof::Result<std::shared_ptr<NativeShaderBuffer>, std::string>::failure("Shader buffer data must not be empty");
    }

    if (data->size() > static_cast<size_t>(INT32_MAX)) {
        return doof::Result<std::shared_ptr<NativeShaderBuffer>, std::string>::failure("Shader buffer data is too large");
    }

    id<MTLBuffer> buffer = [device newBufferWithBytes:data->data()
                                               length:data->size()
                                              options:MTLResourceStorageModeShared];
    if (buffer == nil) {
        return doof::Result<std::shared_ptr<NativeShaderBuffer>, std::string>::failure("Failed to create shader buffer");
    }

    auto shaderBuffer = std::make_shared<NativeShaderBuffer>(
        (__bridge void*)device,
        (__bridge void*)buffer,
        static_cast<int32_t>(data->size())
    );
    [buffer release];
    return doof::Result<std::shared_ptr<NativeShaderBuffer>, std::string>::success(shaderBuffer);
}

NativeShaderBuffer::NativeShaderBuffer(void* device, void* buffer, int32_t byteLength)
    : impl_(std::make_shared<Impl>(device, buffer, byteLength)) {}

NativeShaderBuffer::~NativeShaderBuffer() = default;

int32_t NativeShaderBuffer::byteLength() const {
    return impl_->byteLength;
}

int64_t NativeShaderBuffer::metalBufferHandle() const {
    return native_mesh::metalHandle(impl_->buffer);
}

doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string> NativeShaderPipeline::create(
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
) {
    id<MTLDevice> device = native_mesh::bridgeMetalHandle<id<MTLDevice>>(metalDeviceHandle);
    if (device == nil) {
        return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure("Metal device handle is invalid");
    }
    if (source.empty()) {
        return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure("Shader source must not be empty");
    }
    if (vertexFunction.empty()) {
        return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure("Shader vertex function name must not be empty");
    }
    if (fragmentFunction.empty()) {
        return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure("Shader fragment function name must not be empty");
    }
    if (!attributeIndices || !attributeBuffers || !attributeOffsets || !attributeFormats ||
        attributeIndices->size() != attributeBuffers->size() ||
        attributeIndices->size() != attributeOffsets->size() ||
        attributeIndices->size() != attributeFormats->size()) {
        return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure("Shader vertex attribute arrays must have matching lengths");
    }
    if (!layoutBuffers || !layoutStrides || !layoutStepFunctions || !layoutStepRates ||
        layoutBuffers->size() != layoutStrides->size() ||
        layoutBuffers->size() != layoutStepFunctions->size() ||
        layoutBuffers->size() != layoutStepRates->size()) {
        return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure("Shader vertex layout arrays must have matching lengths");
    }

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:nsString(source) options:nil error:&error];
    if (library == nil) {
        return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure(errorMessage(error, "Failed to compile shader source"));
    }

    id<MTLFunction> vertex = [library newFunctionWithName:nsString(vertexFunction)];
    if (vertex == nil) {
        [library release];
        return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure("Shader vertex function was not found: " + vertexFunction);
    }
    [vertex release];

    id<MTLFunction> fragment = [library newFunctionWithName:nsString(fragmentFunction)];
    if (fragment == nil) {
        [library release];
        return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure("Shader fragment function was not found: " + fragmentFunction);
    }
    [fragment release];

    MTLVertexDescriptor* vertexDescriptor = [[MTLVertexDescriptor alloc] init];
    for (size_t i = 0; i < layoutBuffers->size(); ++i) {
        if ((*layoutBuffers)[i] < 0 || (*layoutStrides)[i] <= 0 || (*layoutStepRates)[i] <= 0) {
            [vertexDescriptor release];
            [library release];
            return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure("Shader vertex layout buffer index, stride, and step rate must be positive");
        }
        MTLVertexStepFunction stepFunction = shaderVertexStepFunction((*layoutStepFunctions)[i]);
        if (stepFunction == MTLVertexStepFunctionConstant) {
            [vertexDescriptor release];
            [library release];
            return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure("Shader vertex layout step function is invalid");
        }
        vertexDescriptor.layouts[static_cast<NSUInteger>((*layoutBuffers)[i])].stride = static_cast<NSUInteger>((*layoutStrides)[i]);
        vertexDescriptor.layouts[static_cast<NSUInteger>((*layoutBuffers)[i])].stepFunction = stepFunction;
        vertexDescriptor.layouts[static_cast<NSUInteger>((*layoutBuffers)[i])].stepRate = static_cast<NSUInteger>((*layoutStepRates)[i]);
    }

    for (size_t i = 0; i < attributeIndices->size(); ++i) {
        if ((*attributeIndices)[i] < 0 || (*attributeBuffers)[i] < 0 || (*attributeOffsets)[i] < 0) {
            [vertexDescriptor release];
            [library release];
            return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure("Shader vertex attribute index, buffer, and offset must be non-negative");
        }
        MTLVertexFormat format = shaderVertexFormat((*attributeFormats)[i]);
        if (format == MTLVertexFormatInvalid) {
            [vertexDescriptor release];
            [library release];
            return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::failure("Shader vertex attribute format is invalid");
        }
        MTLVertexAttributeDescriptor* attribute = vertexDescriptor.attributes[static_cast<NSUInteger>((*attributeIndices)[i])];
        attribute.format = format;
        attribute.offset = static_cast<NSUInteger>((*attributeOffsets)[i]);
        attribute.bufferIndex = static_cast<NSUInteger>((*attributeBuffers)[i]);
    }

    auto pipeline = std::make_shared<NativeShaderPipeline>(
        (__bridge void*)device,
        (__bridge void*)library,
        (__bridge void*)vertexDescriptor,
        vertexFunction,
        fragmentFunction
    );
    [vertexDescriptor release];
    [library release];
    return doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string>::success(pipeline);
}

NativeShaderPipeline::NativeShaderPipeline(
    void* device,
    void* library,
    void* vertexDescriptor,
    std::string vertexFunction,
    std::string fragmentFunction
) : impl_(std::make_shared<Impl>(device, library, vertexDescriptor, std::move(vertexFunction), std::move(fragmentFunction))) {}

NativeShaderPipeline::~NativeShaderPipeline() = default;

doof::Result<int64_t, std::string> NativeShaderPipeline::metalPipelineHandle(int32_t blendMode, bool hasDepthAttachment) {
    if (impl_->device == nil || impl_->library == nil || impl_->vertexDescriptor == nil) {
        return doof::Result<int64_t, std::string>::failure("Shader pipeline is invalid");
    }

    int32_t slot = (blendMode == 1 ? 2 : 0) + (hasDepthAttachment ? 1 : 0);
    if (impl_->pipelines[slot] != nil) {
        return doof::Result<int64_t, std::string>::success(native_mesh::metalHandle(impl_->pipelines[slot]));
    }
    if (impl_->attempted[slot]) {
        return doof::Result<int64_t, std::string>::failure(impl_->errors[slot]);
    }
    impl_->attempted[slot] = true;

    id<MTLFunction> vertex = [impl_->library newFunctionWithName:nsString(impl_->vertexFunction)];
    id<MTLFunction> fragment = [impl_->library newFunctionWithName:nsString(impl_->fragmentFunction)];
    if (vertex == nil || fragment == nil) {
        [fragment release];
        [vertex release];
        impl_->errors[slot] = "Shader functions are no longer available";
        return doof::Result<int64_t, std::string>::failure(impl_->errors[slot]);
    }

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertex;
    descriptor.fragmentFunction = fragment;
    descriptor.vertexDescriptor = impl_->vertexDescriptor;
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    native_mesh::configureDepthAttachment(descriptor, hasDepthAttachment);
    if (blendMode == 1) {
        native_mesh::configureAlphaBlending(descriptor.colorAttachments[0]);
    }

    NSError* error = nil;
    id<MTLRenderPipelineState> pipeline = [impl_->device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    [descriptor release];
    [fragment release];
    [vertex release];

    if (pipeline == nil) {
        impl_->errors[slot] = errorMessage(error, "Failed to create shader render pipeline");
        return doof::Result<int64_t, std::string>::failure(impl_->errors[slot]);
    }

    impl_->pipelines[slot] = pipeline;
    return doof::Result<int64_t, std::string>::success(native_mesh::metalHandle(pipeline));
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
    double m33,
    double ambientLight,
    double directionalLight,
    double lightDirectionX,
    double lightDirectionY,
    double lightDirectionZ
) {
    drawSimpleMeshInternal(
        mesh,
        0,
        false,
        metalRenderCommandEncoderHandle,
        metalDeviceHandle,
        blendMode,
        hasDepthAttachment,
        native_mesh::makeMatrixUniforms(m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33),
        makeSimpleMeshLightingUniforms(ambientLight, directionalLight, lightDirectionX, lightDirectionY, lightDirectionZ)
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
    double m33,
    double ambientLight,
    double directionalLight,
    double lightDirectionX,
    double lightDirectionY,
    double lightDirectionZ
) {
    drawSimpleMeshInternal(
        mesh,
        metalTextureHandle,
        true,
        metalRenderCommandEncoderHandle,
        metalDeviceHandle,
        blendMode,
        hasDepthAttachment,
        native_mesh::makeMatrixUniforms(m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33),
        makeSimpleMeshLightingUniforms(ambientLight, directionalLight, lightDirectionX, lightDirectionY, lightDirectionZ)
    );
}

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
    double m33,
    double ambientLight,
    double directionalLight,
    double lightDirectionX,
    double lightDirectionY,
    double lightDirectionZ
) {
    if (!mesh || !batch || mesh->indexCount() <= 0 || batch->count() <= 0) {
        return;
    }

    id<MTLTexture> texture = native_mesh::bridgeMetalHandle<id<MTLTexture>>(metalTextureHandle);
    id<MTLRenderCommandEncoder> encoder = native_mesh::bridgeMetalHandle<id<MTLRenderCommandEncoder>>(metalRenderCommandEncoderHandle);
    id<MTLDevice> device = native_mesh::bridgeMetalHandle<id<MTLDevice>>(metalDeviceHandle);
    id<MTLBuffer> vertexBuffer = native_mesh::bridgeMetalHandle<id<MTLBuffer>>(mesh->metalVertexBufferHandle());
    id<MTLBuffer> indexBuffer = native_mesh::bridgeMetalHandle<id<MTLBuffer>>(mesh->metalIndexBufferHandle());
    id<MTLBuffer> instanceBuffer = native_mesh::bridgeMetalHandle<id<MTLBuffer>>(batch->metalInstanceBufferHandle());
    if (encoder == nil || device == nil || vertexBuffer == nil || indexBuffer == nil || instanceBuffer == nil) {
        return;
    }

    id<MTLRenderPipelineState> pipeline = simpleModelBatchPipeline(device, blendMode, hasDepthAttachment, textured);
    if (pipeline == nil) {
        return;
    }

    if (textured) {
        id<MTLSamplerState> sampler = native_mesh::linearSampler(device, MTLSamplerAddressModeRepeat);
        if (texture == nil || sampler == nil) {
            return;
        }
        [encoder setFragmentTexture:texture atIndex:0];
        [encoder setFragmentSamplerState:sampler atIndex:0];
    }

    native_mesh::MatrixUniforms uniforms = native_mesh::makeMatrixUniforms(
        m00, m01, m02, m03,
        m10, m11, m12, m13,
        m20, m21, m22, m23,
        m30, m31, m32, m33
    );
    SimpleMeshLightingUniforms lighting = makeSimpleMeshLightingUniforms(
        ambientLight,
        directionalLight,
        lightDirectionX,
        lightDirectionY,
        lightDirectionZ
    );

    [encoder setRenderPipelineState:pipeline];
    [encoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder setVertexBuffer:indexBuffer offset:0 atIndex:2];
    [encoder setVertexBuffer:instanceBuffer offset:0 atIndex:3];
    [encoder setFragmentBytes:&lighting length:sizeof(lighting) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:static_cast<NSUInteger>(mesh->indexCount())
              instanceCount:static_cast<NSUInteger>(batch->count())];
}

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
) {
    if (!pipeline) {
        return doof::Result<void, std::string>::failure("Shader pipeline is required");
    }

    id<MTLRenderCommandEncoder> encoder = native_mesh::bridgeMetalHandle<id<MTLRenderCommandEncoder>>(metalRenderCommandEncoderHandle);
    if (encoder == nil) {
        return doof::Result<void, std::string>::failure("Metal render command encoder handle is invalid");
    }

    auto pipelineHandle = pipeline->metalPipelineHandle(blendMode, hasDepthAttachment);
    if (pipelineHandle.isFailure()) {
        return doof::Result<void, std::string>::failure(pipelineHandle.error());
    }
    id<MTLRenderPipelineState> metalPipeline = native_mesh::bridgeMetalHandle<id<MTLRenderPipelineState>>(pipelineHandle.value());
    if (metalPipeline == nil) {
        return doof::Result<void, std::string>::failure("Shader pipeline handle is invalid");
    }

    auto boundVertexBuffers = bindBuffers(encoder, vertexBufferIndices, vertexBufferHandles, vertexBufferOffsets, false);
    if (boundVertexBuffers.isFailure()) {
        return boundVertexBuffers;
    }

    auto boundVertexBytes = bindBuffers(encoder, vertexBytesIndices, vertexBytesHandles, vertexBytesOffsets, false);
    if (boundVertexBytes.isFailure()) {
        return boundVertexBytes;
    }

    auto boundFragmentBytes = bindBuffers(encoder, fragmentBytesIndices, fragmentBytesHandles, fragmentBytesOffsets, true);
    if (boundFragmentBytes.isFailure()) {
        return boundFragmentBytes;
    }

    id<MTLDevice> device = metalPipeline.device;
    auto boundTextures = bindTextures(encoder, device, fragmentTextureIndices, fragmentTextureHandles);
    if (boundTextures.isFailure()) {
        return boundTextures;
    }

    [encoder setRenderPipelineState:metalPipeline];

    if (indexCount > 0) {
        if (instanceCount <= 0) {
            return doof::Result<void, std::string>::failure("Shader instance count must be positive");
        }
        id<MTLBuffer> indexBuffer = native_mesh::bridgeMetalHandle<id<MTLBuffer>>(indexBufferHandle);
        if (indexBuffer == nil) {
            return doof::Result<void, std::string>::failure("Shader index buffer handle is invalid");
        }
        [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                            indexCount:static_cast<NSUInteger>(indexCount)
                             indexType:MTLIndexTypeUInt32
                           indexBuffer:indexBuffer
                     indexBufferOffset:0
                         instanceCount:static_cast<NSUInteger>(instanceCount)];
    } else {
        if (vertexCount <= 0) {
            return doof::Result<void, std::string>::failure("Shader vertex count must be positive for non-indexed draws");
        }
        if (instanceCount <= 0) {
            return doof::Result<void, std::string>::failure("Shader instance count must be positive");
        }
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                    vertexStart:0
                    vertexCount:static_cast<NSUInteger>(vertexCount)
                  instanceCount:static_cast<NSUInteger>(instanceCount)];
    }

    return doof::Result<void, std::string>::success();
}

}  // namespace doof_game
