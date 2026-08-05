#include "native_game.hpp"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <windowsx.h>
#include <d3d11.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <mutex>
#include <set>

using Microsoft::WRL::ComPtr;

namespace doof_game {
struct AppRuntime;
namespace {

constexpr int32_t kKindClose = 0, kKindResized = 1, kKindKeyDown = 2, kKindKeyUp = 3;
constexpr int32_t kKindMouseDown = 4, kKindMouseUp = 5, kKindMouseMove = 6, kKindScroll = 7;
constexpr int32_t kKeyUnknown = 0;
constexpr int32_t kControllerSlots = 4, kControllerButtons = 16, kControllerAxes = 6;

std::mutex gAppMutex;
std::weak_ptr<AppRuntime> gRunningApp;

std::string windowsError(const char* action, HRESULT error = HRESULT_FROM_WIN32(GetLastError())) {
    char buffer[256] = {};
    FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, nullptr,
        static_cast<DWORD>(error), 0, buffer, static_cast<DWORD>(sizeof(buffer)), nullptr);
    return std::string(action) + (buffer[0] ? ": " + std::string(buffer) : " failed");
}

std::wstring wide(const std::string& value) {
    if (value.empty()) return {};
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), nullptr, 0);
    if (count <= 0) return {};
    std::wstring result(static_cast<size_t>(count), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), result.data(), count);
    return result;
}

int32_t mapKey(WPARAM key) {
    if (key >= 'A' && key <= 'Z') return 1 + static_cast<int32_t>(key - 'A');
    if (key >= '0' && key <= '9') return 27 + static_cast<int32_t>(key - '0');
    switch (key) {
        case VK_LEFT: return 37; case VK_RIGHT: return 38; case VK_UP: return 39; case VK_DOWN: return 40;
        case VK_ESCAPE: return 41; case VK_RETURN: return 42; case VK_SPACE: return 43;
        case VK_BACK: return 44; case VK_TAB: return 45; case VK_SHIFT: return 46;
        case VK_CONTROL: return 47; case VK_MENU: return 48; case VK_LWIN: case VK_RWIN: return 49;
        case VK_F1: return 50; case VK_F2: return 51; case VK_F3: return 52; case VK_F4: return 53;
        case VK_F5: return 54; case VK_F6: return 55; case VK_F7: return 56; case VK_F8: return 57;
        case VK_F9: return 58; case VK_F10: return 59; case VK_F11: return 60; case VK_F12: return 61;
        default: return kKeyUnknown;
    }
}

template <typename T> int64_t handle(T* value) { return reinterpret_cast<int64_t>(value); }

} // namespace

struct NativeGameSurface::Impl {
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    ComPtr<IDXGISwapChain> swapChain;
    explicit Impl(void* d, void* c, void* s) : device(static_cast<ID3D11Device*>(d)),
        context(static_cast<ID3D11DeviceContext*>(c)), swapChain(static_cast<IDXGISwapChain*>(s)) {}
};

NativeGameSurface::NativeGameSurface(void* d, void* q, void* layer) : impl_(std::make_shared<Impl>(d, q, layer)) {}
NativeGameSurface::~NativeGameSurface() = default;
int32_t NativeGameSurface::pixelWidth() const { DXGI_SWAP_CHAIN_DESC d{}; RECT r{}; return SUCCEEDED(impl_->swapChain->GetDesc(&d)) && GetClientRect(d.OutputWindow,&r) ? std::max<LONG>(1,r.right-r.left) : 1; }
int32_t NativeGameSurface::pixelHeight() const { DXGI_SWAP_CHAIN_DESC d{}; RECT r{}; return SUCCEEDED(impl_->swapChain->GetDesc(&d)) && GetClientRect(d.OutputWindow,&r) ? std::max<LONG>(1,r.bottom-r.top) : 1; }
double NativeGameSurface::scale() const { DXGI_SWAP_CHAIN_DESC d{}; return SUCCEEDED(impl_->swapChain->GetDesc(&d)) && d.OutputWindow ? double(GetDpiForWindow(d.OutputWindow)) / 96.0 : 1.0; }
int64_t NativeGameSurface::metalDeviceHandle() const { return handle(impl_->device.Get()); }
int64_t NativeGameSurface::metalCommandQueueHandle() const { return handle(impl_->context.Get()); }
int64_t NativeGameSurface::metalLayerHandle() const { return handle(impl_->swapChain.Get()); }

struct NativeTexture::Impl {
    ComPtr<ID3D11Texture2D> texture;
    ComPtr<ID3D11ShaderResourceView> view;
    int32_t width = 0, height = 0;
    Impl(ID3D11Texture2D* t, int32_t w, int32_t h) : texture(t), width(w), height(h) {
        ComPtr<ID3D11Device> device; if (texture) { texture->GetDevice(&device); if (device) device->CreateShaderResourceView(texture.Get(), nullptr, &view); }
    }
};

static doof::Result<std::shared_ptr<NativeTexture>, std::string> createTexture(
    ID3D11Device* device, const uint8_t* rgba, int32_t width, int32_t height) {
    if (!device) return doof::Failure<std::string>{"D3D11 device handle is invalid"};
    if (!rgba || width <= 0 || height <= 0) return doof::Failure<std::string>{"Texture data or dimensions are invalid"};
    D3D11_TEXTURE2D_DESC desc{}; desc.Width = static_cast<UINT>(width); desc.Height = static_cast<UINT>(height);
    desc.MipLevels = 1; desc.ArraySize = 1; desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1; desc.Usage = D3D11_USAGE_IMMUTABLE; desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA initial{}; initial.pSysMem = rgba; initial.SysMemPitch = static_cast<UINT>(width * 4);
    ComPtr<ID3D11Texture2D> texture;
    HRESULT hr = device->CreateTexture2D(&desc, &initial, &texture);
    if (FAILED(hr)) return doof::Failure<std::string>{windowsError("Failed to create texture", hr)};
    auto result = std::make_shared<NativeTexture>(texture.Get(), width, height);
    if (!result->metalTextureHandle()) return doof::Failure<std::string>{"Failed to create texture view"};
    return doof::Success<std::shared_ptr<NativeTexture>>{result};
}

doof::Result<std::shared_ptr<NativeTexture>, std::string> NativeTexture::load(const std::string& path, int64_t deviceHandle) {
    HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    (void)init;
    ComPtr<IWICImagingFactory> factory;
    HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory));
    if (FAILED(hr)) return doof::Failure<std::string>{windowsError("Failed to initialize image decoder", hr)};
    ComPtr<IWICBitmapDecoder> decoder;
    std::wstring path16 = wide(path);
    hr = factory->CreateDecoderFromFilename(path16.c_str(), nullptr, GENERIC_READ,
        WICDecodeMetadataCacheOnDemand, &decoder);
    if (FAILED(hr)) return doof::Failure<std::string>{windowsError("Failed to load texture", hr)};
    ComPtr<IWICBitmapFrameDecode> frame; hr = decoder->GetFrame(0, &frame);
    if (FAILED(hr)) return doof::Failure<std::string>{windowsError("Failed to decode texture", hr)};
    ComPtr<IWICFormatConverter> converter; factory->CreateFormatConverter(&converter);
    hr = converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppRGBA, WICBitmapDitherTypeNone,
        nullptr, 0.0, WICBitmapPaletteTypeCustom);
    if (FAILED(hr)) return doof::Failure<std::string>{windowsError("Failed to convert texture", hr)};
    UINT w = 0, h = 0; converter->GetSize(&w, &h);
    if (!w || !h || w > 16384 || h > 16384) return doof::Failure<std::string>{"Texture dimensions are invalid"};
    std::vector<uint8_t> pixels(static_cast<size_t>(w) * h * 4);
    hr = converter->CopyPixels(nullptr, w * 4, static_cast<UINT>(pixels.size()), pixels.data());
    if (FAILED(hr)) return doof::Failure<std::string>{windowsError("Failed to read texture pixels", hr)};
    return createTexture(reinterpret_cast<ID3D11Device*>(deviceHandle), pixels.data(), static_cast<int32_t>(w), static_cast<int32_t>(h));
}

doof::Result<std::shared_ptr<NativeTexture>, std::string> NativeTexture::createRgba(
    const std::shared_ptr<std::vector<uint8_t>>& data, int32_t width, int32_t height, int32_t alphaMode, int64_t device) {
    if (!data || width <= 0 || height <= 0 || data->size() != static_cast<size_t>(width) * height * 4)
        return doof::Failure<std::string>{"RGBA texture buffer size does not match its dimensions"};
    if (alphaMode == 0) return createTexture(reinterpret_cast<ID3D11Device*>(device), data->data(), width, height);
    std::vector<uint8_t> straight(*data);
    for (size_t i = 0; i < straight.size(); i += 4) {
        uint8_t a = straight[i + 3];
        if (a) for (size_t c = 0; c < 3; ++c) straight[i + c] = static_cast<uint8_t>(std::min(255u, (static_cast<unsigned>(straight[i + c]) * 255u + a / 2u) / a));
    }
    return createTexture(reinterpret_cast<ID3D11Device*>(device), straight.data(), width, height);
}

doof::Result<std::shared_ptr<NativeTexture>, std::string> NativeTexture::createAlpha4(
    const std::shared_ptr<std::vector<uint8_t>>& data, int32_t width, int32_t height, int64_t device) {
    size_t count = width > 0 && height > 0 ? static_cast<size_t>(width) * height : 0;
    if (!data || !count || data->size() != (count + 1) / 2) return doof::Failure<std::string>{"Alpha4 texture buffer size does not match its dimensions"};
    std::vector<uint8_t> rgba(count * 4, 255);
    for (size_t i = 0; i < count; ++i) rgba[i * 4 + 3] = static_cast<uint8_t>(((i & 1) ? ((*data)[i / 2] & 15) : ((*data)[i / 2] >> 4)) * 17);
    return createTexture(reinterpret_cast<ID3D11Device*>(device), rgba.data(), width, height);
}
NativeTexture::NativeTexture(void* texture, int32_t width, int32_t height) : impl_(std::make_shared<Impl>(static_cast<ID3D11Texture2D*>(texture), width, height)) {}
NativeTexture::~NativeTexture() = default;
int32_t NativeTexture::pixelWidth() const { return impl_->width; }
int32_t NativeTexture::pixelHeight() const { return impl_->height; }
int64_t NativeTexture::metalTextureHandle() const { return handle(impl_->view.Get()); }

struct NativeDepthTexture::Impl { ComPtr<ID3D11Texture2D> texture; ComPtr<ID3D11DepthStencilView> view; int32_t width, height;
    Impl(ID3D11Texture2D* t, int32_t w, int32_t h) : texture(t), width(w), height(h) { ComPtr<ID3D11Device>d;if(texture){texture->GetDevice(&d);if(d)d->CreateDepthStencilView(texture.Get(),nullptr,&view);} } };
doof::Result<std::shared_ptr<NativeDepthTexture>, std::string> NativeDepthTexture::create(int32_t w, int32_t h, int64_t dh) {
    auto* device = reinterpret_cast<ID3D11Device*>(dh); if (!device || w <= 0 || h <= 0) return doof::Failure<std::string>{"Invalid depth texture arguments"};
    D3D11_TEXTURE2D_DESC d{}; d.Width=w; d.Height=h; d.MipLevels=1; d.ArraySize=1; d.Format=DXGI_FORMAT_D32_FLOAT; d.SampleDesc.Count=1; d.BindFlags=D3D11_BIND_DEPTH_STENCIL;
    ComPtr<ID3D11Texture2D> t; HRESULT hr=device->CreateTexture2D(&d,nullptr,&t); if(FAILED(hr)) return doof::Failure<std::string>{windowsError("Failed to create depth texture",hr)};
    auto n=std::make_shared<NativeDepthTexture>(t.Get(),w,h); if(!n->metalTextureHandle()) return doof::Failure<std::string>{"Failed to create depth view"};
    return doof::Success<std::shared_ptr<NativeDepthTexture>>{n};
}
NativeDepthTexture::NativeDepthTexture(void* t,int32_t w,int32_t h):impl_(std::make_shared<Impl>(static_cast<ID3D11Texture2D*>(t),w,h)){}
NativeDepthTexture::~NativeDepthTexture()=default; int32_t NativeDepthTexture::pixelWidth()const{return impl_->width;} int32_t NativeDepthTexture::pixelHeight()const{return impl_->height;} int64_t NativeDepthTexture::metalTextureHandle()const{return handle(impl_->view.Get());}

struct NativeRenderPass::Impl { ComPtr<ID3D11DeviceContext> context; ComPtr<ID3D11Device> device; bool ended=false,color=false,depth=false;
    Impl(ID3D11DeviceContext* c,ID3D11Device* d,bool co,bool de):context(c),device(d),color(co),depth(de){} };
NativeRenderPass::NativeRenderPass(void* e,void*,void* d,int32_t,bool c,bool z):impl_(std::make_shared<Impl>(static_cast<ID3D11DeviceContext*>(e),static_cast<ID3D11Device*>(d),c,z)){}
NativeRenderPass::~NativeRenderPass()=default; void NativeRenderPass::end(){impl_->ended=true;} int64_t NativeRenderPass::metalRenderCommandEncoderHandle()const{return handle(impl_->context.Get());} int64_t NativeRenderPass::metalCommandBufferHandle()const{return handle(impl_->context.Get());} int64_t NativeRenderPass::metalDeviceHandle()const{return handle(impl_->device.Get());} bool NativeRenderPass::hasColorAttachment()const{return impl_->color;} bool NativeRenderPass::hasDepthAttachment()const{return impl_->depth;}

struct NativeRenderFrame::Impl { std::shared_ptr<NativeGameSurface> surface; ComPtr<ID3D11Device> device; ComPtr<ID3D11DeviceContext> context; ComPtr<IDXGISwapChain> swapChain; ComPtr<ID3D11RenderTargetView> target; ComPtr<ID3D11DepthStencilView> depth; bool committed=false;
    explicit Impl(std::shared_ptr<NativeGameSurface> s):surface(std::move(s)) { if(surface){device=reinterpret_cast<ID3D11Device*>(surface->metalDeviceHandle());context=reinterpret_cast<ID3D11DeviceContext*>(surface->metalCommandQueueHandle());swapChain=reinterpret_cast<IDXGISwapChain*>(surface->metalLayerHandle());} } };
std::shared_ptr<NativeRenderFrame> NativeRenderFrame::create(std::shared_ptr<NativeGameSurface>s){return std::shared_ptr<NativeRenderFrame>(new NativeRenderFrame(std::move(s)));}
NativeRenderFrame::NativeRenderFrame(std::shared_ptr<NativeGameSurface>s):impl_(std::make_shared<Impl>(std::move(s))){if(!impl_->swapChain)return; ComPtr<ID3D11Texture2D>b; if(SUCCEEDED(impl_->swapChain->GetBuffer(0,IID_PPV_ARGS(&b))))impl_->device->CreateRenderTargetView(b.Get(),nullptr,&impl_->target);}
NativeRenderFrame::~NativeRenderFrame()=default;
std::shared_ptr<NativeRenderPass> NativeRenderFrame::beginPass(int32_t clearKind,double r,double g,double b,double a,double clearDepth,int32_t depthMode,int32_t blend,int32_t windingMode,int32_t cullMode){
    bool needsDepth=depthMode!=0||clearKind==2||clearKind==3; if(needsDepth&&!impl_->depth){auto z=NativeDepthTexture::create(impl_->surface->pixelWidth(),impl_->surface->pixelHeight(),handle(impl_->device.Get()));if(doof::is_success(z))impl_->depth=reinterpret_cast<ID3D11DepthStencilView*>(doof::success_value(z)->metalTextureHandle());}
    ID3D11RenderTargetView* rt=impl_->target.Get(); impl_->context->OMSetRenderTargets(rt?1:0,rt?&rt:nullptr,impl_->depth.Get()); float color[4]={float(r),float(g),float(b),float(a)}; if(rt&&(clearKind==1||clearKind==3))impl_->context->ClearRenderTargetView(rt,color); if(impl_->depth&&(clearKind==2||clearKind==3))impl_->context->ClearDepthStencilView(impl_->depth.Get(),D3D11_CLEAR_DEPTH,float(clearDepth),0);
    D3D11_RASTERIZER_DESC raster{};raster.FillMode=D3D11_FILL_SOLID;raster.CullMode=cullMode==1?D3D11_CULL_FRONT:cullMode==2?D3D11_CULL_BACK:D3D11_CULL_NONE;raster.FrontCounterClockwise=windingMode==1;raster.DepthClipEnable=TRUE;ComPtr<ID3D11RasterizerState>rasterState;if(SUCCEEDED(impl_->device->CreateRasterizerState(&raster,&rasterState)))impl_->context->RSSetState(rasterState.Get());
    D3D11_DEPTH_STENCIL_DESC depth{};depth.DepthEnable=depthMode!=0;depth.DepthWriteMask=depthMode==2?D3D11_DEPTH_WRITE_MASK_ALL:D3D11_DEPTH_WRITE_MASK_ZERO;depth.DepthFunc=D3D11_COMPARISON_LESS_EQUAL;ComPtr<ID3D11DepthStencilState>depthState;if(SUCCEEDED(impl_->device->CreateDepthStencilState(&depth,&depthState)))impl_->context->OMSetDepthStencilState(depthState.Get(),0);
    D3D11_VIEWPORT vp{0,0,float(impl_->surface->pixelWidth()),float(impl_->surface->pixelHeight()),0,1}; impl_->context->RSSetViewports(1,&vp); return std::shared_ptr<NativeRenderPass>(new NativeRenderPass(impl_->context.Get(),impl_->context.Get(),impl_->device.Get(),blend,true,needsDepth));}
std::shared_ptr<NativeRenderPass> NativeRenderFrame::beginDepthPass(std::shared_ptr<NativeDepthTexture>z,double clearDepth,int32_t depthMode,int32_t blend,int32_t windingMode,int32_t cullMode){ID3D11DepthStencilView*v=z?reinterpret_cast<ID3D11DepthStencilView*>(z->metalTextureHandle()):nullptr;impl_->context->OMSetRenderTargets(0,nullptr,v);if(v)impl_->context->ClearDepthStencilView(v,D3D11_CLEAR_DEPTH,float(clearDepth),0);D3D11_RASTERIZER_DESC raster{};raster.FillMode=D3D11_FILL_SOLID;raster.CullMode=cullMode==1?D3D11_CULL_FRONT:cullMode==2?D3D11_CULL_BACK:D3D11_CULL_NONE;raster.FrontCounterClockwise=windingMode==1;raster.DepthClipEnable=TRUE;ComPtr<ID3D11RasterizerState>rs;if(SUCCEEDED(impl_->device->CreateRasterizerState(&raster,&rs)))impl_->context->RSSetState(rs.Get());D3D11_DEPTH_STENCIL_DESC depth{};depth.DepthEnable=TRUE;depth.DepthWriteMask=depthMode==2?D3D11_DEPTH_WRITE_MASK_ALL:D3D11_DEPTH_WRITE_MASK_ZERO;depth.DepthFunc=D3D11_COMPARISON_LESS_EQUAL;ComPtr<ID3D11DepthStencilState>ds;if(SUCCEEDED(impl_->device->CreateDepthStencilState(&depth,&ds)))impl_->context->OMSetDepthStencilState(ds.Get(),0);return std::shared_ptr<NativeRenderPass>(new NativeRenderPass(impl_->context.Get(),impl_->context.Get(),impl_->device.Get(),blend,false,v!=nullptr));}
void NativeRenderFrame::commit(){if(impl_->committed)return;impl_->committed=true;if(impl_->swapChain)impl_->swapChain->Present(1,0);}

NativeGameEvent::NativeGameEvent(int32_t k,int32_t key,int32_t mb,double x,double y,double dx,double dy,double pdx,double pdy,double sx,double sy,int32_t pw,int32_t ph,double mag,int32_t slot,const std::string& name):kindCode_(k),keyCode_(key),mouseButtonCode_(mb),controllerSlotCode_(slot),controllerName_(name),x_(x),y_(y),deltaX_(dx),deltaY_(dy),panDeltaX_(pdx),panDeltaY_(pdy),scrollDeltaX_(sx),scrollDeltaY_(sy),pixelWidth_(pw),pixelHeight_(ph),magnificationDelta_(mag){}
int32_t NativeGameEvent::kindCode()const{return kindCode_;} int32_t NativeGameEvent::keyCode()const{return keyCode_;} int32_t NativeGameEvent::mouseButtonCode()const{return mouseButtonCode_;} int32_t NativeGameEvent::controllerSlotCode()const{return controllerSlotCode_;} std::string NativeGameEvent::controllerName()const{return controllerName_;} double NativeGameEvent::x()const{return x_;} double NativeGameEvent::y()const{return y_;} double NativeGameEvent::deltaX()const{return deltaX_;} double NativeGameEvent::deltaY()const{return deltaY_;} double NativeGameEvent::panDeltaX()const{return panDeltaX_;} double NativeGameEvent::panDeltaY()const{return panDeltaY_;} double NativeGameEvent::scrollDeltaX()const{return scrollDeltaX_;} double NativeGameEvent::scrollDeltaY()const{return scrollDeltaY_;} int32_t NativeGameEvent::pixelWidth()const{return pixelWidth_;} int32_t NativeGameEvent::pixelHeight()const{return pixelHeight_;} double NativeGameEvent::magnificationDelta()const{return magnificationDelta_;}

struct NativeInputState::Impl { std::set<int32_t> keys,buttons; std::array<bool,kControllerSlots> connected{}; std::array<std::string,kControllerSlots> names{}; std::array<std::array<bool,kControllerButtons>,kControllerSlots> controllerButtons{}; std::array<std::array<double,kControllerAxes>,kControllerSlots> axes{}; double x=0,y=0,dx=0,dy=0,pdx=0,pdy=0,sx=0,sy=0,mag=0; };
NativeInputState::NativeInputState():impl_(std::make_shared<Impl>()){} NativeInputState::~NativeInputState()=default;
bool NativeInputState::isKeyDownCode(int32_t k)const{return impl_->keys.count(k)>0;} bool NativeInputState::isMouseButtonDownCode(int32_t b)const{return impl_->buttons.count(b)>0;} bool NativeInputState::isControllerConnectedCode(int32_t s)const{return s>=0&&s<kControllerSlots&&impl_->connected[s];} std::string NativeInputState::controllerNameCode(int32_t s)const{return s>=0&&s<kControllerSlots?impl_->names[s]:"";} bool NativeInputState::isControllerButtonDownCode(int32_t s,int32_t b)const{return s>=0&&s<kControllerSlots&&b>=0&&b<kControllerButtons&&impl_->controllerButtons[s][b];} double NativeInputState::controllerAxisCode(int32_t s,int32_t a)const{return s>=0&&s<kControllerSlots&&a>=0&&a<kControllerAxes?impl_->axes[s][a]:0;}
double NativeInputState::mouseX()const{return impl_->x;} double NativeInputState::mouseY()const{return impl_->y;} double NativeInputState::mouseDeltaX()const{return impl_->dx;} double NativeInputState::mouseDeltaY()const{return impl_->dy;} double NativeInputState::panDeltaX()const{return impl_->pdx;} double NativeInputState::panDeltaY()const{return impl_->pdy;} double NativeInputState::scrollDeltaX()const{return impl_->sx;} double NativeInputState::scrollDeltaY()const{return impl_->sy;} double NativeInputState::magnificationDelta()const{return impl_->mag;}
void NativeInputState::resetFrameDeltas(){impl_->dx=impl_->dy=impl_->pdx=impl_->pdy=impl_->sx=impl_->sy=impl_->mag=0;} void NativeInputState::setKeyDownCode(int32_t k,bool d){if(d)impl_->keys.insert(k);else impl_->keys.erase(k);} void NativeInputState::setMouseButtonDownCode(int32_t b,bool d){if(d)impl_->buttons.insert(b);else impl_->buttons.erase(b);} void NativeInputState::setControllerConnectedCode(int32_t s,const std::string&n,bool c){if(s>=0&&s<kControllerSlots){impl_->connected[s]=c;impl_->names[s]=c?n:"";}} void NativeInputState::setControllerButtonDownCode(int32_t s,int32_t b,bool d){if(s>=0&&s<kControllerSlots&&b>=0&&b<kControllerButtons)impl_->controllerButtons[s][b]=d;} void NativeInputState::setControllerAxisCode(int32_t s,int32_t a,double v){if(s>=0&&s<kControllerSlots&&a>=0&&a<kControllerAxes)impl_->axes[s][a]=v;} void NativeInputState::setMousePosition(double x,double y){impl_->x=x;impl_->y=y;} void NativeInputState::addMouseDelta(double x,double y){impl_->dx+=x;impl_->dy+=y;} void NativeInputState::addPanDelta(double x,double y){impl_->pdx+=x;impl_->pdy+=y;} void NativeInputState::addScrollDelta(double x,double y){impl_->sx+=x;impl_->sy+=y;} void NativeInputState::addMagnificationDelta(double v){impl_->mag+=v;}

struct AppRuntime { HWND window=nullptr; std::shared_ptr<NativeGameSurface> surface; std::shared_ptr<NativeInputState> input; doof::callback<void(std::shared_ptr<NativeGameEvent>,std::shared_ptr<NativeInputState>)> onEvent; doof::callback<void(std::shared_ptr<NativeGameSurface>,std::shared_ptr<NativeInputState>)> onRender; doof::callback<int32_t()> drain; std::atomic<bool> running{false},render{true}; bool continuous=true; std::atomic<double>* fps=nullptr; int frames=0; std::chrono::steady_clock::time_point fpsStart=std::chrono::steady_clock::now(); };
struct WindowContext { std::shared_ptr<AppRuntime> runtime; std::shared_ptr<NativeGameSurface>* surface=nullptr; };

struct NativeGameApp::Impl { std::string title,error; bool windowed; int32_t width,height; HWND window=nullptr; std::shared_ptr<NativeGameSurface> surface; std::shared_ptr<NativeInputState> input=std::make_shared<NativeInputState>(); std::shared_ptr<AppRuntime> runtime=std::make_shared<AppRuntime>(); std::unique_ptr<WindowContext> context; std::atomic<double> fps{0}; Impl(std::string t,bool w,int32_t x,int32_t y):title(std::move(t)),windowed(w),width(std::max(1,x)),height(std::max(1,y)){} };

static LRESULT CALLBACK windowProc(HWND window,UINT message,WPARAM wp,LPARAM lp){auto* context=reinterpret_cast<WindowContext*>(GetWindowLongPtrW(window,GWLP_USERDATA)); if(message==WM_NCCREATE){context=static_cast<WindowContext*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams);SetWindowLongPtrW(window,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(context));} if(!context||!context->runtime)return DefWindowProcW(window,message,wp,lp);auto rt=context->runtime;auto emit=[&](std::shared_ptr<NativeGameEvent>e){if(rt->running.load())rt->onEvent.call(e,rt->input);};switch(message){case WM_CLOSE:emit(std::make_shared<NativeGameEvent>(kKindClose));return 0;case WM_SIZE:if(context->surface&&*context->surface&&wp!=SIZE_MINIMIZED){int w=LOWORD(lp),h=HIWORD(lp);auto* dc=reinterpret_cast<ID3D11DeviceContext*>((*context->surface)->metalCommandQueueHandle());auto* swap=reinterpret_cast<IDXGISwapChain*>((*context->surface)->metalLayerHandle());dc->OMSetRenderTargets(0,nullptr,nullptr);swap->ResizeBuffers(0,w,h,DXGI_FORMAT_UNKNOWN,0);emit(std::make_shared<NativeGameEvent>(kKindResized,0,0,0,0,0,0,0,0,0,0,w,h));rt->render=true;}return 0;case WM_KEYDOWN:case WM_SYSKEYDOWN:{int k=mapKey(wp);if(k){rt->input->setKeyDownCode(k,true);emit(std::make_shared<NativeGameEvent>(kKindKeyDown,k));}return 0;}case WM_KEYUP:case WM_SYSKEYUP:{int k=mapKey(wp);if(k){rt->input->setKeyDownCode(k,false);emit(std::make_shared<NativeGameEvent>(kKindKeyUp,k));}return 0;}case WM_LBUTTONDOWN:case WM_RBUTTONDOWN:case WM_MBUTTONDOWN:case WM_LBUTTONUP:case WM_RBUTTONUP:case WM_MBUTTONUP:{bool down=message==WM_LBUTTONDOWN||message==WM_RBUTTONDOWN||message==WM_MBUTTONDOWN;int b=(message==WM_LBUTTONDOWN||message==WM_LBUTTONUP)?0:(message==WM_RBUTTONDOWN||message==WM_RBUTTONUP)?1:2;double x=GET_X_LPARAM(lp),y=GET_Y_LPARAM(lp);rt->input->setMouseButtonDownCode(b,down);rt->input->setMousePosition(x,y);emit(std::make_shared<NativeGameEvent>(down?kKindMouseDown:kKindMouseUp,0,b,x,y));return 0;}case WM_MOUSEMOVE:{double x=GET_X_LPARAM(lp),y=GET_Y_LPARAM(lp),dx=x-rt->input->mouseX(),dy=y-rt->input->mouseY();rt->input->setMousePosition(x,y);rt->input->addMouseDelta(dx,dy);emit(std::make_shared<NativeGameEvent>(kKindMouseMove,0,0,x,y,dx,dy));return 0;}case WM_MOUSEWHEEL:{double d=GET_WHEEL_DELTA_WPARAM(wp)/double(WHEEL_DELTA);rt->input->addScrollDelta(0,d);emit(std::make_shared<NativeGameEvent>(kKindScroll,0,0,rt->input->mouseX(),rt->input->mouseY(),0,0,0,0,0,d));return 0;}case WM_DESTROY:PostQuitMessage(0);return 0;}return DefWindowProcW(window,message,wp,lp);}

std::shared_ptr<NativeGameApp> NativeGameApp::create(const std::string&t,bool w,int32_t x,int32_t y){return std::shared_ptr<NativeGameApp>(new NativeGameApp(t,w,x,y));}
NativeGameApp::NativeGameApp(const std::string&t,bool w,int32_t x,int32_t y):impl_(std::make_shared<Impl>(t,w,x,y)){static std::once_flag once;static ATOM atom=0;std::call_once(once,[&]{SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);WNDCLASSEXW wc{sizeof(wc)};wc.style=CS_HREDRAW|CS_VREDRAW;wc.lpfnWndProc=windowProc;wc.hInstance=GetModuleHandleW(nullptr);wc.hCursor=LoadCursorW(nullptr,MAKEINTRESOURCEW(32512));wc.lpszClassName=L"DoofGameWindow";atom=RegisterClassExW(&wc);});if(!atom){impl_->error=windowsError("Failed to register game window");return;}impl_->context=std::make_unique<WindowContext>();impl_->context->runtime=impl_->runtime;impl_->context->surface=&impl_->surface;DWORD style=w?WS_OVERLAPPEDWINDOW:WS_POPUP;int windowX=CW_USEDEFAULT,windowY=CW_USEDEFAULT;if(!w){impl_->width=GetSystemMetrics(SM_CXSCREEN);impl_->height=GetSystemMetrics(SM_CYSCREEN);windowX=0;windowY=0;}RECT rect{0,0,impl_->width,impl_->height};AdjustWindowRect(&rect,style,FALSE);impl_->window=CreateWindowExW(0,L"DoofGameWindow",wide(t).c_str(),style,windowX,windowY,rect.right-rect.left,rect.bottom-rect.top,nullptr,nullptr,GetModuleHandleW(nullptr),impl_->context.get());if(!impl_->window){impl_->error=windowsError("Failed to create game window");return;}DXGI_SWAP_CHAIN_DESC sd{};sd.BufferDesc.Format=DXGI_FORMAT_R8G8B8A8_UNORM;sd.SampleDesc.Count=1;sd.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT;sd.BufferCount=2;sd.OutputWindow=impl_->window;sd.Windowed=TRUE;sd.SwapEffect=DXGI_SWAP_EFFECT_DISCARD;ComPtr<ID3D11Device>d;ComPtr<ID3D11DeviceContext>c;ComPtr<IDXGISwapChain>s;D3D_FEATURE_LEVEL level;HRESULT hr=D3D11CreateDeviceAndSwapChain(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,0,nullptr,0,D3D11_SDK_VERSION,&sd,&s,&d,&level,&c);if(FAILED(hr)){impl_->error=windowsError("Failed to initialize D3D11",hr);return;}impl_->surface=std::make_shared<NativeGameSurface>(d.Get(),c.Get(),s.Get());impl_->runtime->window=impl_->window;impl_->runtime->surface=impl_->surface;impl_->runtime->input=impl_->input;impl_->runtime->fps=&impl_->fps;}
NativeGameApp::~NativeGameApp(){if(impl_->window)DestroyWindow(impl_->window);} std::shared_ptr<NativeGameSurface> NativeGameApp::surface()const{return impl_->surface;} std::shared_ptr<NativeInputState> NativeGameApp::input()const{return impl_->input;} double NativeGameApp::fps()const{return impl_->fps.load();}
doof::Result<void,std::string> NativeGameApp::run(bool continuous,doof::callback<void(std::shared_ptr<NativeGameEvent>,std::shared_ptr<NativeInputState>)>event,doof::callback<void(std::shared_ptr<NativeGameSurface>,std::shared_ptr<NativeInputState>)>render,doof::callback<int32_t()>drain){if(!impl_->surface)return doof::Failure<std::string>{impl_->error};auto rt=impl_->runtime;rt->continuous=continuous;rt->onEvent=event;rt->onRender=render;rt->drain=drain;rt->running=true;{std::lock_guard<std::mutex>lock(gAppMutex);gRunningApp=rt;}ShowWindow(impl_->window,SW_SHOW);UpdateWindow(impl_->window);MSG msg{};while(rt->running){while(PeekMessageW(&msg,nullptr,0,0,PM_REMOVE)){if(msg.message==WM_QUIT){rt->running=false;break;}TranslateMessage(&msg);DispatchMessageW(&msg);}if(!rt->running)break;rt->drain.call();if(rt->continuous||rt->render.exchange(false)){rt->onRender.call(rt->surface,rt->input);rt->frames++;auto now=std::chrono::steady_clock::now();std::chrono::duration<double>elapsed=now-rt->fpsStart;if(elapsed.count()>=1){impl_->fps=rt->frames/elapsed.count();rt->frames=0;rt->fpsStart=now;}rt->input->resetFrameDeltas();}else WaitMessage();}return doof::Success<void>{};}
doof::Result<void,std::string> runNativeGameApp(const std::string&t,bool w,int32_t x,int32_t y,bool c,doof::callback<void(std::shared_ptr<NativeGameEvent>,std::shared_ptr<NativeInputState>)>e,doof::callback<void(std::shared_ptr<NativeGameSurface>,std::shared_ptr<NativeInputState>)>r,doof::callback<int32_t()>d){return NativeGameApp::create(t,w,x,y)->run(c,e,r,d);}
static std::shared_ptr<AppRuntime> running(){std::lock_guard<std::mutex>lock(gAppMutex);return gRunningApp.lock();} void requestGameAppWake(){if(auto r=running())PostMessageW(r->window,WM_NULL,0,0);} void requestGameAppRender(){if(auto r=running()){r->render=true;PostMessageW(r->window,WM_NULL,0,0);}} void requestGameAppStop(){if(auto r=running()){r->running=false;PostMessageW(r->window,WM_NULL,0,0);}} void beginGameAppPanGesture(double,double){} void updateGameAppPanGesture(double,double){} void endGameAppPanGesture(){} void cancelGameAppPanGesture(){} void cancelGameAppPanInertia(){}

} // namespace doof_game
