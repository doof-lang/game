#include "native_mesh_internal.hpp"

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

namespace doof_game {
namespace {

using native_mesh::SpaceDustParticle;

struct SpaceDustUniforms {
    float row0[4];
    float row1[4];
    float row2[4];
    float row3[4];
    float camera[4];
    float color[4];
    float fieldSize;
    float particleSize;
    float fadeStart;
    float fadeEnd;
    float opacity;
    float pixelScale;
    float pad0;
    float pad1;
};

id<MTLRenderPipelineState> spaceDustPipeline(id<MTLDevice> device, bool hasDepthAttachment) {
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
        @"struct Particle { packed_float3 position; float brightness; };\n"
        @"struct Uniforms { float4 row0; float4 row1; float4 row2; float4 row3; float4 camera; float4 color; float fieldSize; float particleSize; float fadeStart; float fadeEnd; float opacity; float pixelScale; float pad0; float pad1; };\n"
        @"struct VertexOut { float4 position [[position]]; float4 color; float pointSize [[point_size]]; };\n"
        @"float doof_game_wrap_axis(float value, float camera, float fieldSize) {\n"
        @"  float relative = value - camera;\n"
        @"  return (fract(relative / fieldSize + 0.5) - 0.5) * fieldSize + camera;\n"
        @"}\n"
        @"vertex VertexOut doof_game_space_dust_vertex(const device Particle* particles [[buffer(0)]], constant Uniforms& uniforms [[buffer(1)]], uint vertexId [[vertex_id]]) {\n"
        @"  Particle particle = particles[vertexId];\n"
        @"  float fieldSize = max(uniforms.fieldSize, 0.001);\n"
        @"  float3 world = float3(\n"
        @"    doof_game_wrap_axis(particle.position.x, uniforms.camera.x, fieldSize),\n"
        @"    doof_game_wrap_axis(particle.position.y, uniforms.camera.y, fieldSize),\n"
        @"    doof_game_wrap_axis(particle.position.z, uniforms.camera.z, fieldSize));\n"
        @"  float distanceToCamera = length(world - uniforms.camera.xyz);\n"
        @"  float fadeSpan = max(uniforms.fadeEnd - uniforms.fadeStart, 0.001);\n"
        @"  float alpha = uniforms.opacity * particle.brightness * clamp((uniforms.fadeEnd - distanceToCamera) / fadeSpan, 0.0, 1.0);\n"
        @"  float4 p = float4(world, 1.0);\n"
        @"  VertexOut out;\n"
        @"  out.position = float4(dot(uniforms.row0, p), dot(uniforms.row1, p), dot(uniforms.row2, p), dot(uniforms.row3, p));\n"
        @"  out.color = float4(uniforms.color.rgb, alpha);\n"
        @"  out.pointSize = max(uniforms.particleSize * uniforms.pixelScale * particle.brightness, 1.0);\n"
        @"  return out;\n"
        @"}\n"
        @"fragment float4 doof_game_space_dust_fragment(VertexOut in [[stage_in]], float2 pointCoord [[point_coord]]) {\n"
        @"  float2 delta = pointCoord - float2(0.5, 0.5);\n"
        @"  float core = 1.0 - smoothstep(0.12, 0.5, length(delta));\n"
        @"  return float4(in.color.rgb, in.color.a * core);\n"
        @"}\n";

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) {
        return nil;
    }

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"doof_game_space_dust_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"doof_game_space_dust_fragment"];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    native_mesh::configureAlphaBlending(descriptor.colorAttachments[0]);
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

struct NativeSpaceDust::Impl {
    id<MTLDevice> device = nil;
    id<MTLBuffer> particleBuffer = nil;
    int32_t particleCount = 0;

    Impl(void* rawDevice, void* rawParticleBuffer, int32_t particleCount)
        : device((__bridge id<MTLDevice>)rawDevice),
          particleBuffer((__bridge id<MTLBuffer>)rawParticleBuffer),
          particleCount(particleCount) {
        [device retain];
        [particleBuffer retain];
    }

    ~Impl() {
        [particleBuffer release];
        [device release];
    }
};

struct NativeSpaceDustBuilder::Impl {
    std::vector<SpaceDustParticle> particles;
};

NativeSpaceDust::NativeSpaceDust(void* device, void* particleBuffer, int32_t particleCount)
    : impl_(std::make_shared<Impl>(device, particleBuffer, particleCount)) {}

NativeSpaceDust::~NativeSpaceDust() = default;

int32_t NativeSpaceDust::particleCount() const {
    return impl_->particleCount;
}

int64_t NativeSpaceDust::metalDeviceHandle() const {
    return native_mesh::metalHandle(impl_->device);
}

int64_t NativeSpaceDust::metalParticleBufferHandle() const {
    return native_mesh::metalHandle(impl_->particleBuffer);
}

std::shared_ptr<NativeSpaceDustBuilder> NativeSpaceDustBuilder::create() {
    return std::make_shared<NativeSpaceDustBuilder>();
}

NativeSpaceDustBuilder::NativeSpaceDustBuilder()
    : impl_(std::make_shared<Impl>()) {}

NativeSpaceDustBuilder::~NativeSpaceDustBuilder() = default;

std::shared_ptr<NativeSpaceDustBuilder> NativeSpaceDustBuilder::addParticle(double x, double y, double z, double brightness) {
    impl_->particles.push_back(SpaceDustParticle {
        static_cast<float>(x),
        static_cast<float>(y),
        static_cast<float>(z),
        static_cast<float>(brightness),
    });
    return shared_from_this();
}

doof::Result<std::shared_ptr<NativeSpaceDust>, std::string> NativeSpaceDustBuilder::build(int64_t metalDeviceHandle) {
    id<MTLDevice> device = native_mesh::bridgeMetalHandle<id<MTLDevice>>(metalDeviceHandle);
    if (device == nil) {
        return doof::Result<std::shared_ptr<NativeSpaceDust>, std::string>::failure("Metal device handle is invalid");
    }

    if (impl_->particles.empty()) {
        return doof::Result<std::shared_ptr<NativeSpaceDust>, std::string>::failure("Space dust has no particles");
    }

    id<MTLBuffer> particleBuffer = [device newBufferWithBytes:impl_->particles.data()
                                                       length:impl_->particles.size() * sizeof(SpaceDustParticle)
                                                      options:MTLResourceStorageModeShared];
    if (particleBuffer == nil) {
        return doof::Result<std::shared_ptr<NativeSpaceDust>, std::string>::failure("Failed to create space dust particle buffer");
    }

    auto dust = std::make_shared<NativeSpaceDust>(
        (__bridge void*)device,
        (__bridge void*)particleBuffer,
        static_cast<int32_t>(impl_->particles.size())
    );

    [particleBuffer release];
    return doof::Result<std::shared_ptr<NativeSpaceDust>, std::string>::success(dust);
}

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
) {
    if (!dust || dust->particleCount() <= 0) {
        return;
    }

    id<MTLRenderCommandEncoder> encoder = native_mesh::bridgeMetalHandle<id<MTLRenderCommandEncoder>>(metalRenderCommandEncoderHandle);
    id<MTLDevice> device = native_mesh::bridgeMetalHandle<id<MTLDevice>>(metalDeviceHandle);
    id<MTLBuffer> particleBuffer = native_mesh::bridgeMetalHandle<id<MTLBuffer>>(dust->metalParticleBufferHandle());
    if (encoder == nil || device == nil || particleBuffer == nil) {
        return;
    }

    id<MTLRenderPipelineState> pipeline = spaceDustPipeline(device, hasDepthAttachment);
    if (pipeline == nil) {
        return;
    }

    const double heightScale = static_cast<double>(std::max(pixelHeight, 1)) / 720.0;
    native_mesh::MatrixUniforms matrix = native_mesh::makeMatrixUniforms(
        m00, m01, m02, m03,
        m10, m11, m12, m13,
        m20, m21, m22, m23,
        m30, m31, m32, m33
    );
    SpaceDustUniforms uniforms {
        { matrix.row0[0], matrix.row0[1], matrix.row0[2], matrix.row0[3] },
        { matrix.row1[0], matrix.row1[1], matrix.row1[2], matrix.row1[3] },
        { matrix.row2[0], matrix.row2[1], matrix.row2[2], matrix.row2[3] },
        { matrix.row3[0], matrix.row3[1], matrix.row3[2], matrix.row3[3] },
        { static_cast<float>(cameraX), static_cast<float>(cameraY), static_cast<float>(cameraZ), 0.0f },
        { static_cast<float>(red), static_cast<float>(green), static_cast<float>(blue), 1.0f },
        static_cast<float>(fieldSize),
        static_cast<float>(particleSize),
        static_cast<float>(fadeStart),
        static_cast<float>(fadeEnd),
        static_cast<float>(opacity),
        static_cast<float>(heightScale),
        0.0f,
        0.0f,
    };

    [encoder setRenderPipelineState:pipeline];
    [encoder setVertexBuffer:particleBuffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypePoint
                vertexStart:0
                vertexCount:static_cast<NSUInteger>(dust->particleCount())];
}

}  // namespace doof_game
