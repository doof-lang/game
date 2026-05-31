#include "native_mesh_internal.hpp"

#include <cmath>

namespace doof_game {
namespace {

struct SkyMapUniforms {
    float pixelWidth;
    float pixelHeight;
    float tanHalfFovY;
    float exposure;
    float rotationM00;
    float rotationM01;
    float rotationM02;
    float rotationM10;
    float rotationM11;
    float rotationM12;
    float rotationM20;
    float rotationM21;
    float rotationM22;
    float pad0;
    float pad1;
    float pad2;
};

id<MTLRenderPipelineState> skyMapPipeline(id<MTLDevice> device, bool hasDepthAttachment) {
    if (device == nil) {
        return nil;
    }

    static id<MTLRenderPipelineState> pipelines[2] = {};
    static bool attempted[2] = {};
    int32_t slot = hasDepthAttachment ? 1 : 0;
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
        @"constant float DOOF_GAME_PI = 3.14159265358979323846;\n"
        @"struct Uniforms { float pixelWidth; float pixelHeight; float tanHalfFovY; float exposure; float rotationM00; float rotationM01; float rotationM02; float rotationM10; float rotationM11; float rotationM12; float rotationM20; float rotationM21; float rotationM22; float pad0; float pad1; float pad2; };\n"
        @"struct VertexOut { float4 position [[position]]; float2 ndc; };\n"
        @"vertex VertexOut doof_game_sky_map_vertex(uint vertexId [[vertex_id]]) {\n"
        @"  float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };\n"
        @"  VertexOut out;\n"
        @"  out.position = float4(positions[vertexId], 1.0, 1.0);\n"
        @"  out.ndc = positions[vertexId];\n"
        @"  return out;\n"
        @"}\n"
        @"fragment float4 doof_game_sky_map_fragment(VertexOut in [[stage_in]], constant Uniforms& uniforms [[buffer(0)]], texture2d<float> tex [[texture(0)]], sampler textureSampler [[sampler(0)]]) {\n"
        @"  float aspect = max(uniforms.pixelWidth, 1.0) / max(uniforms.pixelHeight, 1.0);\n"
        @"  float3 localDir = normalize(float3(in.ndc.x * aspect * uniforms.tanHalfFovY, in.ndc.y * uniforms.tanHalfFovY, -1.0));\n"
        @"  float3 dir = normalize(float3(\n"
        @"    uniforms.rotationM00 * localDir.x + uniforms.rotationM01 * localDir.y + uniforms.rotationM02 * localDir.z,\n"
        @"    uniforms.rotationM10 * localDir.x + uniforms.rotationM11 * localDir.y + uniforms.rotationM12 * localDir.z,\n"
        @"    uniforms.rotationM20 * localDir.x + uniforms.rotationM21 * localDir.y + uniforms.rotationM22 * localDir.z));\n"
        @"  float u = atan2(dir.x, -dir.z) / (2.0 * DOOF_GAME_PI) + 0.5;\n"
        @"  float v = 0.5 - asin(clamp(dir.y, -1.0, 1.0)) / DOOF_GAME_PI;\n"
        @"  float4 color = tex.sample(textureSampler, float2(fract(u), clamp(v, 0.0, 1.0)));\n"
        @"  return float4(color.rgb * uniforms.exposure, color.a);\n"
        @"}\n";

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) {
        return nil;
    }

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"doof_game_sky_map_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"doof_game_sky_map_fragment"];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    native_mesh::configureDepthAttachment(descriptor, hasDepthAttachment);

    id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    [descriptor.vertexFunction release];
    [descriptor.fragmentFunction release];
    [descriptor release];
    [library release];
    pipelines[slot] = pipeline;
    return pipelines[slot];
}

}  // namespace

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
) {
    id<MTLTexture> texture = native_mesh::bridgeMetalHandle<id<MTLTexture>>(metalTextureHandle);
    id<MTLRenderCommandEncoder> encoder = native_mesh::bridgeMetalHandle<id<MTLRenderCommandEncoder>>(metalRenderCommandEncoderHandle);
    id<MTLDevice> device = native_mesh::bridgeMetalHandle<id<MTLDevice>>(metalDeviceHandle);
    if (texture == nil || encoder == nil || device == nil) {
        return;
    }

    id<MTLRenderPipelineState> pipeline = skyMapPipeline(device, hasDepthAttachment);
    id<MTLSamplerState> sampler = native_mesh::linearSampler(device, MTLSamplerAddressModeRepeat);
    if (pipeline == nil || sampler == nil) {
        return;
    }

    SkyMapUniforms uniforms {
        static_cast<float>(pixelWidth),
        static_cast<float>(pixelHeight),
        static_cast<float>(std::tan(fovYRadians * 0.5)),
        static_cast<float>(exposure),
        static_cast<float>(rotationM00),
        static_cast<float>(rotationM01),
        static_cast<float>(rotationM02),
        static_cast<float>(rotationM10),
        static_cast<float>(rotationM11),
        static_cast<float>(rotationM12),
        static_cast<float>(rotationM20),
        static_cast<float>(rotationM21),
        static_cast<float>(rotationM22),
        0.0f,
        0.0f,
        0.0f,
    };

    [encoder setRenderPipelineState:pipeline];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder setFragmentTexture:texture atIndex:0];
    [encoder setFragmentSamplerState:sampler atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
}

}  // namespace doof_game
