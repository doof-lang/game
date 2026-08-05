#include "native_mesh.hpp"

#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
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
template <typename T> doof::Result<ComPtr<ID3D11Buffer>, std::string> immutableBuffer(ID3D11Device* device, const std::vector<T>& values, UINT bind) {
    if (!device || values.empty()) return doof::Failure<std::string>{"Cannot create an empty D3D11 buffer"};
    D3D11_BUFFER_DESC desc{}; desc.ByteWidth = static_cast<UINT>(values.size() * sizeof(T)); desc.Usage = D3D11_USAGE_IMMUTABLE; desc.BindFlags = bind;
    D3D11_SUBRESOURCE_DATA data{}; data.pSysMem = values.data(); ComPtr<ID3D11Buffer> buffer;
    if (FAILED(device->CreateBuffer(&desc, &data, &buffer))) return doof::Failure<std::string>{"Failed to create D3D11 buffer"};
    return doof::Success<ComPtr<ID3D11Buffer>>{buffer};
}

struct MeshConstants {
    float matrix[16];
    float tint[4];
    float whiteBlend;
    float uvOffset[2];
    float uvOffsetPadding;
    float uvScale[2];
    float padding[2]{};
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

std::mutex pipelineMutex;
std::unordered_map<ID3D11Device*, std::shared_ptr<MeshPipeline>> pipelines;

ComPtr<ID3DBlob> compileShader(const char* source, const char* entry, const char* target) {
    ComPtr<ID3DBlob> code, errors;
    if (FAILED(D3DCompile(source, std::strlen(source), "std/game built-in", nullptr, nullptr,
        entry, target, D3DCOMPILE_ENABLE_STRICTNESS, 0, &code, &errors))) return {};
    return code;
}

std::shared_ptr<MeshPipeline> meshPipeline(ID3D11Device* device) {
    std::lock_guard<std::mutex> lock(pipelineMutex);
    auto found = pipelines.find(device); if (found != pipelines.end()) return found->second;
    static const char* shader = R"(
cbuffer MeshConstants : register(b0) {
  row_major float4x4 transformMatrix;
  float4 tint;
  float whiteBlend;
  float2 uvOffset;
  float2 uvScale;
};
struct VertexIn { float3 position : POSITION; float4 color : COLOR; float2 uv : TEXCOORD; float3 normal : NORMAL; };
struct VertexOut { float4 position : SV_POSITION; float4 color : COLOR; float2 uv : TEXCOORD; };
VertexOut vertexMain(VertexIn input) {
  VertexOut output;
  output.position = mul(transformMatrix, float4(input.position, 1.0));
  output.color = lerp(input.color, float4(1.0, 1.0, 1.0, input.color.a), whiteBlend) * tint;
  output.uv = input.uv * uvScale + uvOffset;
  return output;
}
float4 colorMain(VertexOut input) : SV_TARGET { return input.color; }
Texture2D texture0 : register(t0); SamplerState sampler0 : register(s0);
float4 textureMain(VertexOut input) : SV_TARGET { return texture0.Sample(sampler0, input.uv) * input.color; }
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

void drawMesh(std::shared_ptr<NativeSimpleMesh> mesh, ID3D11ShaderResourceView* texture,
    ID3D11DeviceContext* context, ID3D11Device* device, int32_t blendMode,
    const double* matrix, double red, double green, double blue, double alpha,
    double whiteBlend, double uvOffsetX, double uvOffsetY, double uvScaleX, double uvScaleY) {
    if(!mesh||mesh->indexCount()<=0||!context||!device)return;auto pipeline=meshPipeline(device);if(!pipeline)return;
    MeshConstants values{};for(int i=0;i<16;++i)values.matrix[i]=float(matrix[i]);values.tint[0]=float(red);values.tint[1]=float(green);values.tint[2]=float(blue);values.tint[3]=float(alpha);values.whiteBlend=float(whiteBlend);values.uvOffset[0]=float(uvOffsetX);values.uvOffset[1]=float(uvOffsetY);values.uvScale[0]=float(uvScaleX);values.uvScale[1]=float(uvScaleY);
    D3D11_MAPPED_SUBRESOURCE mapped{};if(FAILED(context->Map(pipeline->constants.Get(),0,D3D11_MAP_WRITE_DISCARD,0,&mapped)))return;std::memcpy(mapped.pData,&values,sizeof(values));context->Unmap(pipeline->constants.Get(),0);
    auto* vb=reinterpret_cast<ID3D11Buffer*>(mesh->metalVertexBufferHandle());auto* ib=reinterpret_cast<ID3D11Buffer*>(mesh->metalIndexBufferHandle());UINT stride=sizeof(Vertex),offset=0;context->IASetInputLayout(pipeline->layout.Get());context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);context->IASetVertexBuffers(0,1,&vb,&stride,&offset);context->IASetIndexBuffer(ib,DXGI_FORMAT_R32_UINT,0);context->VSSetShader(pipeline->vertex.Get(),nullptr,0);ID3D11Buffer*cb=pipeline->constants.Get();context->VSSetConstantBuffers(0,1,&cb);context->PSSetConstantBuffers(0,1,&cb);context->PSSetShader(texture?pipeline->textureFragment.Get():pipeline->colorFragment.Get(),nullptr,0);context->PSSetShaderResources(0,1,&texture);ID3D11SamplerState*sampler=pipeline->sampler.Get();context->PSSetSamplers(0,1,&sampler);float factor[4]{};context->OMSetBlendState(blendMode==1?pipeline->alphaBlend.Get():nullptr,factor,0xffffffff);context->DrawIndexed(mesh->indexCount(),0,0);ID3D11ShaderResourceView*none=nullptr;context->PSSetShaderResources(0,1,&none);
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
doof::Result<std::shared_ptr<NativeSimpleModelBatch>,std::string> NativeSimpleModelBatch::create(int64_t dh,int32_t capacity){auto*d=reinterpret_cast<ID3D11Device*>(dh);if(!d||capacity<=0)return doof::Failure<std::string>{"Model batch capacity must be positive"};D3D11_BUFFER_DESC desc{};desc.ByteWidth=UINT(capacity*sizeof(Instance));desc.Usage=D3D11_USAGE_DYNAMIC;desc.BindFlags=D3D11_BIND_VERTEX_BUFFER;desc.CPUAccessFlags=D3D11_CPU_ACCESS_WRITE;ComPtr<ID3D11Buffer>b;if(FAILED(d->CreateBuffer(&desc,nullptr,&b)))return doof::Failure<std::string>{"Failed to create model batch buffer"};return doof::Success<std::shared_ptr<NativeSimpleModelBatch>>{std::make_shared<NativeSimpleModelBatch>(d,b.Get(),capacity)};}
NativeSimpleModelBatch::NativeSimpleModelBatch(void*d,void*b,int32_t c):impl_(std::make_shared<Impl>(d,b,c)){} NativeSimpleModelBatch::~NativeSimpleModelBatch()=default;int32_t NativeSimpleModelBatch::capacity()const{return static_cast<int32_t>(impl_->instances.size());}int32_t NativeSimpleModelBatch::count()const{return impl_->count;}void NativeSimpleModelBatch::setCount(int32_t c){impl_->count=std::clamp(c,0,capacity());}
void NativeSimpleModelBatch::setInstance(int32_t slot,double m00,double m01,double m02,double m03,double m10,double m11,double m12,double m13,double m20,double m21,double m22,double m23,double m30,double m31,double m32,double m33,double n00,double n01,double n02,double n10,double n11,double n12,double n20,double n21,double n22,double r,double g,double b,double a,double white,double ux,double uy,double sx,double sy,double spec,double shine,double fresnel,double power){if(slot<0||slot>=capacity())return;auto&i=impl_->instances[slot];double m[]={m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33};for(int x=0;x<16;++x)i.model[x]=float(m[x]);double n[]={n00,n01,n02,0,n10,n11,n12,0,n20,n21,n22,0};for(int x=0;x<12;++x)i.normal[x]=float(n[x]);i.color[0]=float(r);i.color[1]=float(g);i.color[2]=float(b);i.color[3]=float(a);i.whiteBlend=float(white);i.uvOffset[0]=float(ux);i.uvOffset[1]=float(uy);i.uvScale[0]=float(sx);i.uvScale[1]=float(sy);i.specular=float(spec);i.shininess=float(shine);i.fresnel=float(fresnel);i.fresnelPower=float(power);}
int64_t NativeSimpleModelBatch::metalInstanceBufferHandle()const{return handle(impl_->buffer.Get());}

struct NativeSpaceDust::Impl { ComPtr<ID3D11Device> device;ComPtr<ID3D11Buffer>buffer;int32_t count;Impl(void*d,void*b,int32_t c):device(static_cast<ID3D11Device*>(d)),buffer(static_cast<ID3D11Buffer*>(b)),count(c){} };struct NativeSpaceDustBuilder::Impl{std::vector<Particle>particles;};
NativeSpaceDust::NativeSpaceDust(void*d,void*b,int32_t c):impl_(std::make_shared<Impl>(d,b,c)){}NativeSpaceDust::~NativeSpaceDust()=default;int32_t NativeSpaceDust::particleCount()const{return impl_->count;}int64_t NativeSpaceDust::metalDeviceHandle()const{return handle(impl_->device.Get());}int64_t NativeSpaceDust::metalParticleBufferHandle()const{return handle(impl_->buffer.Get());}
std::shared_ptr<NativeSpaceDustBuilder> NativeSpaceDustBuilder::create(){return std::make_shared<NativeSpaceDustBuilder>();}NativeSpaceDustBuilder::NativeSpaceDustBuilder():impl_(std::make_shared<Impl>()){}NativeSpaceDustBuilder::~NativeSpaceDustBuilder()=default;std::shared_ptr<NativeSpaceDustBuilder> NativeSpaceDustBuilder::addParticle(double x,double y,double z,double b){impl_->particles.push_back(Particle{{float(x),float(y),float(z)},float(b)});return shared_from_this();}doof::Result<std::shared_ptr<NativeSpaceDust>,std::string> NativeSpaceDustBuilder::build(int64_t dh){auto*d=reinterpret_cast<ID3D11Device*>(dh);auto b=immutableBuffer(d,impl_->particles,D3D11_BIND_VERTEX_BUFFER);if(!doof::is_success(b))return doof::Failure<std::string>{doof::failure_error(b)};return doof::Success<std::shared_ptr<NativeSpaceDust>>{std::make_shared<NativeSpaceDust>(d,doof::success_value(b).Get(),static_cast<int32_t>(impl_->particles.size()))};}

struct NativeShaderBuffer::Impl{ComPtr<ID3D11Device>device;ComPtr<ID3D11Buffer>buffer;int32_t size;Impl(void*d,void*b,int32_t s):device(static_cast<ID3D11Device*>(d)),buffer(static_cast<ID3D11Buffer*>(b)),size(s){}};
doof::Result<std::shared_ptr<NativeShaderBuffer>,std::string> NativeShaderBuffer::create(int64_t dh,const std::shared_ptr<std::vector<uint8_t>>&data){auto*d=reinterpret_cast<ID3D11Device*>(dh);if(!d||!data||data->empty())return doof::Failure<std::string>{"Shader buffer data is empty"};D3D11_BUFFER_DESC desc{};desc.ByteWidth=UINT((data->size()+15)&~size_t(15));desc.Usage=D3D11_USAGE_DEFAULT;desc.BindFlags=D3D11_BIND_CONSTANT_BUFFER;std::vector<uint8_t>padded(desc.ByteWidth);std::memcpy(padded.data(),data->data(),data->size());D3D11_SUBRESOURCE_DATA init{};init.pSysMem=padded.data();ComPtr<ID3D11Buffer>b;if(FAILED(d->CreateBuffer(&desc,&init,&b)))return doof::Failure<std::string>{"Failed to create shader buffer"};return doof::Success<std::shared_ptr<NativeShaderBuffer>>{std::make_shared<NativeShaderBuffer>(d,b.Get(),static_cast<int32_t>(data->size()))};}NativeShaderBuffer::NativeShaderBuffer(void*d,void*b,int32_t s):impl_(std::make_shared<Impl>(d,b,s)){}NativeShaderBuffer::~NativeShaderBuffer()=default;int32_t NativeShaderBuffer::byteLength()const{return impl_->size;}int64_t NativeShaderBuffer::metalBufferHandle()const{return handle(impl_->buffer.Get());}

struct NativeShaderPipeline::Impl{};doof::Result<std::shared_ptr<NativeShaderPipeline>,std::string> NativeShaderPipeline::create(int64_t,const std::string&,const std::string&,const std::string&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&,const std::shared_ptr<std::vector<int32_t>>&){return doof::Failure<std::string>{"Metal shader source is not supported by the Windows D3D11 backend"};}NativeShaderPipeline::NativeShaderPipeline(void*,void*,void*,std::string,std::string):impl_(std::make_shared<Impl>()){}NativeShaderPipeline::~NativeShaderPipeline()=default;doof::Result<int64_t,std::string> NativeShaderPipeline::metalPipelineHandle(int32_t,bool,bool){return doof::Failure<std::string>{"Metal shader pipelines are not supported on Windows"};}

void drawNativeSimpleMesh(
    std::shared_ptr<NativeSimpleMesh> mesh, int64_t contextHandle, int64_t deviceHandle, int32_t blendMode, bool, bool,
    double m00,double m01,double m02,double m03,double m10,double m11,double m12,double m13,double m20,double m21,double m22,double m23,double m30,double m31,double m32,double m33,
    double modelM00,double modelM01,double modelM02,double modelM03,double modelM10,double modelM11,double modelM12,double modelM13,double modelM20,double modelM21,double modelM22,double modelM23,double modelM30,double modelM31,double modelM32,double modelM33,
    double,double,double,double,double,double,double,double,double,
    double,double,double,double,double,double,double,double,
    double red,double green,double blue,double alpha,double whiteBlend,double uvOffsetX,double uvOffsetY,double uvScaleX,double uvScaleY,double,double,double,double
) { double viewProjection[]={m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33};double model[]={modelM00,modelM01,modelM02,modelM03,modelM10,modelM11,modelM12,modelM13,modelM20,modelM21,modelM22,modelM23,modelM30,modelM31,modelM32,modelM33};auto matrix=multiplyMatrices(viewProjection,model);drawMesh(std::move(mesh),nullptr,reinterpret_cast<ID3D11DeviceContext*>(contextHandle),reinterpret_cast<ID3D11Device*>(deviceHandle),blendMode,matrix.data(),red,green,blue,alpha,whiteBlend,uvOffsetX,uvOffsetY,uvScaleX,uvScaleY); }

void drawNativeTexturedSimpleMesh(
    std::shared_ptr<NativeSimpleMesh> mesh, int64_t textureHandle, int64_t contextHandle, int64_t deviceHandle, int32_t blendMode, bool, bool,
    double m00,double m01,double m02,double m03,double m10,double m11,double m12,double m13,double m20,double m21,double m22,double m23,double m30,double m31,double m32,double m33,
    double modelM00,double modelM01,double modelM02,double modelM03,double modelM10,double modelM11,double modelM12,double modelM13,double modelM20,double modelM21,double modelM22,double modelM23,double modelM30,double modelM31,double modelM32,double modelM33,
    double,double,double,double,double,double,double,double,double,
    double,double,double,double,double,double,double,double,
    double red,double green,double blue,double alpha,double whiteBlend,double uvOffsetX,double uvOffsetY,double uvScaleX,double uvScaleY,double,double,double,double
) { double viewProjection[]={m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33};double model[]={modelM00,modelM01,modelM02,modelM03,modelM10,modelM11,modelM12,modelM13,modelM20,modelM21,modelM22,modelM23,modelM30,modelM31,modelM32,modelM33};auto matrix=multiplyMatrices(viewProjection,model);drawMesh(std::move(mesh),reinterpret_cast<ID3D11ShaderResourceView*>(textureHandle),reinterpret_cast<ID3D11DeviceContext*>(contextHandle),reinterpret_cast<ID3D11Device*>(deviceHandle),blendMode,matrix.data(),red,green,blue,alpha,whiteBlend,uvOffsetX,uvOffsetY,uvScaleX,uvScaleY); }

void drawNativeSimpleModelBatch(
    std::shared_ptr<NativeSimpleMesh>, std::shared_ptr<NativeSimpleModelBatch>, int64_t, bool,
    int64_t, int64_t, int32_t, bool, bool,
    double,double,double,double,double,double,double,double,double,double,double,double,double,double,double,double,
    double,double,double,double,double,double,double,double
) {}

void drawNativeEquirectangularSkyMap(
    int64_t,int64_t,int64_t,bool,int32_t,int32_t,double,double,
    double,double,double,double,double,double,double,double,double
) {}

void drawNativeSpaceDust(
    std::shared_ptr<NativeSpaceDust>,int64_t,int64_t,bool,int32_t,int32_t,
    double,double,double,double,double,double,double,double,double,double,double,
    double,double,double,double,double,double,double,double,double,double,double,double,double,double,double,double
) {}

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
) { return doof::Failure<std::string>{"Metal shader drawing is not supported on Windows"}; }

} // namespace doof_game
