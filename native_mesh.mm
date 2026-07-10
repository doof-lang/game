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
        return doof::Failure<std::string>{"Shader buffer binding arrays must have matching lengths"};
    }

    for (size_t i = 0; i < indices->size(); ++i) {
        if ((*indices)[i] < 0 || (*offsets)[i] < 0) {
            return doof::Failure<std::string>{"Shader buffer binding index and offset must be non-negative"};
        }
        id<MTLBuffer> buffer = native_mesh::bridgeMetalHandle<id<MTLBuffer>>((*handles)[i]);
        if (buffer == nil) {
            return doof::Failure<std::string>{"Shader buffer binding has an invalid Metal buffer handle"};
        }
        NSUInteger offset = static_cast<NSUInteger>((*offsets)[i]);
        NSUInteger index = static_cast<NSUInteger>((*indices)[i]);
        if (fragment) {
            [encoder setFragmentBuffer:buffer offset:offset atIndex:index];
        } else {
            [encoder setVertexBuffer:buffer offset:offset atIndex:index];
        }
    }
    return doof::Success<void>{};
}

doof::Result<void, std::string> bindTextures(
    id<MTLRenderCommandEncoder> encoder,
    id<MTLDevice> device,
    const std::shared_ptr<std::vector<int32_t>>& indices,
    const std::shared_ptr<std::vector<int64_t>>& handles
) {
    if (!sameSize2(indices, handles)) {
        return doof::Failure<std::string>{"Shader texture binding arrays must have matching lengths"};
    }
    if (indices->empty()) {
        return doof::Success<void>{};
    }

    id<MTLSamplerState> sampler = native_mesh::linearSampler(device, MTLSamplerAddressModeClampToEdge);
    if (sampler == nil) {
        return doof::Failure<std::string>{"Failed to create shader texture sampler"};
    }

    for (size_t i = 0; i < indices->size(); ++i) {
        if ((*indices)[i] < 0) {
            return doof::Failure<std::string>{"Shader texture binding index must be non-negative"};
        }
        id<MTLTexture> texture = native_mesh::bridgeMetalHandle<id<MTLTexture>>((*handles)[i]);
        if (texture == nil) {
            return doof::Failure<std::string>{"Shader texture binding has an invalid Metal texture handle"};
        }
        NSUInteger index = static_cast<NSUInteger>((*indices)[i]);
        [encoder setFragmentTexture:texture atIndex:index];
        [encoder setFragmentSamplerState:sampler atIndex:index];
    }
    return doof::Success<void>{};
}

struct SimpleModelInstance {
    float row0[4];
    float row1[4];
    float row2[4];
    float row3[4];
    float normal0[4];
    float normal1[4];
    float normal2[4];
    float tint[4];
    float effects[4];
    float uv[4];
    float material[4];
};

struct SimpleMeshLightingUniforms {
    float direction[4];
    float levels[4];
    float eye[4];
};

struct SimpleMeshMaterialUniforms {
    float tint[4];
    float effects[4];
    float uv[4];
    float material[4];
};

SimpleMeshLightingUniforms makeSimpleMeshLightingUniforms(
    double ambientLight,
    double directionalLight,
    double lightDirectionX,
    double lightDirectionY,
    double lightDirectionZ,
    double eyeX,
    double eyeY,
    double eyeZ
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
        {
            static_cast<float>(eyeX),
            static_cast<float>(eyeY),
            static_cast<float>(eyeZ),
            0.0f,
        },
    };
}

SimpleMeshMaterialUniforms makeSimpleMeshMaterialUniforms(
    double red,
    double green,
    double blue,
    double alpha,
    double whiteBlend,
    double uvOffsetX,
    double uvOffsetY,
    double uvScaleX,
    double uvScaleY,
    double specular,
    double shininess,
    double fresnel,
    double fresnelPower
) {
    return SimpleMeshMaterialUniforms {
        {
            static_cast<float>(red),
            static_cast<float>(green),
            static_cast<float>(blue),
            static_cast<float>(alpha),
        },
        {
            static_cast<float>(whiteBlend),
            static_cast<float>(specular),
            static_cast<float>(shininess),
            static_cast<float>(fresnel),
        },
        {
            static_cast<float>(uvOffsetX),
            static_cast<float>(uvOffsetY),
            static_cast<float>(uvScaleX),
            static_cast<float>(uvScaleY),
        },
        {
            static_cast<float>(fresnelPower),
            0.0f,
            0.0f,
            0.0f,
        },
    };
}

id<MTLRenderPipelineState> simpleMeshPipeline(id<MTLDevice> device, int32_t blendMode, bool hasColorAttachment, bool hasDepthAttachment, bool textured) {
    if (device == nil) {
        return nil;
    }

    static id<MTLRenderPipelineState> pipelines[16] = {};
    static bool attempted[16] = {};

    int32_t slot = (textured ? 8 : 0) + (blendMode == 1 ? 4 : 0) + (hasColorAttachment ? 2 : 0) + (hasDepthAttachment ? 1 : 0);
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
        @"struct Matrix { float4 row0; float4 row1; float4 row2; float4 row3; };\n"
        @"struct NormalUniforms { float4 row0; float4 row1; float4 row2; float4 row3; };\n"
        @"struct Lighting { float4 direction; float4 levels; float4 eye; };\n"
        @"struct Material { float4 tint; float4 effects; float4 uv; float4 material; };\n"
        @"struct VertexOut { float4 position [[position]]; float4 color; float2 uv; float3 normal; float3 world; };\n"
        @"float4 doof_game_mul_matrix(constant Matrix& matrix, float4 value) {\n"
        @"  return float4(dot(matrix.row0, value), dot(matrix.row1, value), dot(matrix.row2, value), dot(matrix.row3, value));\n"
        @"}\n"
        @"vertex VertexOut doof_game_simple_mesh_vertex(const device VertexIn* vertices [[buffer(0)]], constant Matrix& viewProjection [[buffer(1)]], const device uint* indices [[buffer(2)]], constant NormalUniforms& normalUniforms [[buffer(3)]], constant Matrix& model [[buffer(4)]], uint vertexId [[vertex_id]]) {\n"
        @"  VertexIn meshVertex = vertices[indices[vertexId]];\n"
        @"  float4 p = meshVertex.position;\n"
        @"  float3 n = meshVertex.normal.xyz;\n"
        @"  float4 world = doof_game_mul_matrix(model, p);\n"
        @"  VertexOut out;\n"
        @"  out.position = doof_game_mul_matrix(viewProjection, world);\n"
        @"  out.color = meshVertex.color;\n"
        @"  out.uv = meshVertex.uv;\n"
        @"  out.normal = float3(dot(normalUniforms.row0.xyz, n), dot(normalUniforms.row1.xyz, n), dot(normalUniforms.row2.xyz, n));\n"
        @"  out.world = world.xyz;\n"
        @"  return out;\n"
        @"}\n"
        @"float3 doof_game_simple_mesh_light_direction(constant Lighting& lighting) {\n"
        @"  float len = length(lighting.direction.xyz);\n"
        @"  if (len < 0.0001) { return normalize(float3(0.35, 0.60, 0.72)); }\n"
        @"  return lighting.direction.xyz / len;\n"
        @"}\n"
        @"float4 doof_game_apply_simple_mesh_material(float4 base, constant Material& material) {\n"
        @"  float4 tinted = base * material.tint;\n"
        @"  tinted.rgb = mix(tinted.rgb, float3(1.0), clamp(material.effects.x, 0.0, 1.0));\n"
        @"  return tinted;\n"
        @"}\n"
        @"float4 doof_game_apply_simple_mesh_light(float4 base, float3 normal, float3 world, constant Lighting& lighting, constant Material& material) {\n"
        @"  float len = max(length(normal), 0.0001);\n"
        @"  float3 n = normal / len;\n"
        @"  float3 lightDir = doof_game_simple_mesh_light_direction(lighting);\n"
        @"  float ambient = max(lighting.levels.x, 0.0);\n"
        @"  float directional = max(lighting.levels.y, 0.0);\n"
        @"  float diffuse = max(dot(n, lightDir), 0.0);\n"
        @"  float amount = ambient + directional * diffuse;\n"
        @"  float3 viewDir = normalize(lighting.eye.xyz - world);\n"
        @"  float3 halfDir = normalize(lightDir + viewDir);\n"
        @"  float shininess = max(material.effects.z, 0.0001);\n"
        @"  float specular = max(material.effects.y, 0.0) * pow(max(dot(n, halfDir), 0.0), shininess);\n"
        @"  float fresnelPower = max(material.material.x, 0.0001);\n"
        @"  float fresnel = max(material.effects.w, 0.0) * pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), fresnelPower);\n"
        @"  return float4(base.rgb * amount + float3(specular + fresnel), base.a);\n"
        @"}\n"
        @"void doof_game_discard_empty_simple_mesh_alpha(float alpha) {\n"
        @"  if (alpha <= 0.005) { discard_fragment(); }\n"
        @"}\n"
        @"fragment float4 doof_game_simple_mesh_fragment(VertexOut in [[stage_in]], constant Lighting& lighting [[buffer(0)]], constant Material& material [[buffer(1)]]) {\n"
        @"  float4 base = doof_game_apply_simple_mesh_material(in.color, material);\n"
        @"  doof_game_discard_empty_simple_mesh_alpha(base.a);\n"
        @"  return doof_game_apply_simple_mesh_light(base, in.normal, in.world, lighting, material);\n"
        @"}\n"
        @"fragment float4 doof_game_textured_simple_mesh_fragment(VertexOut in [[stage_in]], constant Lighting& lighting [[buffer(0)]], constant Material& material [[buffer(1)]], texture2d<float> tex [[texture(0)]], sampler textureSampler [[sampler(0)]]) {\n"
        @"  float2 uv = in.uv * material.uv.zw + material.uv.xy;\n"
        @"  float4 sampled = doof_game_apply_simple_mesh_material(tex.sample(textureSampler, uv) * in.color, material);\n"
        @"  doof_game_discard_empty_simple_mesh_alpha(sampled.a);\n"
        @"  return doof_game_apply_simple_mesh_light(sampled, in.normal, in.world, lighting, material);\n"
        @"}\n";

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) {
        return nil;
    }

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"doof_game_simple_mesh_vertex"];
    if (hasColorAttachment) {
        descriptor.fragmentFunction = [library newFunctionWithName:(textured ? @"doof_game_textured_simple_mesh_fragment" : @"doof_game_simple_mesh_fragment")];
        descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    }
    native_mesh::configureDepthAttachment(descriptor, hasDepthAttachment);
    if (hasColorAttachment && blendMode == 1) {
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

id<MTLRenderPipelineState> simpleModelBatchPipeline(id<MTLDevice> device, int32_t blendMode, bool hasColorAttachment, bool hasDepthAttachment, bool textured) {
    if (device == nil) {
        return nil;
    }

    static id<MTLRenderPipelineState> pipelines[16] = {};
    static bool attempted[16] = {};

    int32_t slot = (textured ? 8 : 0) + (blendMode == 1 ? 4 : 0) + (hasColorAttachment ? 2 : 0) + (hasDepthAttachment ? 1 : 0);
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
        @"struct Instance { float4 row0; float4 row1; float4 row2; float4 row3; float4 normal0; float4 normal1; float4 normal2; float4 tint; float4 effects; float4 uv; float4 material; };\n"
        @"struct Uniforms { float4 row0; float4 row1; float4 row2; float4 row3; };\n"
        @"struct Lighting { float4 direction; float4 levels; float4 eye; };\n"
        @"struct VertexOut { float4 position [[position]]; float4 color; float2 uv; float3 normal; float3 world; float4 effects; float4 material; };\n"
        @"vertex VertexOut doof_game_simple_model_batch_vertex(const device VertexIn* vertices [[buffer(0)]], constant Uniforms& uniforms [[buffer(1)]], const device uint* indices [[buffer(2)]], const device Instance* instances [[buffer(3)]], uint vertexId [[vertex_id]], uint instanceId [[instance_id]]) {\n"
        @"  VertexIn meshVertex = vertices[indices[vertexId]];\n"
        @"  Instance inst = instances[instanceId];\n"
        @"  float4 local = meshVertex.position;\n"
        @"  float3 normal = meshVertex.normal.xyz;\n"
        @"  float4 world = float4(dot(inst.row0, local), dot(inst.row1, local), dot(inst.row2, local), dot(inst.row3, local));\n"
        @"  VertexOut out;\n"
        @"  out.position = float4(dot(uniforms.row0, world), dot(uniforms.row1, world), dot(uniforms.row2, world), dot(uniforms.row3, world));\n"
        @"  out.color = meshVertex.color * inst.tint;\n"
        @"  out.uv = meshVertex.uv * inst.uv.zw + inst.uv.xy;\n"
        @"  out.normal = float3(dot(inst.normal0.xyz, normal), dot(inst.normal1.xyz, normal), dot(inst.normal2.xyz, normal));\n"
        @"  out.world = world.xyz;\n"
        @"  out.effects = inst.effects;\n"
        @"  out.material = inst.material;\n"
        @"  return out;\n"
        @"}\n"
        @"float3 doof_game_simple_model_batch_light_direction(constant Lighting& lighting) {\n"
        @"  float len = length(lighting.direction.xyz);\n"
        @"  if (len < 0.0001) { return normalize(float3(0.35, 0.60, 0.72)); }\n"
        @"  return lighting.direction.xyz / len;\n"
        @"}\n"
        @"float4 doof_game_apply_simple_model_batch_material(float4 base, float whiteBlend) {\n"
        @"  base.rgb = mix(base.rgb, float3(1.0), clamp(whiteBlend, 0.0, 1.0));\n"
        @"  return base;\n"
        @"}\n"
        @"float4 doof_game_apply_simple_model_batch_light(float4 base, float3 normal, float3 world, float4 effects, float4 material, constant Lighting& lighting) {\n"
        @"  float len = max(length(normal), 0.0001);\n"
        @"  float3 n = normal / len;\n"
        @"  float3 lightDir = doof_game_simple_model_batch_light_direction(lighting);\n"
        @"  float ambient = max(lighting.levels.x, 0.0);\n"
        @"  float directional = max(lighting.levels.y, 0.0);\n"
        @"  float diffuse = max(dot(n, lightDir), 0.0);\n"
        @"  float amount = ambient + directional * diffuse;\n"
        @"  float3 viewDir = normalize(lighting.eye.xyz - world);\n"
        @"  float3 halfDir = normalize(lightDir + viewDir);\n"
        @"  float shininess = max(effects.z, 0.0001);\n"
        @"  float specular = max(effects.y, 0.0) * pow(max(dot(n, halfDir), 0.0), shininess);\n"
        @"  float fresnelPower = max(material.x, 0.0001);\n"
        @"  float fresnel = max(effects.w, 0.0) * pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), fresnelPower);\n"
        @"  return float4(base.rgb * amount + float3(specular + fresnel), base.a);\n"
        @"}\n"
        @"void doof_game_discard_empty_simple_model_batch_alpha(float alpha) {\n"
        @"  if (alpha <= 0.005) { discard_fragment(); }\n"
        @"}\n"
        @"fragment float4 doof_game_simple_model_batch_fragment(VertexOut in [[stage_in]], constant Lighting& lighting [[buffer(0)]]) {\n"
        @"  float4 base = doof_game_apply_simple_model_batch_material(in.color, in.effects.x);\n"
        @"  doof_game_discard_empty_simple_model_batch_alpha(base.a);\n"
        @"  return doof_game_apply_simple_model_batch_light(base, in.normal, in.world, in.effects, in.material, lighting);\n"
        @"}\n"
        @"fragment float4 doof_game_textured_simple_model_batch_fragment(VertexOut in [[stage_in]], constant Lighting& lighting [[buffer(0)]], texture2d<float> tex [[texture(0)]], sampler textureSampler [[sampler(0)]]) {\n"
        @"  float4 sampled = tex.sample(textureSampler, in.uv) * in.color;\n"
        @"  doof_game_discard_empty_simple_model_batch_alpha(sampled.a);\n"
        @"  sampled = doof_game_apply_simple_model_batch_material(sampled, in.effects.x);\n"
        @"  return doof_game_apply_simple_model_batch_light(sampled, in.normal, in.world, in.effects, in.material, lighting);\n"
        @"}\n";

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) {
        return nil;
    }

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"doof_game_simple_model_batch_vertex"];
    if (hasColorAttachment) {
        descriptor.fragmentFunction = [library newFunctionWithName:(textured ? @"doof_game_textured_simple_model_batch_fragment" : @"doof_game_simple_model_batch_fragment")];
        descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    }
    native_mesh::configureDepthAttachment(descriptor, hasDepthAttachment);
    if (hasColorAttachment && blendMode == 1) {
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
    bool hasColorAttachment,
    bool hasDepthAttachment,
    const native_mesh::MatrixUniforms& uniforms,
    const native_mesh::MatrixUniforms& modelUniforms,
    const native_mesh::MatrixUniforms& normalUniforms,
    const SimpleMeshLightingUniforms& lighting,
    const SimpleMeshMaterialUniforms& material
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

    id<MTLRenderPipelineState> pipeline = simpleMeshPipeline(device, blendMode, hasColorAttachment, hasDepthAttachment, textured);
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
    [encoder setVertexBytes:&normalUniforms length:sizeof(normalUniforms) atIndex:3];
    [encoder setVertexBytes:&modelUniforms length:sizeof(modelUniforms) atIndex:4];
    [encoder setFragmentBytes:&lighting length:sizeof(lighting) atIndex:0];
    [encoder setFragmentBytes:&material length:sizeof(material) atIndex:1];
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
    id<MTLRenderPipelineState> pipelines[8] = {};
    bool attempted[8] = {};
    std::string errors[8];

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
        return doof::Failure<std::string>{"Metal device handle is invalid"};
    }

    if (impl_->vertices.empty()) {
        return doof::Failure<std::string>{"Simple mesh has no vertices"};
    }

    if (impl_->indices.empty()) {
        return doof::Failure<std::string>{"Simple mesh has no triangles"};
    }

    if (impl_->indices.size() % 3 != 0) {
        return doof::Failure<std::string>{"Simple mesh index count must be divisible by 3"};
    }

    for (uint32_t index : impl_->indices) {
        if (index >= impl_->vertices.size()) {
            return doof::Failure<std::string>{"Simple mesh triangle index is out of range"};
        }
    }

    id<MTLBuffer> vertexBuffer = [device newBufferWithBytes:impl_->vertices.data()
                                                     length:impl_->vertices.size() * sizeof(SimpleMeshVertex)
                                                    options:MTLResourceStorageModeShared];
    if (vertexBuffer == nil) {
        return doof::Failure<std::string>{"Failed to create simple mesh vertex buffer"};
    }

    id<MTLBuffer> indexBuffer = [device newBufferWithBytes:impl_->indices.data()
                                                    length:impl_->indices.size() * sizeof(uint32_t)
                                                   options:MTLResourceStorageModeShared];
    if (indexBuffer == nil) {
        [vertexBuffer release];
        return doof::Failure<std::string>{"Failed to create simple mesh index buffer"};
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

    return doof::Success<std::shared_ptr<NativeSimpleMesh>>{mesh};
}

doof::Result<std::shared_ptr<NativeSimpleModelBatch>, std::string> NativeSimpleModelBatch::create(int64_t metalDeviceHandle, int32_t capacity) {
    id<MTLDevice> device = native_mesh::bridgeMetalHandle<id<MTLDevice>>(metalDeviceHandle);
    if (device == nil) {
        return doof::Failure<std::string>{"Metal device handle is invalid"};
    }

    if (capacity <= 0) {
        return doof::Failure<std::string>{"Simple model batch capacity must be positive"};
    }

    id<MTLBuffer> instanceBuffer = [device newBufferWithLength:static_cast<NSUInteger>(capacity) * sizeof(SimpleModelInstance)
                                                       options:MTLResourceStorageModeShared];
    if (instanceBuffer == nil) {
        return doof::Failure<std::string>{"Failed to create simple model batch instance buffer"};
    }

    auto batch = std::make_shared<NativeSimpleModelBatch>(
        (__bridge void*)device,
        (__bridge void*)instanceBuffer,
        capacity
    );

    [instanceBuffer release];

    return doof::Success<std::shared_ptr<NativeSimpleModelBatch>>{batch};
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
    double n00,
    double n01,
    double n02,
    double n10,
    double n11,
    double n12,
    double n20,
    double n21,
    double n22,
    double red,
    double green,
    double blue,
    double alpha,
    double whiteBlend,
    double uvOffsetX,
    double uvOffsetY,
    double uvScaleX,
    double uvScaleY,
    double specular,
    double shininess,
    double fresnel,
    double fresnelPower
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
        { static_cast<float>(n00), static_cast<float>(n01), static_cast<float>(n02), 0.0f },
        { static_cast<float>(n10), static_cast<float>(n11), static_cast<float>(n12), 0.0f },
        { static_cast<float>(n20), static_cast<float>(n21), static_cast<float>(n22), 0.0f },
        { static_cast<float>(red), static_cast<float>(green), static_cast<float>(blue), static_cast<float>(alpha) },
        { static_cast<float>(whiteBlend), static_cast<float>(specular), static_cast<float>(shininess), static_cast<float>(fresnel) },
        { static_cast<float>(uvOffsetX), static_cast<float>(uvOffsetY), static_cast<float>(uvScaleX), static_cast<float>(uvScaleY) },
        { static_cast<float>(fresnelPower), 0.0f, 0.0f, 0.0f },
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
        return doof::Failure<std::string>{"Metal device handle is invalid"};
    }

    if (!data || data->empty()) {
        return doof::Failure<std::string>{"Shader buffer data must not be empty"};
    }

    if (data->size() > static_cast<size_t>(INT32_MAX)) {
        return doof::Failure<std::string>{"Shader buffer data is too large"};
    }

    id<MTLBuffer> buffer = [device newBufferWithBytes:data->data()
                                               length:data->size()
                                              options:MTLResourceStorageModeShared];
    if (buffer == nil) {
        return doof::Failure<std::string>{"Failed to create shader buffer"};
    }

    auto shaderBuffer = std::make_shared<NativeShaderBuffer>(
        (__bridge void*)device,
        (__bridge void*)buffer,
        static_cast<int32_t>(data->size())
    );
    [buffer release];
    return doof::Success<std::shared_ptr<NativeShaderBuffer>>{shaderBuffer};
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
        return doof::Failure<std::string>{"Metal device handle is invalid"};
    }
    if (source.empty()) {
        return doof::Failure<std::string>{"Shader source must not be empty"};
    }
    if (vertexFunction.empty()) {
        return doof::Failure<std::string>{"Shader vertex function name must not be empty"};
    }
    if (fragmentFunction.empty()) {
        return doof::Failure<std::string>{"Shader fragment function name must not be empty"};
    }
    if (!attributeIndices || !attributeBuffers || !attributeOffsets || !attributeFormats ||
        attributeIndices->size() != attributeBuffers->size() ||
        attributeIndices->size() != attributeOffsets->size() ||
        attributeIndices->size() != attributeFormats->size()) {
        return doof::Failure<std::string>{"Shader vertex attribute arrays must have matching lengths"};
    }
    if (!layoutBuffers || !layoutStrides || !layoutStepFunctions || !layoutStepRates ||
        layoutBuffers->size() != layoutStrides->size() ||
        layoutBuffers->size() != layoutStepFunctions->size() ||
        layoutBuffers->size() != layoutStepRates->size()) {
        return doof::Failure<std::string>{"Shader vertex layout arrays must have matching lengths"};
    }

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:nsString(source) options:nil error:&error];
    if (library == nil) {
        return doof::Failure<std::string>{errorMessage(error, "Failed to compile shader source")};
    }

    id<MTLFunction> vertex = [library newFunctionWithName:nsString(vertexFunction)];
    if (vertex == nil) {
        [library release];
        return doof::Failure<std::string>{"Shader vertex function was not found: " + vertexFunction};
    }
    [vertex release];

    id<MTLFunction> fragment = [library newFunctionWithName:nsString(fragmentFunction)];
    if (fragment == nil) {
        [library release];
        return doof::Failure<std::string>{"Shader fragment function was not found: " + fragmentFunction};
    }
    [fragment release];

    MTLVertexDescriptor* vertexDescriptor = [[MTLVertexDescriptor alloc] init];
    for (size_t i = 0; i < layoutBuffers->size(); ++i) {
        if ((*layoutBuffers)[i] < 0 || (*layoutStrides)[i] <= 0 || (*layoutStepRates)[i] <= 0) {
            [vertexDescriptor release];
            [library release];
            return doof::Failure<std::string>{"Shader vertex layout buffer index, stride, and step rate must be positive"};
        }
        MTLVertexStepFunction stepFunction = shaderVertexStepFunction((*layoutStepFunctions)[i]);
        if (stepFunction == MTLVertexStepFunctionConstant) {
            [vertexDescriptor release];
            [library release];
            return doof::Failure<std::string>{"Shader vertex layout step function is invalid"};
        }
        vertexDescriptor.layouts[static_cast<NSUInteger>((*layoutBuffers)[i])].stride = static_cast<NSUInteger>((*layoutStrides)[i]);
        vertexDescriptor.layouts[static_cast<NSUInteger>((*layoutBuffers)[i])].stepFunction = stepFunction;
        vertexDescriptor.layouts[static_cast<NSUInteger>((*layoutBuffers)[i])].stepRate = static_cast<NSUInteger>((*layoutStepRates)[i]);
    }

    for (size_t i = 0; i < attributeIndices->size(); ++i) {
        if ((*attributeIndices)[i] < 0 || (*attributeBuffers)[i] < 0 || (*attributeOffsets)[i] < 0) {
            [vertexDescriptor release];
            [library release];
            return doof::Failure<std::string>{"Shader vertex attribute index, buffer, and offset must be non-negative"};
        }
        MTLVertexFormat format = shaderVertexFormat((*attributeFormats)[i]);
        if (format == MTLVertexFormatInvalid) {
            [vertexDescriptor release];
            [library release];
            return doof::Failure<std::string>{"Shader vertex attribute format is invalid"};
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
    return doof::Success<std::shared_ptr<NativeShaderPipeline>>{pipeline};
}

NativeShaderPipeline::NativeShaderPipeline(
    void* device,
    void* library,
    void* vertexDescriptor,
    std::string vertexFunction,
    std::string fragmentFunction
) : impl_(std::make_shared<Impl>(device, library, vertexDescriptor, std::move(vertexFunction), std::move(fragmentFunction))) {}

NativeShaderPipeline::~NativeShaderPipeline() = default;

doof::Result<int64_t, std::string> NativeShaderPipeline::metalPipelineHandle(int32_t blendMode, bool hasColorAttachment, bool hasDepthAttachment) {
    if (impl_->device == nil || impl_->library == nil || impl_->vertexDescriptor == nil) {
        return doof::Failure<std::string>{"Shader pipeline is invalid"};
    }

    int32_t slot = (blendMode == 1 ? 4 : 0) + (hasColorAttachment ? 2 : 0) + (hasDepthAttachment ? 1 : 0);
    if (impl_->pipelines[slot] != nil) {
        return doof::Success<int64_t>{native_mesh::metalHandle(impl_->pipelines[slot])};
    }
    if (impl_->attempted[slot]) {
        return doof::Failure<std::string>{impl_->errors[slot]};
    }
    impl_->attempted[slot] = true;

    id<MTLFunction> vertex = [impl_->library newFunctionWithName:nsString(impl_->vertexFunction)];
    id<MTLFunction> fragment = hasColorAttachment ? [impl_->library newFunctionWithName:nsString(impl_->fragmentFunction)] : nil;
    if (vertex == nil || (hasColorAttachment && fragment == nil)) {
        [fragment release];
        [vertex release];
        impl_->errors[slot] = "Shader functions are no longer available";
        return doof::Failure<std::string>{impl_->errors[slot]};
    }

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertex;
    if (hasColorAttachment) {
        descriptor.fragmentFunction = fragment;
        descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    }
    descriptor.vertexDescriptor = impl_->vertexDescriptor;
    native_mesh::configureDepthAttachment(descriptor, hasDepthAttachment);
    if (hasColorAttachment && blendMode == 1) {
        native_mesh::configureAlphaBlending(descriptor.colorAttachments[0]);
    }

    NSError* error = nil;
    id<MTLRenderPipelineState> pipeline = [impl_->device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    [descriptor release];
    [fragment release];
    [vertex release];

    if (pipeline == nil) {
        impl_->errors[slot] = errorMessage(error, "Failed to create shader render pipeline");
        return doof::Failure<std::string>{impl_->errors[slot]};
    }

    impl_->pipelines[slot] = pipeline;
    return doof::Success<int64_t>{native_mesh::metalHandle(pipeline)};
}

void drawNativeSimpleMesh(
    std::shared_ptr<NativeSimpleMesh> mesh,
    int64_t metalRenderCommandEncoderHandle,
    int64_t metalDeviceHandle,
    int32_t blendMode,
    bool hasColorAttachment,
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
    double modelM00,
    double modelM01,
    double modelM02,
    double modelM03,
    double modelM10,
    double modelM11,
    double modelM12,
    double modelM13,
    double modelM20,
    double modelM21,
    double modelM22,
    double modelM23,
    double modelM30,
    double modelM31,
    double modelM32,
    double modelM33,
    double n00,
    double n01,
    double n02,
    double n10,
    double n11,
    double n12,
    double n20,
    double n21,
    double n22,
    double ambientLight,
    double directionalLight,
    double lightDirectionX,
    double lightDirectionY,
    double lightDirectionZ,
    double eyeX,
    double eyeY,
    double eyeZ,
    double red,
    double green,
    double blue,
    double alpha,
    double whiteBlend,
    double uvOffsetX,
    double uvOffsetY,
    double uvScaleX,
    double uvScaleY,
    double specular,
    double shininess,
    double fresnel,
    double fresnelPower
) {
    drawSimpleMeshInternal(
        mesh,
        0,
        false,
        metalRenderCommandEncoderHandle,
        metalDeviceHandle,
        blendMode,
        hasColorAttachment,
        hasDepthAttachment,
        native_mesh::makeMatrixUniforms(m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33),
        native_mesh::makeMatrixUniforms(modelM00, modelM01, modelM02, modelM03, modelM10, modelM11, modelM12, modelM13, modelM20, modelM21, modelM22, modelM23, modelM30, modelM31, modelM32, modelM33),
        native_mesh::makeNormalMatrixUniforms(n00, n01, n02, n10, n11, n12, n20, n21, n22),
        makeSimpleMeshLightingUniforms(ambientLight, directionalLight, lightDirectionX, lightDirectionY, lightDirectionZ, eyeX, eyeY, eyeZ),
        makeSimpleMeshMaterialUniforms(red, green, blue, alpha, whiteBlend, uvOffsetX, uvOffsetY, uvScaleX, uvScaleY, specular, shininess, fresnel, fresnelPower)
    );
}

void drawNativeTexturedSimpleMesh(
    std::shared_ptr<NativeSimpleMesh> mesh,
    int64_t metalTextureHandle,
    int64_t metalRenderCommandEncoderHandle,
    int64_t metalDeviceHandle,
    int32_t blendMode,
    bool hasColorAttachment,
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
    double modelM00,
    double modelM01,
    double modelM02,
    double modelM03,
    double modelM10,
    double modelM11,
    double modelM12,
    double modelM13,
    double modelM20,
    double modelM21,
    double modelM22,
    double modelM23,
    double modelM30,
    double modelM31,
    double modelM32,
    double modelM33,
    double n00,
    double n01,
    double n02,
    double n10,
    double n11,
    double n12,
    double n20,
    double n21,
    double n22,
    double ambientLight,
    double directionalLight,
    double lightDirectionX,
    double lightDirectionY,
    double lightDirectionZ,
    double eyeX,
    double eyeY,
    double eyeZ,
    double red,
    double green,
    double blue,
    double alpha,
    double whiteBlend,
    double uvOffsetX,
    double uvOffsetY,
    double uvScaleX,
    double uvScaleY,
    double specular,
    double shininess,
    double fresnel,
    double fresnelPower
) {
    drawSimpleMeshInternal(
        mesh,
        metalTextureHandle,
        true,
        metalRenderCommandEncoderHandle,
        metalDeviceHandle,
        blendMode,
        hasColorAttachment,
        hasDepthAttachment,
        native_mesh::makeMatrixUniforms(m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33),
        native_mesh::makeMatrixUniforms(modelM00, modelM01, modelM02, modelM03, modelM10, modelM11, modelM12, modelM13, modelM20, modelM21, modelM22, modelM23, modelM30, modelM31, modelM32, modelM33),
        native_mesh::makeNormalMatrixUniforms(n00, n01, n02, n10, n11, n12, n20, n21, n22),
        makeSimpleMeshLightingUniforms(ambientLight, directionalLight, lightDirectionX, lightDirectionY, lightDirectionZ, eyeX, eyeY, eyeZ),
        makeSimpleMeshMaterialUniforms(red, green, blue, alpha, whiteBlend, uvOffsetX, uvOffsetY, uvScaleX, uvScaleY, specular, shininess, fresnel, fresnelPower)
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
    bool hasColorAttachment,
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
    double lightDirectionZ,
    double eyeX,
    double eyeY,
    double eyeZ
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

    id<MTLRenderPipelineState> pipeline = simpleModelBatchPipeline(device, blendMode, hasColorAttachment, hasDepthAttachment, textured);
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
        lightDirectionZ,
        eyeX,
        eyeY,
        eyeZ
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
    bool hasColorAttachment,
    bool hasDepthAttachment
) {
    if (!pipeline) {
        return doof::Failure<std::string>{"Shader pipeline is required"};
    }

    id<MTLRenderCommandEncoder> encoder = native_mesh::bridgeMetalHandle<id<MTLRenderCommandEncoder>>(metalRenderCommandEncoderHandle);
    if (encoder == nil) {
        return doof::Failure<std::string>{"Metal render command encoder handle is invalid"};
    }

    auto pipelineHandle = pipeline->metalPipelineHandle(blendMode, hasColorAttachment, hasDepthAttachment);
    if (doof::is_failure(pipelineHandle)) {
        return doof::Failure<std::string>{doof::failure_error(pipelineHandle)};
    }
    id<MTLRenderPipelineState> metalPipeline = native_mesh::bridgeMetalHandle<id<MTLRenderPipelineState>>(doof::success_value(pipelineHandle));
    if (metalPipeline == nil) {
        return doof::Failure<std::string>{"Shader pipeline handle is invalid"};
    }

    auto boundVertexBuffers = bindBuffers(encoder, vertexBufferIndices, vertexBufferHandles, vertexBufferOffsets, false);
    if (doof::is_failure(boundVertexBuffers)) {
        return boundVertexBuffers;
    }

    auto boundVertexBytes = bindBuffers(encoder, vertexBytesIndices, vertexBytesHandles, vertexBytesOffsets, false);
    if (doof::is_failure(boundVertexBytes)) {
        return boundVertexBytes;
    }

    auto boundFragmentBytes = bindBuffers(encoder, fragmentBytesIndices, fragmentBytesHandles, fragmentBytesOffsets, true);
    if (doof::is_failure(boundFragmentBytes)) {
        return boundFragmentBytes;
    }

    id<MTLDevice> device = metalPipeline.device;
    auto boundTextures = bindTextures(encoder, device, fragmentTextureIndices, fragmentTextureHandles);
    if (doof::is_failure(boundTextures)) {
        return boundTextures;
    }

    [encoder setRenderPipelineState:metalPipeline];

    if (indexCount > 0) {
        if (instanceCount <= 0) {
            return doof::Failure<std::string>{"Shader instance count must be positive"};
        }
        id<MTLBuffer> indexBuffer = native_mesh::bridgeMetalHandle<id<MTLBuffer>>(indexBufferHandle);
        if (indexBuffer == nil) {
            return doof::Failure<std::string>{"Shader index buffer handle is invalid"};
        }
        [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                            indexCount:static_cast<NSUInteger>(indexCount)
                             indexType:MTLIndexTypeUInt32
                           indexBuffer:indexBuffer
                     indexBufferOffset:0
                         instanceCount:static_cast<NSUInteger>(instanceCount)];
    } else {
        if (vertexCount <= 0) {
            return doof::Failure<std::string>{"Shader vertex count must be positive for non-indexed draws"};
        }
        if (instanceCount <= 0) {
            return doof::Failure<std::string>{"Shader instance count must be positive"};
        }
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                    vertexStart:0
                    vertexCount:static_cast<NSUInteger>(vertexCount)
                  instanceCount:static_cast<NSUInteger>(instanceCount)];
    }

    return doof::Success<void>{};
}

}  // namespace doof_game
