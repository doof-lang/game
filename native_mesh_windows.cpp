#include "native_mesh.hpp"

#define NOMINMAX
#include <d3d11.h>
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

struct NativeShaderBuffer::Impl{ComPtr<ID3D11Device>device;ComPtr<ID3D11Buffer>buffer;int32_t size;Impl(void*d,void*b,int32_t s):device(static_cast<ID3D11Device*>(d)),buffer(static_cast<ID3D11Buffer*>(b)),size(s){}};
doof::Result<std::shared_ptr<NativeShaderBuffer>,std::string> NativeShaderBuffer::create(int64_t dh,const std::shared_ptr<std::vector<uint8_t>>&data){auto*d=reinterpret_cast<ID3D11Device*>(dh);if(!d||!data||data->empty())return doof::Failure<std::string>{"Shader buffer data is empty"};D3D11_BUFFER_DESC desc{};desc.ByteWidth=UINT((data->size()+15)&~size_t(15));desc.Usage=D3D11_USAGE_DEFAULT;desc.BindFlags=D3D11_BIND_CONSTANT_BUFFER;std::vector<uint8_t>padded(desc.ByteWidth);std::memcpy(padded.data(),data->data(),data->size());D3D11_SUBRESOURCE_DATA init{};init.pSysMem=padded.data();ComPtr<ID3D11Buffer>b;if(FAILED(d->CreateBuffer(&desc,&init,&b)))return doof::Failure<std::string>{"Failed to create shader buffer"};return doof::Success<std::shared_ptr<NativeShaderBuffer>>{std::make_shared<NativeShaderBuffer>(d,b.Get(),static_cast<int32_t>(data->size()))};}NativeShaderBuffer::NativeShaderBuffer(void*d,void*b,int32_t s):impl_(std::make_shared<Impl>(d,b,s)){}NativeShaderBuffer::~NativeShaderBuffer()=default;int32_t NativeShaderBuffer::byteLength()const{return impl_->size;}int64_t NativeShaderBuffer::metalBufferHandle()const{return handle(impl_->buffer.Get());}

struct NativeShaderPipeline::Impl{};doof::Result<std::shared_ptr<NativeShaderPipeline>,std::string> NativeShaderPipeline::create(int64_t,const std::string&,const std::string&,const std::string&,const std::string&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&){return doof::Failure<std::string>{"Custom HLSL shaders are not implemented by the Windows D3D11 backend"};}NativeShaderPipeline::NativeShaderPipeline(void*,void*,void*,void*,std::string,std::string):impl_(std::make_shared<Impl>()){}NativeShaderPipeline::~NativeShaderPipeline()=default;doof::Result<int64_t,std::string> NativeShaderPipeline::metalPipelineHandle(int32_t,bool,bool){return doof::Failure<std::string>{"Custom shader pipelines are not implemented on Windows"};}

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
    std::shared_ptr<NativeShaderPipeline>,
    const std::shared_ptr<std::vector<int32_t>>&,
    const std::shared_ptr<std::vector<int64_t>>&,
    const std::shared_ptr<std::vector<int32_t>>&,
    const std::shared_ptr<std::vector<int32_t>>&,
    const std::shared_ptr<std::vector<int64_t>>&,
    const std::shared_ptr<std::vector<int32_t>>&,
    const std::shared_ptr<std::vector<int32_t>>&,
    const std::shared_ptr<std::vector<int64_t>>&,
    const std::shared_ptr<std::vector<int32_t>>&,
    const std::shared_ptr<std::vector<int32_t>>&,
    const std::shared_ptr<std::vector<int64_t>>&,
    int64_t,int32_t,int32_t,int32_t,int64_t,int32_t,bool,bool
) { return doof::Failure<std::string>{"Custom shader drawing is not implemented on Windows"}; }

} // namespace doof_game
