#include "native_mesh.hpp"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

// WebGL mesh, sky-map, and space-dust implementation selected for the Wasm
// target. The public Doof API remains the shared std/game API; the historic
// metal*Handle method names are ABI slots and carry opaque WebGL resource IDs.
#if defined(__EMSCRIPTEN__)
extern "C" {
__attribute__((import_module("doof_game"), import_name("mesh_create")))
int32_t doof_game_mesh_create(int32_t window, const double* vertices, int32_t vertex_values,
    const uint16_t* indices, int32_t index_count);
__attribute__((import_module("doof_game"), import_name("dust_create")))
int32_t doof_game_dust_create(int32_t window, const double* particles, int32_t particle_values);
__attribute__((import_module("doof_game"), import_name("resource_delete")))
void doof_game_resource_delete(int32_t window, int32_t kind, int32_t resource);
__attribute__((import_module("doof_game"), import_name("draw_mesh")))
void doof_game_draw_mesh(int32_t window, int32_t mesh, int32_t texture, int32_t textured,
    int32_t blend_mode, const double* view_projection, const double* model, const double* normal,
    double ambient, double directional, double light_x, double light_y, double light_z,
    double red, double green, double blue, double alpha);
__attribute__((import_module("doof_game"), import_name("draw_sky")))
void doof_game_draw_sky(int32_t window, int32_t texture, int32_t pixel_width, int32_t pixel_height,
    double fov_y, double exposure, const double* rotation);
__attribute__((import_module("doof_game"), import_name("draw_dust")))
void doof_game_draw_dust(int32_t window, int32_t dust, int32_t particle_count, int32_t pixel_height,
    double camera_x, double camera_y, double camera_z, double field_size, double particle_size,
    double fade_start, double fade_end, double opacity, double red, double green, double blue,
    const double* camera_matrix);
}
#endif

namespace doof_game {
namespace {

struct VertexValues { std::vector<double> values; std::vector<uint16_t> indices; };
void matrix4(double* out,double m00,double m01,double m02,double m03,double m10,double m11,double m12,double m13,double m20,double m21,double m22,double m23,double m30,double m31,double m32,double m33){double values[16]={m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33};for(int i=0;i<16;++i)out[i]=values[i];}
void matrix3(double* out,double m00,double m01,double m02,double m10,double m11,double m12,double m20,double m21,double m22){double values[9]={m00,m01,m02,m10,m11,m12,m20,m21,m22};for(int i=0;i<9;++i)out[i]=values[i];}

}  // namespace

struct NativeSimpleMesh::Impl{int32_t window=0,resource=0,vertexCount=0,indexCount=0;Impl(int32_t w,int32_t r,int32_t vc,int32_t ic):window(w),resource(r),vertexCount(vc),indexCount(ic){}};
NativeSimpleMesh::NativeSimpleMesh(void* device,void* vertexBuffer,void*,int32_t vertexCount,int32_t indexCount):impl_(std::make_shared<Impl>(static_cast<int32_t>(reinterpret_cast<std::uintptr_t>(device)),static_cast<int32_t>(reinterpret_cast<std::uintptr_t>(vertexBuffer)),vertexCount,indexCount)){}NativeSimpleMesh::~NativeSimpleMesh(){if(impl_.use_count()==1&&impl_->resource)doof_game_resource_delete(impl_->window,0,impl_->resource);}int32_t NativeSimpleMesh::vertexCount()const{return impl_->vertexCount;}int32_t NativeSimpleMesh::indexCount()const{return impl_->indexCount;}int64_t NativeSimpleMesh::metalDeviceHandle()const{return impl_->window;}int64_t NativeSimpleMesh::metalVertexBufferHandle()const{return impl_->resource;}int64_t NativeSimpleMesh::metalIndexBufferHandle()const{return impl_->resource;}
struct NativeSimpleMeshBuilder::Impl{VertexValues data;};std::shared_ptr<NativeSimpleMeshBuilder> NativeSimpleMeshBuilder::create(){return std::make_shared<NativeSimpleMeshBuilder>();}NativeSimpleMeshBuilder::NativeSimpleMeshBuilder():impl_(std::make_shared<Impl>()){}NativeSimpleMeshBuilder::~NativeSimpleMeshBuilder()=default;
int32_t NativeSimpleMeshBuilder::addVertex(double x,double y,double z,double red,double green,double blue,double alpha,double u,double v,double nx,double ny,double nz){auto& values=impl_->data.values;values.insert(values.end(),{x,y,z,red,green,blue,alpha,u,v,nx,ny,nz});return static_cast<int32_t>(values.size()/12-1);}std::shared_ptr<NativeSimpleMeshBuilder> NativeSimpleMeshBuilder::addTriangle(int32_t a,int32_t b,int32_t c){if(a>=0&&b>=0&&c>=0&&a<65536&&b<65536&&c<65536){impl_->data.indices.push_back(a);impl_->data.indices.push_back(b);impl_->data.indices.push_back(c);}return shared_from_this();}
doof::Result<std::shared_ptr<NativeSimpleMesh>,std::string> NativeSimpleMeshBuilder::build(int64_t window){if(impl_->data.values.empty())return doof::Failure<std::string>{"Simple mesh has no vertices"};if(impl_->data.indices.empty())return doof::Failure<std::string>{"Simple mesh has no triangles"};int32_t resource=doof_game_mesh_create(window,impl_->data.values.data(),impl_->data.values.size(),impl_->data.indices.data(),impl_->data.indices.size());if(!resource)return doof::Failure<std::string>{"Failed to create WebGL mesh"};return doof::Success<std::shared_ptr<NativeSimpleMesh>>{std::make_shared<NativeSimpleMesh>(reinterpret_cast<void*>(static_cast<std::uintptr_t>(window)),reinterpret_cast<void*>(static_cast<std::uintptr_t>(resource)),nullptr,impl_->data.values.size()/12,impl_->data.indices.size())};}

struct NativeSpaceDust::Impl{int32_t window=0,resource=0,count=0;Impl(int32_t w,int32_t r,int32_t c):window(w),resource(r),count(c){}};NativeSpaceDust::NativeSpaceDust(void* device,void* buffer,int32_t count):impl_(std::make_shared<Impl>(static_cast<int32_t>(reinterpret_cast<std::uintptr_t>(device)),static_cast<int32_t>(reinterpret_cast<std::uintptr_t>(buffer)),count)){}NativeSpaceDust::~NativeSpaceDust(){if(impl_.use_count()==1&&impl_->resource)doof_game_resource_delete(impl_->window,1,impl_->resource);}int32_t NativeSpaceDust::particleCount()const{return impl_->count;}int64_t NativeSpaceDust::metalDeviceHandle()const{return impl_->window;}int64_t NativeSpaceDust::metalParticleBufferHandle()const{return impl_->resource;}
struct NativeSpaceDustBuilder::Impl{std::vector<double> values;};std::shared_ptr<NativeSpaceDustBuilder> NativeSpaceDustBuilder::create(){return std::make_shared<NativeSpaceDustBuilder>();}NativeSpaceDustBuilder::NativeSpaceDustBuilder():impl_(std::make_shared<Impl>()){}NativeSpaceDustBuilder::~NativeSpaceDustBuilder()=default;std::shared_ptr<NativeSpaceDustBuilder> NativeSpaceDustBuilder::addParticle(double x,double y,double z,double brightness){impl_->values.insert(impl_->values.end(),{x,y,z,brightness});return shared_from_this();}doof::Result<std::shared_ptr<NativeSpaceDust>,std::string> NativeSpaceDustBuilder::build(int64_t window){if(impl_->values.empty())return doof::Failure<std::string>{"Space dust has no particles"};int32_t resource=doof_game_dust_create(window,impl_->values.data(),impl_->values.size());if(!resource)return doof::Failure<std::string>{"Failed to create WebGL dust"};return doof::Success<std::shared_ptr<NativeSpaceDust>>{std::make_shared<NativeSpaceDust>(reinterpret_cast<void*>(static_cast<std::uintptr_t>(window)),reinterpret_cast<void*>(static_cast<std::uintptr_t>(resource)),impl_->values.size()/4)};}

#define MESH_ARGS double m00,double m01,double m02,double m03,double m10,double m11,double m12,double m13,double m20,double m21,double m22,double m23,double m30,double m31,double m32,double m33,double modelM00,double modelM01,double modelM02,double modelM03,double modelM10,double modelM11,double modelM12,double modelM13,double modelM20,double modelM21,double modelM22,double modelM23,double modelM30,double modelM31,double modelM32,double modelM33,double n00,double n01,double n02,double n10,double n11,double n12,double n20,double n21,double n22,double ambient,double directional,double lightX,double lightY,double lightZ,double,double,double,double red,double green,double blue,double alpha,double,double,double,double,double,double,double,double,double
void drawNativeSimpleMesh(std::shared_ptr<NativeSimpleMesh> mesh,int64_t window,int64_t,int32_t blend,bool,bool,MESH_ARGS){double view[16],model[16],normal[9];matrix4(view,m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33);matrix4(model,modelM00,modelM01,modelM02,modelM03,modelM10,modelM11,modelM12,modelM13,modelM20,modelM21,modelM22,modelM23,modelM30,modelM31,modelM32,modelM33);matrix3(normal,n00,n01,n02,n10,n11,n12,n20,n21,n22);doof_game_draw_mesh(window,mesh->metalVertexBufferHandle(),0,0,blend,view,model,normal,ambient,directional,lightX,lightY,lightZ,red,green,blue,alpha);}
void drawNativeTexturedSimpleMesh(std::shared_ptr<NativeSimpleMesh> mesh,int64_t texture,int64_t window,int64_t,int32_t blend,bool,bool,MESH_ARGS){double view[16],model[16],normal[9];matrix4(view,m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33);matrix4(model,modelM00,modelM01,modelM02,modelM03,modelM10,modelM11,modelM12,modelM13,modelM20,modelM21,modelM22,modelM23,modelM30,modelM31,modelM32,modelM33);matrix3(normal,n00,n01,n02,n10,n11,n12,n20,n21,n22);doof_game_draw_mesh(window,mesh->metalVertexBufferHandle(),texture,1,blend,view,model,normal,ambient,directional,lightX,lightY,lightZ,red,green,blue,alpha);}
#undef MESH_ARGS

void drawNativeEquirectangularSkyMap(int64_t texture,int64_t window,int64_t,bool,int32_t width,int32_t height,double fovY,double exposure,double m00,double m01,double m02,double m10,double m11,double m12,double m20,double m21,double m22){double rotation[9];matrix3(rotation,m00,m01,m02,m10,m11,m12,m20,m21,m22);doof_game_draw_sky(window,texture,width,height,fovY,exposure,rotation);}
void drawNativeSpaceDust(std::shared_ptr<NativeSpaceDust> dust,int64_t window,int64_t,bool,int32_t,int32_t height,double cameraX,double cameraY,double cameraZ,double fieldSize,double particleSize,double fadeStart,double fadeEnd,double opacity,double red,double green,double blue,double m00,double m01,double m02,double m03,double m10,double m11,double m12,double m13,double m20,double m21,double m22,double m23,double m30,double m31,double m32,double m33){double matrix[16];matrix4(matrix,m00,m01,m02,m03,m10,m11,m12,m13,m20,m21,m22,m23,m30,m31,m32,m33);doof_game_draw_dust(window,dust->metalParticleBufferHandle(),dust->particleCount(),height,cameraX,cameraY,cameraZ,fieldSize,particleSize,fadeStart,fadeEnd,opacity,red,green,blue,matrix);}

}  // namespace doof_game
