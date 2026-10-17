#include "native_mesh.hpp"

#define NOMINMAX
#include <d3d11_1.h>
#include <d3dcompiler.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <unordered_map>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace doof_game {
namespace {
template <typename T> int64_t handle(T* value) { return reinterpret_cast<int64_t>(value); }
struct Vertex { float position[3], color[4], uv[2], normal[3]; };
struct Particle { float position[3], brightness; };
struct Instance { float model[16], normal[12], color[4], whiteBlend, uvOffset[2], uvScale[2], specular, shininess, fresnel, fresnelPower; };
static_assert(sizeof(Instance) == 164 && offsetof(Instance, normal) == 64 &&
    offsetof(Instance, color) == 112 && offsetof(Instance, whiteBlend) == 128 &&
    offsetof(Instance, uvOffset) == 132 && offsetof(Instance, uvScale) == 140 &&
    offsetof(Instance, specular) == 148, "D3D11 model instance layout changed");
template <typename T> doof::Result<ComPtr<ID3D11Buffer>, std::string> immutableBuffer(ID3D11Device* device, const std::vector<T>& values, UINT bind) {
    if (!device || values.empty()) return doof::Failure<std::string>{"Cannot create an empty D3D11 buffer"};
    D3D11_BUFFER_DESC desc{}; desc.ByteWidth = static_cast<UINT>(values.size() * sizeof(T)); desc.Usage = D3D11_USAGE_IMMUTABLE; desc.BindFlags = bind;
    D3D11_SUBRESOURCE_DATA data{}; data.pSysMem = values.data(); ComPtr<ID3D11Buffer> buffer;
    if (FAILED(device->CreateBuffer(&desc, &data, &buffer))) return doof::Failure<std::string>{"Failed to create D3D11 buffer"};
    return doof::Success<ComPtr<ID3D11Buffer>>{buffer};
}

struct MeshConstants {
    float viewProjection[16];
    float model[16];
    float normal[12];
    float lightDirection[4];
    float lightLevels[4];
    float eye[4];
    float tint[4];
    float effects[4];
    float uv[4];
    float material[4];
};

struct MeshPipeline {
    ComPtr<ID3D11VertexShader> vertex;
    ComPtr<ID3D11PixelShader> colorFragment;
    ComPtr<ID3D11PixelShader> textureFragment;
    ComPtr<ID3D11InputLayout> layout;
    ComPtr<ID3D11Buffer> constants;
    ComPtr<ID3D11SamplerState> sampler;
    ComPtr<ID3D11BlendState> alphaBlend;
};

struct SkyMapConstants {
    float pixelWidth, pixelHeight, tanHalfFovY, exposure;
    float rotation[12];
};

struct SkyMapPipeline {
    ComPtr<ID3D11VertexShader> vertex;
    ComPtr<ID3D11PixelShader> fragment;
    ComPtr<ID3D11Buffer> constants;
    ComPtr<ID3D11SamplerState> sampler;
};

struct SpaceDustConstants {
    float matrix[16];
    float camera[4];
    float color[4];
    float fieldSize, particleSize, fadeStart, fadeEnd;
    float opacity, pixelScale, pixelWidth, pixelHeight;
};

struct SpaceDustPipeline {
    ComPtr<ID3D11VertexShader> vertex;
    ComPtr<ID3D11GeometryShader> geometry;
    ComPtr<ID3D11PixelShader> fragment;
    ComPtr<ID3D11InputLayout> layout;
    ComPtr<ID3D11Buffer> constants;
    ComPtr<ID3D11BlendState> alphaBlend;
};

struct ModelBatchPipeline {
    ComPtr<ID3D11VertexShader> vertex;
    ComPtr<ID3D11PixelShader> colorFragment;
    ComPtr<ID3D11PixelShader> textureFragment;
    ComPtr<ID3D11InputLayout> layout;
    ComPtr<ID3D11Buffer> constants;
    ComPtr<ID3D11SamplerState> sampler;
    ComPtr<ID3D11BlendState> alphaBlend;
};

struct ModelBatchConstants {
    float matrix[16];
    float lightDirection[4];
    float lightLevels[4];
    float eye[4];
};

std::mutex pipelineMutex;
std::unordered_map<ID3D11Device*, std::shared_ptr<MeshPipeline>> pipelines;
std::unordered_map<ID3D11Device*, std::shared_ptr<SkyMapPipeline>> skyMapPipelines;
std::unordered_map<ID3D11Device*, std::shared_ptr<SpaceDustPipeline>> spaceDustPipelines;
std::unordered_map<ID3D11Device*, std::shared_ptr<ModelBatchPipeline>> modelBatchPipelines;

ComPtr<ID3DBlob> compileShader(const char* source, const char* entry, const char* target) {
    ComPtr<ID3DBlob> code, errors;
    if (FAILED(D3DCompile(source, std::strlen(source), "std/game built-in", nullptr, nullptr,
        entry, target, D3DCOMPILE_ENABLE_STRICTNESS, 0, &code, &errors))) {
        if (errors) {
            std::fwrite(errors->GetBufferPointer(), 1, errors->GetBufferSize(), stderr);
            OutputDebugStringA(static_cast<const char*>(errors->GetBufferPointer()));
        }
        return {};
    }
    return code;
}

template <typename T>
bool createDynamicConstants(ID3D11Device* device, ComPtr<ID3D11Buffer>& buffer) {
    D3D11_BUFFER_DESC desc{};
    desc.ByteWidth = (sizeof(T) + 15u) & ~15u;
    desc.Usage = D3D11_USAGE_DYNAMIC;
    desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    return SUCCEEDED(device->CreateBuffer(&desc, nullptr, &buffer));
}

template <typename T>
bool updateConstants(ID3D11DeviceContext* context, ID3D11Buffer* buffer, const T& values) {
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (!context || !buffer || FAILED(context->Map(buffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) return false;
    std::memcpy(mapped.pData, &values, sizeof(values));
    context->Unmap(buffer, 0);
    return true;
}

void configureAlphaBlend(ID3D11Device* device, ComPtr<ID3D11BlendState>& state) {
    D3D11_BLEND_DESC blend{};
    blend.RenderTarget[0].BlendEnable = TRUE;
    blend.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC_ALPHA;
    blend.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
    blend.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
    blend.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_SRC_ALPHA;
    blend.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
    blend.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
    blend.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
    device->CreateBlendState(&blend, &state);
}

std::shared_ptr<SkyMapPipeline> skyMapPipeline(ID3D11Device* device) {
    std::lock_guard<std::mutex> lock(pipelineMutex);
    auto found = skyMapPipelines.find(device); if (found != skyMapPipelines.end()) return found->second;
    static const char* shader = R"(
cbuffer SkyMapConstants : register(b0) {
  float pixelWidth; float pixelHeight; float tanHalfFovY; float exposure;
  float3 rotation0; float rotationPad0;
  float3 rotation1; float rotationPad1;
  float3 rotation2; float rotationPad2;
};
struct VertexOut { float4 position : SV_POSITION; float2 ndc : TEXCOORD0; };
VertexOut vertexMain(uint vertexId : SV_VertexID) {
  float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
  VertexOut output; output.position = float4(positions[vertexId], 1.0, 1.0); output.ndc = positions[vertexId]; return output;
}
Texture2D texture0 : register(t0); SamplerState sampler0 : register(s0);
float4 fragmentMain(VertexOut input) : SV_TARGET {
  float aspect = max(pixelWidth, 1.0) / max(pixelHeight, 1.0);
  float3 localDir = normalize(float3(input.ndc.x * aspect * tanHalfFovY, input.ndc.y * tanHalfFovY, -1.0));
  float3 dir = normalize(float3(dot(rotation0, localDir), dot(rotation1, localDir), dot(rotation2, localDir)));
  float u = atan2(dir.x, -dir.z) / 6.28318530718 + 0.5;
  float v = 0.5 - asin(clamp(dir.y, -1.0, 1.0)) / 3.14159265359;
  float4 color = texture0.Sample(sampler0, float2(frac(u), clamp(v, 0.0, 1.0)));
  return float4(color.rgb * exposure, color.a);
}
)";
    auto vs = compileShader(shader, "vertexMain", "vs_5_0"), ps = compileShader(shader, "fragmentMain", "ps_5_0");
    if (!vs || !ps) return {};
    auto result = std::make_shared<SkyMapPipeline>();
    if (FAILED(device->CreateVertexShader(vs->GetBufferPointer(), vs->GetBufferSize(), nullptr, &result->vertex)) ||
        FAILED(device->CreatePixelShader(ps->GetBufferPointer(), ps->GetBufferSize(), nullptr, &result->fragment)) ||
        !createDynamicConstants<SkyMapConstants>(device, result->constants)) return {};
    D3D11_SAMPLER_DESC sampler{}; sampler.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    sampler.AddressU = D3D11_TEXTURE_ADDRESS_WRAP; sampler.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampler.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP; sampler.MaxLOD = D3D11_FLOAT32_MAX;
    if (FAILED(device->CreateSamplerState(&sampler, &result->sampler))) return {};
    skyMapPipelines[device] = result; return result;
}

std::shared_ptr<SpaceDustPipeline> spaceDustPipeline(ID3D11Device* device) {
    std::lock_guard<std::mutex> lock(pipelineMutex);
    auto found = spaceDustPipelines.find(device); if (found != spaceDustPipelines.end()) return found->second;
    static const char* shader = R"(
cbuffer DustConstants : register(b0) {
  row_major float4x4 transformMatrix; float4 camera; float4 dustColor;
  float fieldSize; float particleSize; float fadeStart; float fadeEnd;
  float opacity; float pixelScale; float pixelWidth; float pixelHeight;
};
struct VertexIn { float3 position : POSITION; float brightness : BRIGHTNESS; };
struct VertexOut { float4 position : SV_POSITION; float4 color : COLOR0; float size : SIZE0; };
float wrapAxis(float value, float center, float size) {
  float relative = value - center; return (frac(relative / size + 0.5) - 0.5) * size + center;
}
VertexOut vertexMain(VertexIn input) {
  float size = max(fieldSize, 0.001);
  float3 world = float3(wrapAxis(input.position.x, camera.x, size), wrapAxis(input.position.y, camera.y, size), wrapAxis(input.position.z, camera.z, size));
  float distanceToCamera = length(world - camera.xyz); float fadeSpan = max(fadeEnd - fadeStart, 0.001);
  VertexOut output; output.position = mul(transformMatrix, float4(world, 1.0));
  output.color = float4(dustColor.rgb, opacity * input.brightness * saturate((fadeEnd - distanceToCamera) / fadeSpan));
  output.size = max(particleSize * pixelScale * input.brightness, 1.0); return output;
}
struct PixelIn { float4 position : SV_POSITION; float4 color : COLOR0; float2 pointCoord : TEXCOORD0; };
[maxvertexcount(4)] void geometryMain(point VertexOut input[1], inout TriangleStream<PixelIn> stream) {
  float2 clip = float2(input[0].size / max(pixelWidth, 1.0), input[0].size / max(pixelHeight, 1.0)) * input[0].position.w;
  float2 corners[4] = { float2(-1.0, -1.0), float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0) };
  float2 coords[4] = { float2(0.0, 1.0), float2(0.0, 0.0), float2(1.0, 1.0), float2(1.0, 0.0) };
  [unroll] for (uint i = 0; i < 4; ++i) { PixelIn output; output.position = input[0].position; output.position.xy += corners[i] * clip; output.color = input[0].color; output.pointCoord = coords[i]; stream.Append(output); }
}
float4 fragmentMain(PixelIn input) : SV_TARGET {
  float core = 1.0 - smoothstep(0.12, 0.5, length(input.pointCoord - float2(0.5, 0.5)));
  return float4(input.color.rgb, input.color.a * core);
}
)";
    auto vs = compileShader(shader, "vertexMain", "vs_5_0"), gs = compileShader(shader, "geometryMain", "gs_5_0"), ps = compileShader(shader, "fragmentMain", "ps_5_0");
    if (!vs || !gs || !ps) return {};
    auto result = std::make_shared<SpaceDustPipeline>();
    if (FAILED(device->CreateVertexShader(vs->GetBufferPointer(), vs->GetBufferSize(), nullptr, &result->vertex)) ||
        FAILED(device->CreateGeometryShader(gs->GetBufferPointer(), gs->GetBufferSize(), nullptr, &result->geometry)) ||
        FAILED(device->CreatePixelShader(ps->GetBufferPointer(), ps->GetBufferSize(), nullptr, &result->fragment))) return {};
    D3D11_INPUT_ELEMENT_DESC elements[] = {
        {"POSITION",0,DXGI_FORMAT_R32G32B32_FLOAT,0,0,D3D11_INPUT_PER_VERTEX_DATA,0},
        {"BRIGHTNESS",0,DXGI_FORMAT_R32_FLOAT,0,12,D3D11_INPUT_PER_VERTEX_DATA,0},
    };
    if (FAILED(device->CreateInputLayout(elements, 2, vs->GetBufferPointer(), vs->GetBufferSize(), &result->layout)) ||
        !createDynamicConstants<SpaceDustConstants>(device, result->constants)) return {};
    configureAlphaBlend(device, result->alphaBlend);
    spaceDustPipelines[device] = result; return result;
}

std::shared_ptr<MeshPipeline> meshPipeline(ID3D11Device* device) {
    std::lock_guard<std::mutex> lock(pipelineMutex);
    auto found = pipelines.find(device); if (found != pipelines.end()) return found->second;
    static const char* shader = R"(
cbuffer MeshConstants : register(b0) {
  row_major float4x4 viewProjection; row_major float4x4 model;
  float4 normal0; float4 normal1; float4 normal2;
  float4 lightDirection; float4 lightLevels; float4 eye; float4 tint;
  float4 effects; float4 uvTransform; float4 material;
};
struct VertexIn { float3 position : POSITION; float4 color : COLOR; float2 uv : TEXCOORD; float3 normal : NORMAL; };
struct VertexOut { float4 position : SV_POSITION; float4 color : COLOR; float2 uv : TEXCOORD; float3 normal : NORMAL; float3 world : TEXCOORD1; };
VertexOut vertexMain(VertexIn input) {
  VertexOut output; float4 world = mul(model, float4(input.position, 1.0));
  output.position = mul(viewProjection, world); output.color = input.color;
  output.uv = input.uv * uvTransform.zw + uvTransform.xy;
  output.normal = float3(dot(normal0.xyz, input.normal), dot(normal1.xyz, input.normal), dot(normal2.xyz, input.normal));
  output.world = world.xyz;
  return output;
}
Texture2D texture0 : register(t0); SamplerState sampler0 : register(s0);
float4 applyLight(VertexOut input, float4 base) {
  base *= tint; base.rgb = lerp(base.rgb, float3(1.0, 1.0, 1.0), saturate(effects.x)); clip(base.a - 0.005);
  float3 n = normalize(input.normal);
  float3 lightDir = length(lightDirection.xyz) < 0.0001 ? normalize(float3(0.35, 0.60, 0.72)) : normalize(lightDirection.xyz);
  float amount = max(lightLevels.x, 0.0) + max(lightLevels.y, 0.0) * max(dot(n, lightDir), 0.0);
  float3 viewDir = normalize(eye.xyz - input.world); float3 halfDir = normalize(lightDir + viewDir);
  float specular = max(effects.y, 0.0) * pow(max(dot(n, halfDir), 0.0), max(effects.z, 0.0001));
  float fresnel = max(effects.w, 0.0) * pow(1.0 - saturate(dot(n, viewDir)), max(material.x, 0.0001));
  return float4(base.rgb * amount + specular + fresnel, base.a);
}
float4 colorMain(VertexOut input) : SV_TARGET { return applyLight(input, input.color); }
float4 textureMain(VertexOut input) : SV_TARGET { return applyLight(input, texture0.Sample(sampler0, input.uv) * input.color); }
)";
    auto vs = compileShader(shader,"vertexMain","vs_5_0"), ps = compileShader(shader,"colorMain","ps_5_0"), pts = compileShader(shader,"textureMain","ps_5_0");
    if (!vs || !ps || !pts) return {};
    auto result = std::make_shared<MeshPipeline>();
    if (FAILED(device->CreateVertexShader(vs->GetBufferPointer(),vs->GetBufferSize(),nullptr,&result->vertex)) ||
        FAILED(device->CreatePixelShader(ps->GetBufferPointer(),ps->GetBufferSize(),nullptr,&result->colorFragment)) ||
        FAILED(device->CreatePixelShader(pts->GetBufferPointer(),pts->GetBufferSize(),nullptr,&result->textureFragment))) return {};
    D3D11_INPUT_ELEMENT_DESC elements[] = {
        {"POSITION",0,DXGI_FORMAT_R32G32B32_FLOAT,0,0,D3D11_INPUT_PER_VERTEX_DATA,0},
        {"COLOR",0,DXGI_FORMAT_R32G32B32A32_FLOAT,0,12,D3D11_INPUT_PER_VERTEX_DATA,0},
        {"TEXCOORD",0,DXGI_FORMAT_R32G32_FLOAT,0,28,D3D11_INPUT_PER_VERTEX_DATA,0},
        {"NORMAL",0,DXGI_FORMAT_R32G32B32_FLOAT,0,36,D3D11_INPUT_PER_VERTEX_DATA,0},
    };
    if (FAILED(device->CreateInputLayout(elements,4,vs->GetBufferPointer(),vs->GetBufferSize(),&result->layout))) return {};
    D3D11_BUFFER_DESC cb{}; cb.ByteWidth=sizeof(MeshConstants); cb.Usage=D3D11_USAGE_DYNAMIC; cb.BindFlags=D3D11_BIND_CONSTANT_BUFFER; cb.CPUAccessFlags=D3D11_CPU_ACCESS_WRITE;
    if (FAILED(device->CreateBuffer(&cb,nullptr,&result->constants))) return {};
    D3D11_SAMPLER_DESC sampler{}; sampler.Filter=D3D11_FILTER_MIN_MAG_MIP_LINEAR; sampler.AddressU=D3D11_TEXTURE_ADDRESS_WRAP; sampler.AddressV=D3D11_TEXTURE_ADDRESS_WRAP; sampler.AddressW=D3D11_TEXTURE_ADDRESS_WRAP; sampler.MaxLOD=D3D11_FLOAT32_MAX;
    device->CreateSamplerState(&sampler,&result->sampler);
    D3D11_BLEND_DESC blend{}; blend.RenderTarget[0].BlendEnable=TRUE; blend.RenderTarget[0].SrcBlend=D3D11_BLEND_SRC_ALPHA; blend.RenderTarget[0].DestBlend=D3D11_BLEND_INV_SRC_ALPHA; blend.RenderTarget[0].BlendOp=D3D11_BLEND_OP_ADD; blend.RenderTarget[0].SrcBlendAlpha=D3D11_BLEND_SRC_ALPHA; blend.RenderTarget[0].DestBlendAlpha=D3D11_BLEND_INV_SRC_ALPHA; blend.RenderTarget[0].BlendOpAlpha=D3D11_BLEND_OP_ADD; blend.RenderTarget[0].RenderTargetWriteMask=D3D11_COLOR_WRITE_ENABLE_ALL;
    device->CreateBlendState(&blend,&result->alphaBlend); pipelines[device]=result; return result;
}

std::shared_ptr<ModelBatchPipeline> modelBatchPipeline(ID3D11Device* device) {
    std::lock_guard<std::mutex> lock(pipelineMutex);
    auto found = modelBatchPipelines.find(device); if (found != modelBatchPipelines.end()) return found->second;
    static const char* shader = R"(
cbuffer BatchConstants : register(b0) {
  row_major float4x4 viewProjection; float4 lightDirection; float4 lightLevels; float4 eye;
};
Texture2D texture0 : register(t0); SamplerState sampler0 : register(s0);
struct VertexIn {
  float3 position : POSITION; float4 color : COLOR; float2 uv : TEXCOORD; float3 normal : NORMAL;
  float4 model0 : INSTANCE_MODEL0; float4 model1 : INSTANCE_MODEL1; float4 model2 : INSTANCE_MODEL2; float4 model3 : INSTANCE_MODEL3;
  float3 normal0 : INSTANCE_NORMAL0; float3 normal1 : INSTANCE_NORMAL1; float3 normal2 : INSTANCE_NORMAL2;
  float4 tint : INSTANCE_COLOR; float whiteBlend : INSTANCE_WHITE; float2 uvOffset : INSTANCE_UVOFFSET;
  float2 uvScale : INSTANCE_UVSCALE; float4 material : INSTANCE_MATERIAL;
};
struct VertexOut { float4 position : SV_POSITION; float4 color : COLOR0; float2 uv : TEXCOORD0; float3 normal : NORMAL0; float3 world : TEXCOORD1; float4 effects : TEXCOORD2; float fresnelPower : TEXCOORD3; };
VertexOut vertexMain(VertexIn input) {
  float4x4 model = float4x4(input.model0, input.model1, input.model2, input.model3);
  float4 world = mul(model, float4(input.position, 1.0)); VertexOut output;
  output.position = mul(viewProjection, world); output.color = input.color * input.tint;
  output.uv = input.uv * input.uvScale + input.uvOffset;
  output.normal = float3(dot(input.normal0, input.normal), dot(input.normal1, input.normal), dot(input.normal2, input.normal));
  output.world = world.xyz; output.effects = float4(input.whiteBlend, input.material.xyz); output.fresnelPower = input.material.w; return output;
}
float4 light(VertexOut input, float4 base) {
  base.rgb = lerp(base.rgb, float3(1.0, 1.0, 1.0), saturate(input.effects.x)); clip(base.a - 0.005);
  float3 normal = normalize(input.normal); float3 direction = length(lightDirection.xyz) < 0.0001 ? normalize(float3(0.35, 0.60, 0.72)) : normalize(lightDirection.xyz);
  float amount = max(lightLevels.x, 0.0) + max(lightLevels.y, 0.0) * max(dot(normal, direction), 0.0);
  float3 viewDirection = normalize(eye.xyz - input.world); float3 halfDirection = normalize(direction + viewDirection);
  float specular = max(input.effects.y, 0.0) * pow(max(dot(normal, halfDirection), 0.0), max(input.effects.z, 0.0001));
  float fresnel = max(input.effects.w, 0.0) * pow(1.0 - saturate(dot(normal, viewDirection)), max(input.fresnelPower, 0.0001));
  return float4(base.rgb * amount + specular + fresnel, base.a);
}
float4 colorMain(VertexOut input) : SV_TARGET { return light(input, input.color); }
float4 textureMain(VertexOut input) : SV_TARGET { return light(input, texture0.Sample(sampler0, input.uv) * input.color); }
)";
    auto vs = compileShader(shader, "vertexMain", "vs_5_0"), ps = compileShader(shader, "colorMain", "ps_5_0"), pts = compileShader(shader, "textureMain", "ps_5_0");
    if (!vs || !ps || !pts) return {};
    auto result = std::make_shared<ModelBatchPipeline>();
    if (FAILED(device->CreateVertexShader(vs->GetBufferPointer(), vs->GetBufferSize(), nullptr, &result->vertex)) ||
        FAILED(device->CreatePixelShader(ps->GetBufferPointer(), ps->GetBufferSize(), nullptr, &result->colorFragment)) ||
        FAILED(device->CreatePixelShader(pts->GetBufferPointer(), pts->GetBufferSize(), nullptr, &result->textureFragment))) return {};
    D3D11_INPUT_ELEMENT_DESC elements[] = {
        {"POSITION",0,DXGI_FORMAT_R32G32B32_FLOAT,0,0,D3D11_INPUT_PER_VERTEX_DATA,0}, {"COLOR",0,DXGI_FORMAT_R32G32B32A32_FLOAT,0,12,D3D11_INPUT_PER_VERTEX_DATA,0},
        {"TEXCOORD",0,DXGI_FORMAT_R32G32_FLOAT,0,28,D3D11_INPUT_PER_VERTEX_DATA,0}, {"NORMAL",0,DXGI_FORMAT_R32G32B32_FLOAT,0,36,D3D11_INPUT_PER_VERTEX_DATA,0},
        {"INSTANCE_MODEL",0,DXGI_FORMAT_R32G32B32A32_FLOAT,1,0,D3D11_INPUT_PER_INSTANCE_DATA,1}, {"INSTANCE_MODEL",1,DXGI_FORMAT_R32G32B32A32_FLOAT,1,16,D3D11_INPUT_PER_INSTANCE_DATA,1},
        {"INSTANCE_MODEL",2,DXGI_FORMAT_R32G32B32A32_FLOAT,1,32,D3D11_INPUT_PER_INSTANCE_DATA,1}, {"INSTANCE_MODEL",3,DXGI_FORMAT_R32G32B32A32_FLOAT,1,48,D3D11_INPUT_PER_INSTANCE_DATA,1},
        {"INSTANCE_NORMAL",0,DXGI_FORMAT_R32G32B32_FLOAT,1,64,D3D11_INPUT_PER_INSTANCE_DATA,1}, {"INSTANCE_NORMAL",1,DXGI_FORMAT_R32G32B32_FLOAT,1,80,D3D11_INPUT_PER_INSTANCE_DATA,1},
        {"INSTANCE_NORMAL",2,DXGI_FORMAT_R32G32B32_FLOAT,1,96,D3D11_INPUT_PER_INSTANCE_DATA,1}, {"INSTANCE_COLOR",0,DXGI_FORMAT_R32G32B32A32_FLOAT,1,112,D3D11_INPUT_PER_INSTANCE_DATA,1},
        {"INSTANCE_WHITE",0,DXGI_FORMAT_R32_FLOAT,1,128,D3D11_INPUT_PER_INSTANCE_DATA,1}, {"INSTANCE_UVOFFSET",0,DXGI_FORMAT_R32G32_FLOAT,1,132,D3D11_INPUT_PER_INSTANCE_DATA,1},
        {"INSTANCE_UVSCALE",0,DXGI_FORMAT_R32G32_FLOAT,1,140,D3D11_INPUT_PER_INSTANCE_DATA,1}, {"INSTANCE_MATERIAL",0,DXGI_FORMAT_R32G32B32A32_FLOAT,1,148,D3D11_INPUT_PER_INSTANCE_DATA,1},
    };
    if (FAILED(device->CreateInputLayout(elements, static_cast<UINT>(std::size(elements)), vs->GetBufferPointer(), vs->GetBufferSize(), &result->layout)) ||
        !createDynamicConstants<ModelBatchConstants>(device, result->constants)) return {};
    D3D11_SAMPLER_DESC sampler{}; sampler.Filter=D3D11_FILTER_MIN_MAG_MIP_LINEAR; sampler.AddressU=D3D11_TEXTURE_ADDRESS_WRAP; sampler.AddressV=D3D11_TEXTURE_ADDRESS_WRAP; sampler.AddressW=D3D11_TEXTURE_ADDRESS_WRAP; sampler.MaxLOD=D3D11_FLOAT32_MAX;
    device->CreateSamplerState(&sampler, &result->sampler); configureAlphaBlend(device, result->alphaBlend);
    modelBatchPipelines[device] = result; return result;
}

void drawMesh(std::shared_ptr<NativeSimpleMesh> mesh, ID3D11ShaderResourceView* texture,
    ID3D11DeviceContext* context, ID3D11Device* device, int32_t blendMode,
    bool hasColorAttachment, const double* viewProjection, const double* model, const double* normal,
    double ambient, double directional, double lightX, double lightY, double lightZ,
    double eyeX, double eyeY, double eyeZ, double red, double green, double blue, double alpha,
    double whiteBlend, double uvOffsetX, double uvOffsetY, double uvScaleX, double uvScaleY,
    double specular, double shininess, double fresnel, double fresnelPower) {
    if(!mesh||mesh->indexCount()<=0||!context||!device)return;auto pipeline=meshPipeline(device);if(!pipeline)return;
    MeshConstants values{};for(int i=0;i<16;++i){values.viewProjection[i]=float(viewProjection[i]);values.model[i]=float(model[i]);}for(int i=0;i<12;++i)values.normal[i]=float(normal[i]);values.lightDirection[0]=float(lightX);values.lightDirection[1]=float(lightY);values.lightDirection[2]=float(lightZ);values.lightLevels[0]=float(ambient);values.lightLevels[1]=float(directional);values.eye[0]=float(eyeX);values.eye[1]=float(eyeY);values.eye[2]=float(eyeZ);values.tint[0]=float(red);values.tint[1]=float(green);values.tint[2]=float(blue);values.tint[3]=float(alpha);values.effects[0]=float(whiteBlend);values.effects[1]=float(specular);values.effects[2]=float(shininess);values.effects[3]=float(fresnel);values.uv[0]=float(uvOffsetX);values.uv[1]=float(uvOffsetY);values.uv[2]=float(uvScaleX);values.uv[3]=float(uvScaleY);values.material[0]=float(fresnelPower);if(!updateConstants(context,pipeline->constants.Get(),values))return;
    auto* vb=reinterpret_cast<ID3D11Buffer*>(mesh->metalVertexBufferHandle());auto* ib=reinterpret_cast<ID3D11Buffer*>(mesh->metalIndexBufferHandle());UINT stride=sizeof(Vertex),offset=0;context->IASetInputLayout(pipeline->layout.Get());context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);context->IASetVertexBuffers(0,1,&vb,&stride,&offset);context->IASetIndexBuffer(ib,DXGI_FORMAT_R32_UINT,0);context->VSSetShader(pipeline->vertex.Get(),nullptr,0);ID3D11Buffer*cb=pipeline->constants.Get();context->VSSetConstantBuffers(0,1,&cb);context->PSSetConstantBuffers(0,1,&cb);context->PSSetShader(hasColorAttachment?(texture?pipeline->textureFragment.Get():pipeline->colorFragment.Get()):nullptr,nullptr,0);context->PSSetShaderResources(0,1,&texture);ID3D11SamplerState*sampler=pipeline->sampler.Get();context->PSSetSamplers(0,1,&sampler);float factor[4]{};context->OMSetBlendState(blendMode==1?pipeline->alphaBlend.Get():nullptr,factor,0xffffffff);context->DrawIndexed(mesh->indexCount(),0,0);ID3D11ShaderResourceView*none=nullptr;context->PSSetShaderResources(0,1,&none);
}

std::array<double, 16> multiplyMatrices(const double* left, const double* right) {
    std::array<double, 16> result{};
    for (int row = 0; row < 4; ++row) {
        for (int column = 0; column < 4; ++column) {
            for (int index = 0; index < 4; ++index) {
                result[row * 4 + column] += left[row * 4 + index] * right[index * 4 + column];
            }
        }
    }
    return result;
}
}

struct NativeSimpleMesh::Impl { ComPtr<ID3D11Device> device; ComPtr<ID3D11Buffer> vertices,indices; int32_t vertexCount,indexCount; Impl(void*d,void*v,void*i,int32_t vc,int32_t ic):device(static_cast<ID3D11Device*>(d)),vertices(static_cast<ID3D11Buffer*>(v)),indices(static_cast<ID3D11Buffer*>(i)),vertexCount(vc),indexCount(ic){} };
NativeSimpleMesh::NativeSimpleMesh(void*d,void*v,void*i,int32_t vc,int32_t ic):impl_(std::make_shared<Impl>(d,v,i,vc,ic)){} NativeSimpleMesh::~NativeSimpleMesh()=default; int32_t NativeSimpleMesh::vertexCount()const{return impl_->vertexCount;} int32_t NativeSimpleMesh::indexCount()const{return impl_->indexCount;} int64_t NativeSimpleMesh::metalDeviceHandle()const{return handle(impl_->device.Get());} int64_t NativeSimpleMesh::metalVertexBufferHandle()const{return handle(impl_->vertices.Get());} int64_t NativeSimpleMesh::metalIndexBufferHandle()const{return handle(impl_->indices.Get());}

struct NativeSimpleMeshBuilder::Impl { std::vector<Vertex> vertices; std::vector<uint32_t> indices; };
std::shared_ptr<NativeSimpleMeshBuilder> NativeSimpleMeshBuilder::create(){return std::make_shared<NativeSimpleMeshBuilder>();} NativeSimpleMeshBuilder::NativeSimpleMeshBuilder():impl_(std::make_shared<Impl>()){} NativeSimpleMeshBuilder::~NativeSimpleMeshBuilder()=default;
int32_t NativeSimpleMeshBuilder::addVertex(double x,double y,double z,double r,double g,double b,double a,double u,double v,double nx,double ny,double nz){impl_->vertices.push_back(Vertex{{float(x),float(y),float(z)},{float(r),float(g),float(b),float(a)},{float(u),float(v)},{float(nx),float(ny),float(nz)}});return static_cast<int32_t>(impl_->vertices.size()-1);}
std::shared_ptr<NativeSimpleMeshBuilder> NativeSimpleMeshBuilder::addTriangle(int32_t a,int32_t b,int32_t c){impl_->indices.push_back(uint32_t(a));impl_->indices.push_back(uint32_t(b));impl_->indices.push_back(uint32_t(c));return shared_from_this();}
doof::Result<std::shared_ptr<NativeSimpleMesh>,std::string> NativeSimpleMeshBuilder::build(int64_t dh){auto*d=reinterpret_cast<ID3D11Device*>(dh);if(!d)return doof::Failure<std::string>{"D3D11 device handle is invalid"};if(impl_->vertices.empty()&&impl_->indices.empty())return doof::Success<std::shared_ptr<NativeSimpleMesh>>{std::make_shared<NativeSimpleMesh>(d,nullptr,nullptr,0,0)};if(impl_->vertices.empty())return doof::Failure<std::string>{"Simple mesh has no vertices"};if(impl_->indices.empty())return doof::Failure<std::string>{"Simple mesh has no triangles"};if(impl_->indices.size()%3)return doof::Failure<std::string>{"Simple mesh index count must be divisible by 3"};for(uint32_t index:impl_->indices)if(index>=impl_->vertices.size())return doof::Failure<std::string>{"Simple mesh triangle index is out of range"};auto vb=immutableBuffer(d,impl_->vertices,D3D11_BIND_VERTEX_BUFFER);if(!doof::is_success(vb))return doof::Failure<std::string>{doof::failure_error(vb)};auto ib=immutableBuffer(d,impl_->indices,D3D11_BIND_INDEX_BUFFER);if(!doof::is_success(ib))return doof::Failure<std::string>{doof::failure_error(ib)};return doof::Success<std::shared_ptr<NativeSimpleMesh>>{std::make_shared<NativeSimpleMesh>(d,doof::success_value(vb).Get(),doof::success_value(ib).Get(),static_cast<int32_t>(impl_->vertices.size()),static_cast<int32_t>(impl_->indices.size()))};}

struct NativeSimpleModelBatch::Impl { ComPtr<ID3D11Device> device; ComPtr<ID3D11Buffer> buffer; std::vector<Instance> instances; int32_t count=0; Impl(void*d,void*b,int32_t c):device(static_cast<ID3D11Device*>(d)),buffer(static_cast<ID3D11Buffer*>(b)),instances(c){} };
doof::Result<std::shared_ptr<NativeSimpleModelBatch>,std::string> NativeSimpleModelBatch::create(int64_t dh,int32_t capacity){auto*d=reinterpret_cast<ID3D11Device*>(dh);if(!d)return doof::Failure<std::string>{"D3D11 device handle is invalid"};if(capacity<=0)return doof::Failure<std::string>{"Simple model batch capacity must be positive"};D3D11_BUFFER_DESC desc{};desc.ByteWidth=UINT(capacity*sizeof(Instance));desc.Usage=D3D11_USAGE_DEFAULT;desc.BindFlags=D3D11_BIND_VERTEX_BUFFER;ComPtr<ID3D11Buffer>b;if(FAILED(d->CreateBuffer(&desc,nullptr,&b)))return doof::Failure<std::string>{"Failed to create simple model batch buffer"};return doof::Success<std::shared_ptr<NativeSimpleModelBatch>>{std::make_shared<NativeSimpleModelBatch>(d,b.Get(),capacity)};}
NativeSimpleModelBatch::NativeSimpleModelBatch(void*d,void*b,int32_t c):impl_(std::make_shared<Impl>(d,b,c)){} NativeSimpleModelBatch::~NativeSimpleModelBatch()=default;int32_t NativeSimpleModelBatch::capacity()const{return static_cast<int32_t>(impl_->instances.size());}int32_t NativeSimpleModelBatch::count()const{return impl_->count;}void NativeSimpleModelBatch::setCount(int32_t c){impl_->count=std::clamp(c,0,capacity());}
void NativeSimpleModelBatch::setInstance(int32_t slot,double m00,double m01,double m02,double m03,double m10,double m11,double m12,double m13,double m20,double m21,double m22,double m23,double m30,double m31,double m32,double m33,double n00,double n01,double n02,double n10,double n11,double n12,double n20,double n21,double n22,double r,double g,double b,double a,double white,double ux,double uy,double sx,double sy,double spec,double shine,double fresnel,double power){if(slot<0||slot>=capacity())return;auto&i=impl_->instances[slot];double m[]={m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33};for(int x=0;x<16;++x)i.model[x]=float(m[x]);double n[]={n00,n01,n02,0,n10,n11,n12,0,n20,n21,n22,0};for(int x=0;x<12;++x)i.normal[x]=float(n[x]);i.color[0]=float(r);i.color[1]=float(g);i.color[2]=float(b);i.color[3]=float(a);i.whiteBlend=float(white);i.uvOffset[0]=float(ux);i.uvOffset[1]=float(uy);i.uvScale[0]=float(sx);i.uvScale[1]=float(sy);i.specular=float(spec);i.shininess=float(shine);i.fresnel=float(fresnel);i.fresnelPower=float(power);ComPtr<ID3D11DeviceContext>context;impl_->device->GetImmediateContext(&context);if(context&&impl_->buffer){D3D11_BOX box{};box.left=UINT(slot*sizeof(Instance));box.right=box.left+UINT(sizeof(Instance));box.bottom=1;box.back=1;context->UpdateSubresource(impl_->buffer.Get(),0,&box,&i,UINT(sizeof(Instance)),0);}}
int64_t NativeSimpleModelBatch::metalInstanceBufferHandle()const{return handle(impl_->buffer.Get());}

struct NativeSpaceDust::Impl { ComPtr<ID3D11Device> device;ComPtr<ID3D11Buffer>buffer;int32_t count;Impl(void*d,void*b,int32_t c):device(static_cast<ID3D11Device*>(d)),buffer(static_cast<ID3D11Buffer*>(b)),count(c){} };struct NativeSpaceDustBuilder::Impl{std::vector<Particle>particles;};
NativeSpaceDust::NativeSpaceDust(void*d,void*b,int32_t c):impl_(std::make_shared<Impl>(d,b,c)){}NativeSpaceDust::~NativeSpaceDust()=default;int32_t NativeSpaceDust::particleCount()const{return impl_->count;}int64_t NativeSpaceDust::metalDeviceHandle()const{return handle(impl_->device.Get());}int64_t NativeSpaceDust::metalParticleBufferHandle()const{return handle(impl_->buffer.Get());}
std::shared_ptr<NativeSpaceDustBuilder> NativeSpaceDustBuilder::create(){return std::make_shared<NativeSpaceDustBuilder>();}NativeSpaceDustBuilder::NativeSpaceDustBuilder():impl_(std::make_shared<Impl>()){}NativeSpaceDustBuilder::~NativeSpaceDustBuilder()=default;std::shared_ptr<NativeSpaceDustBuilder> NativeSpaceDustBuilder::addParticle(double x,double y,double z,double b){impl_->particles.push_back(Particle{{float(x),float(y),float(z)},float(b)});return shared_from_this();}doof::Result<std::shared_ptr<NativeSpaceDust>,std::string> NativeSpaceDustBuilder::build(int64_t dh){auto*d=reinterpret_cast<ID3D11Device*>(dh);if(!d)return doof::Failure<std::string>{"D3D11 device handle is invalid"};if(impl_->particles.empty())return doof::Failure<std::string>{"Space dust has no particles"};auto b=immutableBuffer(d,impl_->particles,D3D11_BIND_VERTEX_BUFFER);if(!doof::is_success(b))return doof::Failure<std::string>{doof::failure_error(b)};return doof::Success<std::shared_ptr<NativeSpaceDust>>{std::make_shared<NativeSpaceDust>(d,doof::success_value(b).Get(),static_cast<int32_t>(impl_->particles.size()))};}

namespace {
// Shader buffers keep a CPU copy and create one D3D11 buffer per role on first
// use: D3D11 forbids combining D3D11_BIND_CONSTANT_BUFFER with other bind flags.
struct ShaderBufferStorage {
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11Buffer> geometry;
    ComPtr<ID3D11Buffer> constants;
    int32_t size = 0;
    // Padded to 256 bytes so constant-buffer ranges bound at 256-byte offsets
    // always cover whole 16-constant blocks inside the buffer.
    std::vector<uint8_t> contents;

    ID3D11Buffer* buffer(bool constant) {
        ComPtr<ID3D11Buffer>& target = constant ? constants : geometry;
        if (target || !device) return target.Get();
        D3D11_BUFFER_DESC desc{};
        desc.ByteWidth = static_cast<UINT>(contents.size());
        desc.Usage = D3D11_USAGE_DEFAULT;
        desc.BindFlags = constant ? D3D11_BIND_CONSTANT_BUFFER : (D3D11_BIND_VERTEX_BUFFER | D3D11_BIND_INDEX_BUFFER);
        D3D11_SUBRESOURCE_DATA init{}; init.pSysMem = contents.data();
        if (FAILED(device->CreateBuffer(&desc, &init, &target))) target.Reset();
        return target.Get();
    }
};

ShaderBufferStorage* shaderBufferStorage(int64_t value) { return reinterpret_cast<ShaderBufferStorage*>(value); }

std::unordered_map<ID3D11Device*, ComPtr<ID3D11SamplerState>> shaderSamplers;

ID3D11SamplerState* shaderClampSampler(ID3D11Device* device) {
    std::lock_guard<std::mutex> lock(pipelineMutex);
    auto& sampler = shaderSamplers[device];
    if (!sampler) {
        D3D11_SAMPLER_DESC desc{}; desc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
        desc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP; desc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP; desc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
        desc.MaxLOD = D3D11_FLOAT32_MAX;
        if (FAILED(device->CreateSamplerState(&desc, &sampler))) sampler.Reset();
    }
    return sampler.Get();
}

doof::Result<ComPtr<ID3DBlob>, std::string> compileCustomShader(const std::string& source, const std::string& entry, const char* target, const char* label) {
    ComPtr<ID3DBlob> code, errors;
    if (FAILED(D3DCompile(source.data(), source.size(), label, nullptr, D3D_COMPILE_STANDARD_FILE_INCLUDE,
        entry.c_str(), target, D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &code, &errors))) {
        std::string message = std::string("Failed to compile ") + label;
        if (errors) message += ": " + std::string(static_cast<const char*>(errors->GetBufferPointer()), errors->GetBufferSize());
        while (!message.empty() && (message.back() == '\0' || message.back() == '\n' || message.back() == '\r')) message.pop_back();
        return doof::Failure<std::string>{message};
    }
    return doof::Success<ComPtr<ID3DBlob>>{code};
}

DXGI_FORMAT shaderVertexFormat(int32_t format) {
    switch (format) {
        case 1: return DXGI_FORMAT_R32_FLOAT;
        case 2: return DXGI_FORMAT_R32G32_FLOAT;
        case 3: return DXGI_FORMAT_R32G32B32_FLOAT;
        case 4: return DXGI_FORMAT_R32G32B32A32_FLOAT;
        case 5: return DXGI_FORMAT_R32_UINT;
        case 6: return DXGI_FORMAT_R8G8B8A8_UNORM;
        default: return DXGI_FORMAT_UNKNOWN;
    }
}

template <typename T> bool sameLength(const std::shared_ptr<std::vector<T>>& value, size_t size) { return value && value->size() == size; }
} // namespace

struct NativeShaderBuffer::Impl : ShaderBufferStorage { Impl(void* d, void*, int32_t s) { device = static_cast<ID3D11Device*>(d); size = s; } };
doof::Result<std::shared_ptr<NativeShaderBuffer>, std::string> NativeShaderBuffer::create(int64_t dh, const std::shared_ptr<std::vector<uint8_t>>& data) {
    auto* d = reinterpret_cast<ID3D11Device*>(dh);
    if (!d) return doof::Failure<std::string>{"D3D11 device handle is invalid"};
    if (!data || data->empty()) return doof::Failure<std::string>{"Shader buffer data must not be empty"};
    if (data->size() > static_cast<size_t>(INT32_MAX - 255)) return doof::Failure<std::string>{"Shader buffer data is too large"};
    auto shaderBuffer = std::make_shared<NativeShaderBuffer>(d, nullptr, static_cast<int32_t>(data->size()));
    shaderBuffer->impl_->contents.assign((data->size() + 255) & ~size_t(255), 0);
    std::memcpy(shaderBuffer->impl_->contents.data(), data->data(), data->size());
    return doof::Success<std::shared_ptr<NativeShaderBuffer>>{shaderBuffer};
}
NativeShaderBuffer::NativeShaderBuffer(void* d, void* b, int32_t s) : impl_(std::make_shared<Impl>(d, b, s)) {}
NativeShaderBuffer::~NativeShaderBuffer() = default;
int32_t NativeShaderBuffer::byteLength() const { return impl_->size; }
// Draws resolve this handle back to the storage and pick the role-specific buffer.
int64_t NativeShaderBuffer::metalBufferHandle() const { return handle(static_cast<ShaderBufferStorage*>(impl_.get())); }
doof::Result<void, std::string> NativeShaderBuffer::update(const std::shared_ptr<std::vector<uint8_t>>& data, int32_t offset) {
    if (!data || data->empty()) return doof::Failure<std::string>{"Shader buffer update data must not be empty"};
    if (offset < 0 || size_t(offset) + data->size() > size_t(impl_->size)) return doof::Failure<std::string>{"Shader buffer update range exceeds the buffer"};
    std::memcpy(impl_->contents.data() + offset, data->data(), data->size());
    if (!impl_->geometry && !impl_->constants) return doof::Success<void>{};
    ComPtr<ID3D11DeviceContext> context; impl_->device->GetImmediateContext(&context);
    if (!context) return doof::Failure<std::string>{"D3D11 device context is unavailable"};
    // Constant buffers only accept whole-resource UpdateSubresource calls on D3D11.0.
    if (impl_->constants) context->UpdateSubresource(impl_->constants.Get(), 0, nullptr, impl_->contents.data(), 0, 0);
    if (impl_->geometry) {
        D3D11_BOX box{}; box.left = UINT(offset); box.right = UINT(offset + data->size()); box.bottom = 1; box.back = 1;
        context->UpdateSubresource(impl_->geometry.Get(), 0, &box, impl_->contents.data() + offset, 0, 0);
    }
    return doof::Success<void>{};
}

struct NativeShaderPipeline::Impl {
    struct Slot { UINT index = 0; int32_t stages = 0; };
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11VertexShader> vertex;
    ComPtr<ID3D11PixelShader> fragment;
    ComPtr<ID3D11InputLayout> layout;
    ComPtr<ID3D11BlendState> alphaBlend;
    std::vector<UINT> strides; // indexed by vertex buffer slot; 0 = no layout
    std::vector<Slot> uniforms;
    std::vector<Slot> textures;
    // One dynamic constant buffer per uniform slot for inline uniform bytes.
    std::vector<ComPtr<ID3D11Buffer>> inlineUniforms;
    std::vector<UINT> inlineCapacities;
};

doof::Result<std::shared_ptr<NativeShaderPipeline>, std::string> NativeShaderPipeline::create(
    int64_t deviceHandle,
    const std::string& vertexSource,
    const std::string& fragmentSource,
    const std::string& vertexFunction,
    const std::string& fragmentFunction,
    const std::shared_ptr<std::vector<int32_t>>& attributeIndices,
    const std::shared_ptr<std::vector<int32_t>>& attributeBuffers,
    const std::shared_ptr<std::vector<int32_t>>& attributeOffsets,
    const std::shared_ptr<std::vector<int32_t>>& attributeFormats,
    const std::shared_ptr<std::vector<int32_t>>& layoutBuffers,
    const std::shared_ptr<std::vector<int32_t>>& layoutStrides,
    const std::shared_ptr<std::vector<int32_t>>& layoutStepFunctions,
    const std::shared_ptr<std::vector<int32_t>>& layoutStepRates,
    const std::shared_ptr<std::vector<std::string>>& uniformNames,
    const std::shared_ptr<std::vector<int32_t>>& uniformIndices,
    const std::shared_ptr<std::vector<int32_t>>& uniformStages,
    const std::shared_ptr<std::vector<std::string>>& textureNames,
    const std::shared_ptr<std::vector<int32_t>>& textureIndices,
    const std::shared_ptr<std::vector<int32_t>>& textureStages
) {
    if (!uniformNames || !sameLength(uniformIndices, uniformNames->size()) || !sameLength(uniformStages, uniformNames->size()))
        return doof::Failure<std::string>{"Shader uniform slot arrays must have matching lengths"};
    if (!textureNames || !sameLength(textureIndices, textureNames->size()) || !sameLength(textureStages, textureNames->size()))
        return doof::Failure<std::string>{"Shader texture slot arrays must have matching lengths"};
    auto impl = std::make_shared<Impl>();
    for (size_t i = 0; i < uniformIndices->size(); ++i) {
        int32_t index = (*uniformIndices)[i], stages = (*uniformStages)[i];
        if (index < 0 || index >= D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT || (stages & 3) == 0)
            return doof::Failure<std::string>{"Shader uniform slot index or stages are invalid"};
        impl->uniforms.push_back({UINT(index), stages});
    }
    for (size_t i = 0; i < textureIndices->size(); ++i) {
        int32_t index = (*textureIndices)[i], stages = (*textureStages)[i];
        if (index < 0 || index >= D3D11_COMMONSHADER_SAMPLER_SLOT_COUNT || (stages & 3) == 0)
            return doof::Failure<std::string>{"Shader texture slot index or stages are invalid"};
        impl->textures.push_back({UINT(index), stages});
    }
    impl->inlineUniforms.resize(impl->uniforms.size());
    impl->inlineCapacities.resize(impl->uniforms.size());

    auto* device = reinterpret_cast<ID3D11Device*>(deviceHandle);
    if (!device) return doof::Failure<std::string>{"D3D11 device handle is invalid"};
    if (vertexSource.empty()) return doof::Failure<std::string>{"Shader vertex source must not be empty"};
    if (fragmentSource.empty()) return doof::Failure<std::string>{"Shader fragment source must not be empty"};
    if (vertexFunction.empty()) return doof::Failure<std::string>{"Shader vertex function name must not be empty"};
    if (fragmentFunction.empty()) return doof::Failure<std::string>{"Shader fragment function name must not be empty"};
    if (!attributeIndices || !sameLength(attributeBuffers, attributeIndices->size()) ||
        !sameLength(attributeOffsets, attributeIndices->size()) || !sameLength(attributeFormats, attributeIndices->size()))
        return doof::Failure<std::string>{"Shader vertex attribute arrays must have matching lengths"};
    if (!layoutBuffers || !sameLength(layoutStrides, layoutBuffers->size()) ||
        !sameLength(layoutStepFunctions, layoutBuffers->size()) || !sameLength(layoutStepRates, layoutBuffers->size()))
        return doof::Failure<std::string>{"Shader vertex layout arrays must have matching lengths"};

    struct Layout { bool instanced = false; UINT stepRate = 0; };
    std::vector<Layout> layouts;
    for (size_t i = 0; i < layoutBuffers->size(); ++i) {
        int32_t buffer = (*layoutBuffers)[i];
        if (buffer < 0 || buffer >= D3D11_IA_VERTEX_INPUT_RESOURCE_SLOT_COUNT || (*layoutStrides)[i] <= 0 || (*layoutStepRates)[i] <= 0)
            return doof::Failure<std::string>{"Shader vertex layout buffer index, stride, and step rate must be positive"};
        int32_t step = (*layoutStepFunctions)[i];
        if (step != 1 && step != 2) return doof::Failure<std::string>{"Shader vertex layout step function is invalid"};
        if (impl->strides.size() <= size_t(buffer)) { impl->strides.resize(size_t(buffer) + 1); layouts.resize(size_t(buffer) + 1); }
        impl->strides[size_t(buffer)] = UINT((*layoutStrides)[i]);
        layouts[size_t(buffer)] = {step == 2, step == 2 ? UINT((*layoutStepRates)[i]) : 0};
    }

    // HLSL vertex inputs bind by semantic: attribute index N is TEXCOORDN.
    std::vector<D3D11_INPUT_ELEMENT_DESC> elements;
    for (size_t i = 0; i < attributeIndices->size(); ++i) {
        int32_t index = (*attributeIndices)[i], buffer = (*attributeBuffers)[i], offset = (*attributeOffsets)[i];
        if (index < 0 || buffer < 0 || offset < 0)
            return doof::Failure<std::string>{"Shader vertex attribute index, buffer, and offset must be non-negative"};
        DXGI_FORMAT format = shaderVertexFormat((*attributeFormats)[i]);
        if (format == DXGI_FORMAT_UNKNOWN) return doof::Failure<std::string>{"Shader vertex attribute format is invalid"};
        if (size_t(buffer) >= impl->strides.size() || impl->strides[size_t(buffer)] == 0)
            return doof::Failure<std::string>{"Shader vertex attribute references a buffer without a layout"};
        const Layout& layout = layouts[size_t(buffer)];
        elements.push_back({"TEXCOORD", UINT(index), format, UINT(buffer), UINT(offset),
            layout.instanced ? D3D11_INPUT_PER_INSTANCE_DATA : D3D11_INPUT_PER_VERTEX_DATA, layout.stepRate});
    }

    auto vertexCode = compileCustomShader(vertexSource, vertexFunction, "vs_5_0", "shader vertex source");
    if (doof::is_failure(vertexCode)) return doof::Failure<std::string>{doof::failure_error(vertexCode)};
    auto fragmentCode = compileCustomShader(fragmentSource, fragmentFunction, "ps_5_0", "shader fragment source");
    if (doof::is_failure(fragmentCode)) return doof::Failure<std::string>{doof::failure_error(fragmentCode)};
    auto vs = doof::success_value(vertexCode), ps = doof::success_value(fragmentCode);
    impl->device = device;
    if (FAILED(device->CreateVertexShader(vs->GetBufferPointer(), vs->GetBufferSize(), nullptr, &impl->vertex)))
        return doof::Failure<std::string>{"Failed to create shader vertex function: " + vertexFunction};
    if (FAILED(device->CreatePixelShader(ps->GetBufferPointer(), ps->GetBufferSize(), nullptr, &impl->fragment)))
        return doof::Failure<std::string>{"Failed to create shader fragment function: " + fragmentFunction};
    if (!elements.empty() && FAILED(device->CreateInputLayout(elements.data(), UINT(elements.size()), vs->GetBufferPointer(), vs->GetBufferSize(), &impl->layout)))
        return doof::Failure<std::string>{"Failed to create shader input layout; vertex inputs must use TEXCOORD<attribute index> semantics"};
    configureAlphaBlend(device, impl->alphaBlend);
    if (!impl->alphaBlend) return doof::Failure<std::string>{"Failed to create shader blend state"};

    auto pipeline = std::make_shared<NativeShaderPipeline>(device, nullptr, nullptr, nullptr, vertexFunction, fragmentFunction);
    pipeline->impl_ = std::move(impl);
    return doof::Success<std::shared_ptr<NativeShaderPipeline>>{pipeline};
}
NativeShaderPipeline::NativeShaderPipeline(void*, void*, void*, void*, std::string, std::string) : impl_(std::make_shared<Impl>()) {}
NativeShaderPipeline::~NativeShaderPipeline() = default;
// D3D11 has no monolithic pipeline object; blend and attachment state are applied per draw.
doof::Result<int64_t, std::string> NativeShaderPipeline::metalPipelineHandle(int32_t, bool, bool) {
    if (!impl_->device || !impl_->vertex || !impl_->fragment) return doof::Failure<std::string>{"Shader pipeline is invalid"};
    return doof::Success<int64_t>{handle(impl_.get())};
}

void drawNativeSimpleMesh(
    std::shared_ptr<NativeSimpleMesh> mesh, int64_t contextHandle, int64_t deviceHandle, int32_t blendMode, bool hasColorAttachment, bool,
    double m00,double m01,double m02,double m03,double m10,double m11,double m12,double m13,double m20,double m21,double m22,double m23,double m30,double m31,double m32,double m33,
    double modelM00,double modelM01,double modelM02,double modelM03,double modelM10,double modelM11,double modelM12,double modelM13,double modelM20,double modelM21,double modelM22,double modelM23,double modelM30,double modelM31,double modelM32,double modelM33,
    double n00,double n01,double n02,double n10,double n11,double n12,double n20,double n21,double n22,
    double ambient,double directional,double lightX,double lightY,double lightZ,double eyeX,double eyeY,double eyeZ,
    double red,double green,double blue,double alpha,double whiteBlend,double uvOffsetX,double uvOffsetY,double uvScaleX,double uvScaleY,double specular,double shininess,double fresnel,double fresnelPower
) { double viewProjection[]={m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33};double model[]={modelM00,modelM01,modelM02,modelM03,modelM10,modelM11,modelM12,modelM13,modelM20,modelM21,modelM22,modelM23,modelM30,modelM31,modelM32,modelM33};double normal[]={n00,n01,n02,0,n10,n11,n12,0,n20,n21,n22,0};drawMesh(std::move(mesh),nullptr,reinterpret_cast<ID3D11DeviceContext*>(contextHandle),reinterpret_cast<ID3D11Device*>(deviceHandle),blendMode,hasColorAttachment,viewProjection,model,normal,ambient,directional,lightX,lightY,lightZ,eyeX,eyeY,eyeZ,red,green,blue,alpha,whiteBlend,uvOffsetX,uvOffsetY,uvScaleX,uvScaleY,specular,shininess,fresnel,fresnelPower); }

void drawNativeTexturedSimpleMesh(
    std::shared_ptr<NativeSimpleMesh> mesh, int64_t textureHandle, int64_t contextHandle, int64_t deviceHandle, int32_t blendMode, bool hasColorAttachment, bool,
    double m00,double m01,double m02,double m03,double m10,double m11,double m12,double m13,double m20,double m21,double m22,double m23,double m30,double m31,double m32,double m33,
    double modelM00,double modelM01,double modelM02,double modelM03,double modelM10,double modelM11,double modelM12,double modelM13,double modelM20,double modelM21,double modelM22,double modelM23,double modelM30,double modelM31,double modelM32,double modelM33,
    double n00,double n01,double n02,double n10,double n11,double n12,double n20,double n21,double n22,
    double ambient,double directional,double lightX,double lightY,double lightZ,double eyeX,double eyeY,double eyeZ,
    double red,double green,double blue,double alpha,double whiteBlend,double uvOffsetX,double uvOffsetY,double uvScaleX,double uvScaleY,double specular,double shininess,double fresnel,double fresnelPower
) { double viewProjection[]={m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33};double model[]={modelM00,modelM01,modelM02,modelM03,modelM10,modelM11,modelM12,modelM13,modelM20,modelM21,modelM22,modelM23,modelM30,modelM31,modelM32,modelM33};double normal[]={n00,n01,n02,0,n10,n11,n12,0,n20,n21,n22,0};drawMesh(std::move(mesh),reinterpret_cast<ID3D11ShaderResourceView*>(textureHandle),reinterpret_cast<ID3D11DeviceContext*>(contextHandle),reinterpret_cast<ID3D11Device*>(deviceHandle),blendMode,hasColorAttachment,viewProjection,model,normal,ambient,directional,lightX,lightY,lightZ,eyeX,eyeY,eyeZ,red,green,blue,alpha,whiteBlend,uvOffsetX,uvOffsetY,uvScaleX,uvScaleY,specular,shininess,fresnel,fresnelPower); }

void drawNativeSimpleModelBatch(
    std::shared_ptr<NativeSimpleMesh> mesh, std::shared_ptr<NativeSimpleModelBatch> batch, int64_t textureHandle, bool textured,
    int64_t contextHandle, int64_t deviceHandle, int32_t blendMode, bool hasColorAttachment, bool,
    double m00,double m01,double m02,double m03,double m10,double m11,double m12,double m13,double m20,double m21,double m22,double m23,double m30,double m31,double m32,double m33,
    double ambient,double directional,double lightX,double lightY,double lightZ,double eyeX,double eyeY,double eyeZ
) {
    if(!mesh||!batch||mesh->indexCount()<=0||batch->count()<=0)return;
    auto*context=reinterpret_cast<ID3D11DeviceContext*>(contextHandle);auto*device=reinterpret_cast<ID3D11Device*>(deviceHandle);if(!context||!device)return;
    auto pipeline=modelBatchPipeline(device);if(!pipeline)return;
    auto*texture=reinterpret_cast<ID3D11ShaderResourceView*>(textureHandle);if(textured&&!texture)return;
    ModelBatchConstants values{};double matrix[]={m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33};for(int i=0;i<16;++i)values.matrix[i]=float(matrix[i]);
    values.lightDirection[0]=float(lightX);values.lightDirection[1]=float(lightY);values.lightDirection[2]=float(lightZ);values.lightLevels[0]=float(ambient);values.lightLevels[1]=float(directional);values.eye[0]=float(eyeX);values.eye[1]=float(eyeY);values.eye[2]=float(eyeZ);
    if(!updateConstants(context,pipeline->constants.Get(),values))return;
    auto*vertices=reinterpret_cast<ID3D11Buffer*>(mesh->metalVertexBufferHandle());auto*indices=reinterpret_cast<ID3D11Buffer*>(mesh->metalIndexBufferHandle());auto*instances=reinterpret_cast<ID3D11Buffer*>(batch->metalInstanceBufferHandle());
    ID3D11Buffer*buffers[]={vertices,instances};UINT strides[]={sizeof(Vertex),sizeof(Instance)},offsets[]={0,0};context->IASetInputLayout(pipeline->layout.Get());context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);context->IASetVertexBuffers(0,2,buffers,strides,offsets);context->IASetIndexBuffer(indices,DXGI_FORMAT_R32_UINT,0);
    context->VSSetShader(pipeline->vertex.Get(),nullptr,0);ID3D11Buffer*constants=pipeline->constants.Get();context->VSSetConstantBuffers(0,1,&constants);context->PSSetConstantBuffers(0,1,&constants);
    context->PSSetShader(hasColorAttachment?(textured?pipeline->textureFragment.Get():pipeline->colorFragment.Get()):nullptr,nullptr,0);context->PSSetShaderResources(0,1,&texture);ID3D11SamplerState*sampler=pipeline->sampler.Get();context->PSSetSamplers(0,1,&sampler);float factor[4]{};context->OMSetBlendState(blendMode==1?pipeline->alphaBlend.Get():nullptr,factor,0xffffffff);
    context->DrawIndexedInstanced(mesh->indexCount(),batch->count(),0,0,0);ID3D11ShaderResourceView*none=nullptr;context->PSSetShaderResources(0,1,&none);
}

void drawNativeEquirectangularSkyMap(
    int64_t textureHandle,int64_t contextHandle,int64_t deviceHandle,bool,int32_t pixelWidth,int32_t pixelHeight,double fovY,double exposure,
    double r00,double r01,double r02,double r10,double r11,double r12,double r20,double r21,double r22
) {
    auto*texture=reinterpret_cast<ID3D11ShaderResourceView*>(textureHandle);auto*context=reinterpret_cast<ID3D11DeviceContext*>(contextHandle);auto*device=reinterpret_cast<ID3D11Device*>(deviceHandle);if(!texture||!context||!device)return;
    auto pipeline=skyMapPipeline(device);if(!pipeline)return;SkyMapConstants values{};values.pixelWidth=float(pixelWidth);values.pixelHeight=float(pixelHeight);values.tanHalfFovY=float(std::tan(fovY*0.5));values.exposure=float(exposure);double rotation[]={r00,r01,r02,0,r10,r11,r12,0,r20,r21,r22,0};for(int i=0;i<12;++i)values.rotation[i]=float(rotation[i]);if(!updateConstants(context,pipeline->constants.Get(),values))return;
    context->IASetInputLayout(nullptr);context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);context->VSSetShader(pipeline->vertex.Get(),nullptr,0);context->PSSetShader(pipeline->fragment.Get(),nullptr,0);ID3D11Buffer*constants=pipeline->constants.Get();context->PSSetConstantBuffers(0,1,&constants);context->PSSetShaderResources(0,1,&texture);ID3D11SamplerState*sampler=pipeline->sampler.Get();context->PSSetSamplers(0,1,&sampler);context->OMSetBlendState(nullptr,nullptr,0xffffffff);context->Draw(3,0);ID3D11ShaderResourceView*none=nullptr;context->PSSetShaderResources(0,1,&none);
}

void drawNativeSpaceDust(
    std::shared_ptr<NativeSpaceDust> dust,int64_t contextHandle,int64_t deviceHandle,bool,int32_t pixelWidth,int32_t pixelHeight,
    double cameraX,double cameraY,double cameraZ,double fieldSize,double particleSize,double fadeStart,double fadeEnd,double opacity,double red,double green,double blue,
    double m00,double m01,double m02,double m03,double m10,double m11,double m12,double m13,double m20,double m21,double m22,double m23,double m30,double m31,double m32,double m33
) {
    if(!dust||dust->particleCount()<=0)return;auto*context=reinterpret_cast<ID3D11DeviceContext*>(contextHandle);auto*device=reinterpret_cast<ID3D11Device*>(deviceHandle);auto*particles=reinterpret_cast<ID3D11Buffer*>(dust->metalParticleBufferHandle());if(!context||!device||!particles)return;
    auto pipeline=spaceDustPipeline(device);if(!pipeline)return;SpaceDustConstants values{};double matrix[]={m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33};for(int i=0;i<16;++i)values.matrix[i]=float(matrix[i]);values.camera[0]=float(cameraX);values.camera[1]=float(cameraY);values.camera[2]=float(cameraZ);values.color[0]=float(red);values.color[1]=float(green);values.color[2]=float(blue);values.color[3]=1;values.fieldSize=float(fieldSize);values.particleSize=float(particleSize);values.fadeStart=float(fadeStart);values.fadeEnd=float(fadeEnd);values.opacity=float(opacity);values.pixelScale=float(std::max(pixelHeight,1)/720.0);values.pixelWidth=float(pixelWidth);values.pixelHeight=float(pixelHeight);if(!updateConstants(context,pipeline->constants.Get(),values))return;
    UINT stride=sizeof(Particle),offset=0;context->IASetInputLayout(pipeline->layout.Get());context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_POINTLIST);context->IASetVertexBuffers(0,1,&particles,&stride,&offset);ID3D11Buffer*constants=pipeline->constants.Get();context->VSSetShader(pipeline->vertex.Get(),nullptr,0);context->VSSetConstantBuffers(0,1,&constants);context->GSSetShader(pipeline->geometry.Get(),nullptr,0);context->GSSetConstantBuffers(0,1,&constants);context->PSSetShader(pipeline->fragment.Get(),nullptr,0);context->PSSetConstantBuffers(0,1,&constants);float factor[4]{};context->OMSetBlendState(pipeline->alphaBlend.Get(),factor,0xffffffff);context->Draw(dust->particleCount(),0);context->GSSetShader(nullptr,nullptr,0);
}

doof::Result<void,std::string> drawNativeShader(
    std::shared_ptr<NativeShaderPipeline> pipeline,
    const std::shared_ptr<std::vector<int32_t>>& vertexBufferIndices,
    const std::shared_ptr<std::vector<int64_t>>& vertexBufferHandles,
    const std::shared_ptr<std::vector<int32_t>>& vertexBufferOffsets,
    const std::shared_ptr<std::vector<int32_t>>& uniformSlots,
    const std::shared_ptr<std::vector<int64_t>>& uniformBufferHandles,
    const std::shared_ptr<std::vector<int32_t>>& uniformOffsets,
    const std::shared_ptr<std::vector<int32_t>>& uniformLengths,
    const std::shared_ptr<std::vector<uint8_t>>& uniformBytes,
    const std::shared_ptr<std::vector<int32_t>>& textureSlots,
    const std::shared_ptr<std::vector<int64_t>>& textureHandles,
    int64_t indexBufferHandle,
    int32_t indexCount,
    int32_t vertexCount,
    int32_t instanceCount,
    int64_t contextHandle,
    int32_t blendMode,
    bool hasColorAttachment,
    bool
) {
    if (!pipeline) return doof::Failure<std::string>{"Shader pipeline is required"};
    auto& impl = *pipeline->impl();
    if (!impl.device || !impl.vertex || !impl.fragment) return doof::Failure<std::string>{"Shader pipeline is invalid"};
    auto* context = reinterpret_cast<ID3D11DeviceContext*>(contextHandle);
    if (!context) return doof::Failure<std::string>{"D3D11 device context handle is invalid"};
    if (instanceCount <= 0) return doof::Failure<std::string>{"Shader instance count must be positive"};
    if (indexCount <= 0 && vertexCount <= 0) return doof::Failure<std::string>{"Shader vertex count must be positive for non-indexed draws"};
    ID3D11Device* device = impl.device.Get();

    if (!vertexBufferIndices || !sameLength(vertexBufferHandles, vertexBufferIndices->size()) || !sameLength(vertexBufferOffsets, vertexBufferIndices->size()))
        return doof::Failure<std::string>{"Shader vertex buffer binding arrays must have matching lengths"};
    for (size_t i = 0; i < vertexBufferIndices->size(); ++i) {
        int32_t index = (*vertexBufferIndices)[i], offset = (*vertexBufferOffsets)[i];
        if (index < 0 || offset < 0) return doof::Failure<std::string>{"Shader buffer binding index and offset must be non-negative"};
        if (size_t(index) >= impl.strides.size() || impl.strides[size_t(index)] == 0)
            return doof::Failure<std::string>{"Shader vertex buffer binding has no matching vertex layout"};
        auto* storage = shaderBufferStorage((*vertexBufferHandles)[i]);
        ID3D11Buffer* buffer = storage ? storage->buffer(false) : nullptr;
        if (!buffer) return doof::Failure<std::string>{"Shader buffer binding has an invalid D3D11 buffer handle"};
        UINT stride = impl.strides[size_t(index)], start = UINT(offset);
        context->IASetVertexBuffers(UINT(index), 1, &buffer, &stride, &start);
    }

    if (!uniformSlots || !uniformBytes || !sameLength(uniformBufferHandles, uniformSlots->size()) ||
        !sameLength(uniformOffsets, uniformSlots->size()) || !sameLength(uniformLengths, uniformSlots->size()))
        return doof::Failure<std::string>{"Shader uniform binding arrays must have matching lengths"};
    ComPtr<ID3D11DeviceContext1> context1;
    for (size_t i = 0; i < uniformSlots->size(); ++i) {
        int32_t ordinal = (*uniformSlots)[i], offset = (*uniformOffsets)[i], length = (*uniformLengths)[i];
        if (ordinal < 0 || size_t(ordinal) >= impl.uniforms.size() || offset < 0 || length <= 0)
            return doof::Failure<std::string>{"Shader uniform binding is invalid"};
        const auto& slot = impl.uniforms[size_t(ordinal)];
        bool vertex = (slot.stages & 1) != 0, fragment = (slot.stages & 2) != 0;

        if ((*uniformBufferHandles)[i] != 0) {
            auto* storage = shaderBufferStorage((*uniformBufferHandles)[i]);
            ID3D11Buffer* buffer = storage ? storage->buffer(true) : nullptr;
            if (!buffer) return doof::Failure<std::string>{"Shader uniform binding has an invalid D3D11 buffer handle"};
            if (offset == 0 && length <= 65536) {
                if (vertex) context->VSSetConstantBuffers(slot.index, 1, &buffer);
                if (fragment) context->PSSetConstantBuffers(slot.index, 1, &buffer);
                continue;
            }
            // Ranged binds need D3D11.1. Offsets arrive 256-byte aligned, which is
            // the 16-constant granularity D3D11.1 requires; the count is rounded
            // the same way and capped at the 4096 constants a shader can address.
            if (!context1 && FAILED(context->QueryInterface(IID_PPV_ARGS(&context1))))
                return doof::Failure<std::string>{"Shader uniform buffer offsets require Direct3D 11.1"};
            UINT first = UINT(offset) / 16, count = std::min<UINT>((UINT(length) + 255u) / 256u * 16u, 4096u);
            if (vertex) context1->VSSetConstantBuffers1(slot.index, 1, &buffer, &first, &count);
            if (fragment) context1->PSSetConstantBuffers1(slot.index, 1, &buffer, &first, &count);
            continue;
        }

        if (size_t(offset) + size_t(length) > uniformBytes->size()) return doof::Failure<std::string>{"Shader uniform bytes are out of range"};
        if (length > 65536) return doof::Failure<std::string>{"Shader inline uniform bytes exceed the 64 KiB constant buffer limit"};
        UINT padded = (UINT(length) + 15u) & ~15u;
        auto& buffer = impl.inlineUniforms[size_t(ordinal)];
        if (!buffer || impl.inlineCapacities[size_t(ordinal)] < padded) {
            D3D11_BUFFER_DESC desc{}; desc.ByteWidth = padded; desc.Usage = D3D11_USAGE_DYNAMIC;
            desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER; desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
            buffer.Reset();
            if (FAILED(device->CreateBuffer(&desc, nullptr, &buffer))) return doof::Failure<std::string>{"Failed to create shader uniform buffer"};
            impl.inlineCapacities[size_t(ordinal)] = padded;
        }
        D3D11_MAPPED_SUBRESOURCE mapped{};
        if (FAILED(context->Map(buffer.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) return doof::Failure<std::string>{"Failed to update shader uniform buffer"};
        std::memset(mapped.pData, 0, impl.inlineCapacities[size_t(ordinal)]);
        std::memcpy(mapped.pData, uniformBytes->data() + offset, size_t(length));
        context->Unmap(buffer.Get(), 0);
        ID3D11Buffer* raw = buffer.Get();
        if (vertex) context->VSSetConstantBuffers(slot.index, 1, &raw);
        if (fragment) context->PSSetConstantBuffers(slot.index, 1, &raw);
    }

    if (!textureSlots || !sameLength(textureHandles, textureSlots->size()))
        return doof::Failure<std::string>{"Shader texture binding arrays must have matching lengths"};
    ID3D11SamplerState* sampler = textureSlots->empty() ? nullptr : shaderClampSampler(device);
    if (!textureSlots->empty() && !sampler) return doof::Failure<std::string>{"Failed to create shader texture sampler"};
    std::vector<ComPtr<ID3D11ShaderResourceView>> views;
    for (size_t i = 0; i < textureSlots->size(); ++i) {
        int32_t ordinal = (*textureSlots)[i];
        if (ordinal < 0 || size_t(ordinal) >= impl.textures.size()) return doof::Failure<std::string>{"Shader texture binding is invalid"};
        // Depth textures hand out depth-stencil views, which cannot be sampled.
        auto* view = reinterpret_cast<ID3D11View*>((*textureHandles)[i]);
        ComPtr<ID3D11ShaderResourceView> texture;
        if (!view || FAILED(view->QueryInterface(IID_PPV_ARGS(&texture))))
            return doof::Failure<std::string>{"Shader texture binding has an invalid D3D11 shader resource view (depth textures cannot be sampled on Windows)"};
        const auto& slot = impl.textures[size_t(ordinal)];
        ID3D11ShaderResourceView* raw = texture.Get();
        if ((slot.stages & 1) != 0) { context->VSSetShaderResources(slot.index, 1, &raw); context->VSSetSamplers(slot.index, 1, &sampler); }
        if ((slot.stages & 2) != 0) { context->PSSetShaderResources(slot.index, 1, &raw); context->PSSetSamplers(slot.index, 1, &sampler); }
        views.push_back(texture);
    }

    context->IASetInputLayout(impl.layout.Get());
    context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    context->VSSetShader(impl.vertex.Get(), nullptr, 0);
    context->PSSetShader(hasColorAttachment ? impl.fragment.Get() : nullptr, nullptr, 0);
    float factor[4]{};
    context->OMSetBlendState(blendMode == 1 ? impl.alphaBlend.Get() : nullptr, factor, 0xffffffff);
    if (indexCount > 0) {
        auto* storage = shaderBufferStorage(indexBufferHandle);
        ID3D11Buffer* indices = storage ? storage->buffer(false) : nullptr;
        if (!indices) return doof::Failure<std::string>{"Shader index buffer handle is invalid"};
        context->IASetIndexBuffer(indices, DXGI_FORMAT_R32_UINT, 0);
        context->DrawIndexedInstanced(UINT(indexCount), UINT(instanceCount), 0, 0, 0);
    } else {
        context->DrawInstanced(UINT(vertexCount), UINT(instanceCount), 0, 0);
    }

    // Unbind sampled views so a texture can become a render target in a later pass.
    ID3D11ShaderResourceView* none = nullptr;
    for (size_t i = 0; i < textureSlots->size(); ++i) {
        const auto& slot = impl.textures[size_t((*textureSlots)[i])];
        if ((slot.stages & 1) != 0) context->VSSetShaderResources(slot.index, 1, &none);
        if ((slot.stages & 2) != 0) context->PSSetShaderResources(slot.index, 1, &none);
    }
    return doof::Success<void>{};
}

} // namespace doof_game
