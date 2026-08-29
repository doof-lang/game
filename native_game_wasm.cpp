#include "native_game.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <memory>
#include <set>
#include <string>

// Wasm implementation of the existing std/game native app and surface boundary.
// Browser objects stay in doof-game.js and cross this boundary as opaque integer
// handles, just as the native backends expose opaque platform handles to Doof.
#if defined(__EMSCRIPTEN__)
extern "C" {
__attribute__((import_module("doof_game"), import_name("window_create")))
int32_t doof_game_window_create(const char* title, int32_t width, int32_t height, int32_t windowed);
__attribute__((import_module("doof_game"), import_name("window_width")))
int32_t doof_game_window_width(int32_t window);
__attribute__((import_module("doof_game"), import_name("window_height")))
int32_t doof_game_window_height(int32_t window);
__attribute__((import_module("doof_game"), import_name("window_scale")))
double doof_game_window_scale(int32_t window);
__attribute__((import_module("doof_game"), import_name("window_start")))
void doof_game_window_start(int32_t window, int32_t frame_dispatcher, int32_t event_dispatcher);
__attribute__((import_module("doof_game"), import_name("window_stop")))
void doof_game_window_stop(int32_t window);
__attribute__((import_module("doof_game"), import_name("begin_pass")))
void doof_game_begin_pass(int32_t window, int32_t clear_kind, double red, double green, double blue,
    double alpha, double depth, int32_t depth_mode, int32_t blend_mode, int32_t winding, int32_t cull);
__attribute__((import_module("doof_game"), import_name("frame_commit")))
void doof_game_frame_commit(int32_t window);
__attribute__((import_module("doof_game"), import_name("texture_rgba")))
int32_t doof_game_texture_rgba(int32_t window, const uint8_t* data, int32_t count, int32_t width, int32_t height);
__attribute__((import_module("doof_game"), import_name("texture_load")))
int32_t doof_game_texture_load(int32_t window, const char* path);
__attribute__((import_module("doof_game"), import_name("texture_width")))
int32_t doof_game_texture_width(int32_t texture);
__attribute__((import_module("doof_game"), import_name("texture_height")))
int32_t doof_game_texture_height(int32_t texture);
__attribute__((import_module("doof_game"), import_name("texture_delete")))
void doof_game_texture_delete(int32_t window, int32_t texture);
}
#endif

namespace doof_game {
namespace {

constexpr int32_t kControllerSlots = 4;
constexpr int32_t kControllerButtons = 16;
constexpr int32_t kControllerAxes = 6;

struct Runtime {
    std::shared_ptr<NativeGameSurface> surface;
    std::shared_ptr<NativeInputState> input;
    doof::callback<void(std::shared_ptr<NativeGameEvent>, std::shared_ptr<NativeInputState>)> onEvent;
    doof::callback<void(std::shared_ptr<NativeGameSurface>, std::shared_ptr<NativeInputState>)> onRender;
    doof::callback<int32_t()> drain;
    bool running = false;
    bool continuous = true;
    bool renderRequested = true;
    double fps = 0.0;
    double lastFrame = 0.0;
};

std::shared_ptr<Runtime> gRuntime;

extern "C" void doofGameFrameDispatcher(double timestamp) {
    auto runtime = gRuntime;
    if (!runtime || !runtime->running) return;
    auto& domain = doof::detail::ApplicationDomain::shared();
    doof::detail::ActiveActorScope scope(&domain);
    runtime->drain.call();
    if (runtime->continuous || runtime->renderRequested) {
        runtime->renderRequested = false;
        runtime->onRender.call(runtime->surface, runtime->input);
        if (runtime->lastFrame > 0.0 && timestamp > runtime->lastFrame) {
            runtime->fps = 1000.0 / (timestamp - runtime->lastFrame);
        }
        runtime->lastFrame = timestamp;
        runtime->input->resetFrameDeltas();
    }
}

extern "C" void doofGameEventDispatcher(
    int32_t kind, int32_t key, int32_t button,
    double x, double y, double deltaX, double deltaY,
    double scrollX, double scrollY, int32_t pixelWidth, int32_t pixelHeight
) {
    auto runtime = gRuntime;
    if (!runtime || !runtime->running) return;
    auto& domain = doof::detail::ApplicationDomain::shared();
    doof::detail::ActiveActorScope scope(&domain);
    if (kind == 2) runtime->input->setKeyDownCode(key, true);
    if (kind == 3) runtime->input->setKeyDownCode(key, false);
    if (kind == 4) runtime->input->setMouseButtonDownCode(button, true);
    if (kind == 5) runtime->input->setMouseButtonDownCode(button, false);
    if (kind >= 4 && kind <= 6) {
        runtime->input->setMousePosition(x, y);
        if (kind == 6) runtime->input->addMouseDelta(deltaX, deltaY);
    }
    if (kind == 7) runtime->input->addScrollDelta(scrollX, scrollY);
    runtime->onEvent.call(std::make_shared<NativeGameEvent>(
        kind, key, button, x, y, deltaX, deltaY, 0.0, 0.0,
        scrollX, scrollY, pixelWidth, pixelHeight), runtime->input);
    runtime->renderRequested = true;
}

int32_t functionPointer(void (*function)()) {
    return static_cast<int32_t>(reinterpret_cast<std::uintptr_t>(function));
}

}  // namespace

struct NativeGameSurface::Impl { int32_t window = 0; explicit Impl(int32_t value) : window(value) {} };
NativeGameSurface::NativeGameSurface(void* device, void*, void*) : impl_(std::make_shared<Impl>(static_cast<int32_t>(reinterpret_cast<std::uintptr_t>(device)))) {}
NativeGameSurface::~NativeGameSurface() = default;
int32_t NativeGameSurface::pixelWidth() const { return doof_game_window_width(impl_->window); }
int32_t NativeGameSurface::pixelHeight() const { return doof_game_window_height(impl_->window); }
double NativeGameSurface::scale() const { return doof_game_window_scale(impl_->window); }
int64_t NativeGameSurface::metalDeviceHandle() const { return impl_->window; }
int64_t NativeGameSurface::metalCommandQueueHandle() const { return impl_->window; }
int64_t NativeGameSurface::metalLayerHandle() const { return impl_->window; }

struct NativeTexture::Impl { int32_t window=0,texture=0,width=0,height=0; Impl(int32_t w,int32_t t,int32_t x,int32_t y):window(w),texture(t),width(x),height(y){} };
NativeTexture::NativeTexture(void* texture,int32_t width,int32_t height):impl_(std::make_shared<Impl>(gRuntime?static_cast<int32_t>(gRuntime->surface->metalDeviceHandle()):0,static_cast<int32_t>(reinterpret_cast<std::uintptr_t>(texture)),width,height)){}
NativeTexture::~NativeTexture(){if(impl_.use_count()==1&&impl_->texture)doof_game_texture_delete(impl_->window,impl_->texture);}int32_t NativeTexture::pixelWidth()const{return impl_->width;}int32_t NativeTexture::pixelHeight()const{return impl_->height;}int64_t NativeTexture::metalTextureHandle()const{return impl_->texture;}
doof::Result<std::shared_ptr<NativeTexture>,std::string> NativeTexture::load(const std::string& path,int64_t window){int32_t texture=doof_game_texture_load(window,path.c_str());if(!texture)return doof::Failure<std::string>{"Texture was not preloaded by the Wasm host: "+path};return doof::Success<std::shared_ptr<NativeTexture>>{std::make_shared<NativeTexture>(reinterpret_cast<void*>(static_cast<std::uintptr_t>(texture)),doof_game_texture_width(texture),doof_game_texture_height(texture))};}
doof::Result<std::shared_ptr<NativeTexture>,std::string> NativeTexture::createRgba(const std::shared_ptr<std::vector<uint8_t>>& data,int32_t width,int32_t height,int32_t,int64_t window){if(!data||data->size()!=static_cast<std::size_t>(width)*height*4u)return doof::Failure<std::string>{"RGBA texture buffer size does not match its dimensions"};int32_t texture=doof_game_texture_rgba(window,data->data(),data->size(),width,height);if(!texture)return doof::Failure<std::string>{"Failed to create WebGL 2 texture"};return doof::Success<std::shared_ptr<NativeTexture>>{std::make_shared<NativeTexture>(reinterpret_cast<void*>(static_cast<std::uintptr_t>(texture)),width,height)};}
doof::Result<std::shared_ptr<NativeTexture>,std::string> NativeTexture::createAlpha4(const std::shared_ptr<std::vector<uint8_t>>& data,int32_t width,int32_t height,int64_t window){std::size_t count=width>0&&height>0?static_cast<std::size_t>(width)*height:0;if(!data||!count||data->size()!=(count+1)/2)return doof::Failure<std::string>{"Alpha4 texture buffer size does not match its dimensions"};std::vector<uint8_t> rgba(count*4,255);for(std::size_t i=0;i<count;++i)rgba[i*4+3]=static_cast<uint8_t>(((i&1)?((*data)[i/2]&15):((*data)[i/2]>>4))*17);auto shared=std::make_shared<std::vector<uint8_t>>(std::move(rgba));return createRgba(shared,width,height,1,window);}

struct NativeDepthTexture::Impl{int32_t width=0,height=0;};doof::Result<std::shared_ptr<NativeDepthTexture>,std::string> NativeDepthTexture::create(int32_t,int32_t,int64_t){return doof::Failure<std::string>{"Depth textures are not implemented by the Wasm backend"};}NativeDepthTexture::NativeDepthTexture(void*,int32_t width,int32_t height):impl_(std::make_shared<Impl>()){impl_->width=width;impl_->height=height;}NativeDepthTexture::~NativeDepthTexture()=default;int32_t NativeDepthTexture::pixelWidth()const{return impl_->width;}int32_t NativeDepthTexture::pixelHeight()const{return impl_->height;}int64_t NativeDepthTexture::metalTextureHandle()const{return 0;}

struct NativeRenderPass::Impl{int32_t window=0,blend=0;bool color=true,depth=false;Impl(int32_t w,int32_t b,bool c,bool d):window(w),blend(b),color(c),depth(d){}};NativeRenderPass::NativeRenderPass(void* encoder,void*,void*,int32_t blend,bool color,bool depth):impl_(std::make_shared<Impl>(static_cast<int32_t>(reinterpret_cast<std::uintptr_t>(encoder)),blend,color,depth)){}NativeRenderPass::~NativeRenderPass()=default;void NativeRenderPass::end(){}int64_t NativeRenderPass::metalRenderCommandEncoderHandle()const{return impl_->window;}int64_t NativeRenderPass::metalCommandBufferHandle()const{return impl_->window;}int64_t NativeRenderPass::metalDeviceHandle()const{return impl_->window;}bool NativeRenderPass::hasColorAttachment()const{return impl_->color;}bool NativeRenderPass::hasDepthAttachment()const{return impl_->depth;}
struct NativeRenderFrame::Impl{std::shared_ptr<NativeGameSurface> surface;explicit Impl(std::shared_ptr<NativeGameSurface> value):surface(std::move(value)){}};std::shared_ptr<NativeRenderFrame> NativeRenderFrame::create(std::shared_ptr<NativeGameSurface> surface){return std::shared_ptr<NativeRenderFrame>(new NativeRenderFrame(std::move(surface)));}NativeRenderFrame::NativeRenderFrame(std::shared_ptr<NativeGameSurface> surface):impl_(std::make_shared<Impl>(std::move(surface))){}NativeRenderFrame::~NativeRenderFrame()=default;
std::shared_ptr<NativeRenderPass> NativeRenderFrame::beginPass(int32_t clearKind,double red,double green,double blue,double alpha,double clearDepth,int32_t depthMode,int32_t blendMode,int32_t winding,int32_t cull){int32_t window=impl_->surface->metalDeviceHandle();doof_game_begin_pass(window,clearKind,red,green,blue,alpha,clearDepth,depthMode,blendMode,winding,cull);return std::shared_ptr<NativeRenderPass>(new NativeRenderPass(reinterpret_cast<void*>(static_cast<std::uintptr_t>(window)),nullptr,nullptr,blendMode,true,depthMode!=0));}
std::shared_ptr<NativeRenderPass> NativeRenderFrame::beginDepthPass(std::shared_ptr<NativeDepthTexture>,double clearDepth,int32_t depthMode,int32_t blendMode,int32_t winding,int32_t cull){return beginPass(2,0,0,0,0,clearDepth,depthMode,blendMode,winding,cull);}void NativeRenderFrame::commit(){doof_game_frame_commit(impl_->surface->metalDeviceHandle());}

NativeGameEvent::NativeGameEvent(int32_t kind,int32_t key,int32_t button,double x,double y,double dx,double dy,double pdx,double pdy,double sx,double sy,int32_t width,int32_t height,double magnification,int32_t slot,const std::string& name):kindCode_(kind),keyCode_(key),mouseButtonCode_(button),controllerSlotCode_(slot),controllerName_(name),x_(x),y_(y),deltaX_(dx),deltaY_(dy),panDeltaX_(pdx),panDeltaY_(pdy),scrollDeltaX_(sx),scrollDeltaY_(sy),pixelWidth_(width),pixelHeight_(height),magnificationDelta_(magnification){}
int32_t NativeGameEvent::kindCode()const{return kindCode_;}int32_t NativeGameEvent::keyCode()const{return keyCode_;}int32_t NativeGameEvent::mouseButtonCode()const{return mouseButtonCode_;}int32_t NativeGameEvent::controllerSlotCode()const{return controllerSlotCode_;}std::string NativeGameEvent::controllerName()const{return controllerName_;}double NativeGameEvent::x()const{return x_;}double NativeGameEvent::y()const{return y_;}double NativeGameEvent::deltaX()const{return deltaX_;}double NativeGameEvent::deltaY()const{return deltaY_;}double NativeGameEvent::panDeltaX()const{return panDeltaX_;}double NativeGameEvent::panDeltaY()const{return panDeltaY_;}double NativeGameEvent::scrollDeltaX()const{return scrollDeltaX_;}double NativeGameEvent::scrollDeltaY()const{return scrollDeltaY_;}int32_t NativeGameEvent::pixelWidth()const{return pixelWidth_;}int32_t NativeGameEvent::pixelHeight()const{return pixelHeight_;}double NativeGameEvent::magnificationDelta()const{return magnificationDelta_;}

struct NativeInputState::Impl{std::set<int32_t> keys,buttons;std::array<bool,kControllerSlots> connected{};std::array<std::string,kControllerSlots> names{};std::array<std::array<bool,kControllerButtons>,kControllerSlots> controllerButtons{};std::array<std::array<double,kControllerAxes>,kControllerSlots> axes{};double x=0,y=0,dx=0,dy=0,pdx=0,pdy=0,sx=0,sy=0,mag=0;};NativeInputState::NativeInputState():impl_(std::make_shared<Impl>()){}NativeInputState::~NativeInputState()=default;
bool NativeInputState::isKeyDownCode(int32_t key)const{return impl_->keys.count(key)!=0;}bool NativeInputState::isMouseButtonDownCode(int32_t button)const{return impl_->buttons.count(button)!=0;}bool NativeInputState::isControllerConnectedCode(int32_t slot)const{return slot>=0&&slot<kControllerSlots&&impl_->connected[slot];}std::string NativeInputState::controllerNameCode(int32_t slot)const{return slot>=0&&slot<kControllerSlots?impl_->names[slot]:"";}bool NativeInputState::isControllerButtonDownCode(int32_t slot,int32_t button)const{return slot>=0&&slot<kControllerSlots&&button>=0&&button<kControllerButtons&&impl_->controllerButtons[slot][button];}double NativeInputState::controllerAxisCode(int32_t slot,int32_t axis)const{return slot>=0&&slot<kControllerSlots&&axis>=0&&axis<kControllerAxes?impl_->axes[slot][axis]:0;}
double NativeInputState::mouseX()const{return impl_->x;}double NativeInputState::mouseY()const{return impl_->y;}double NativeInputState::mouseDeltaX()const{return impl_->dx;}double NativeInputState::mouseDeltaY()const{return impl_->dy;}double NativeInputState::panDeltaX()const{return impl_->pdx;}double NativeInputState::panDeltaY()const{return impl_->pdy;}double NativeInputState::scrollDeltaX()const{return impl_->sx;}double NativeInputState::scrollDeltaY()const{return impl_->sy;}double NativeInputState::magnificationDelta()const{return impl_->mag;}void NativeInputState::resetFrameDeltas(){impl_->dx=impl_->dy=impl_->pdx=impl_->pdy=impl_->sx=impl_->sy=impl_->mag=0;}void NativeInputState::setKeyDownCode(int32_t key,bool down){if(down)impl_->keys.insert(key);else impl_->keys.erase(key);}void NativeInputState::setMouseButtonDownCode(int32_t button,bool down){if(down)impl_->buttons.insert(button);else impl_->buttons.erase(button);}void NativeInputState::setControllerConnectedCode(int32_t slot,const std::string& name,bool connected){if(slot>=0&&slot<kControllerSlots){impl_->connected[slot]=connected;impl_->names[slot]=connected?name:"";}}void NativeInputState::setControllerButtonDownCode(int32_t slot,int32_t button,bool down){if(slot>=0&&slot<kControllerSlots&&button>=0&&button<kControllerButtons)impl_->controllerButtons[slot][button]=down;}void NativeInputState::setControllerAxisCode(int32_t slot,int32_t axis,double value){if(slot>=0&&slot<kControllerSlots&&axis>=0&&axis<kControllerAxes)impl_->axes[slot][axis]=value;}void NativeInputState::setMousePosition(double x,double y){impl_->x=x;impl_->y=y;}void NativeInputState::addMouseDelta(double x,double y){impl_->dx+=x;impl_->dy+=y;}void NativeInputState::addPanDelta(double x,double y){impl_->pdx+=x;impl_->pdy+=y;}void NativeInputState::addScrollDelta(double x,double y){impl_->sx+=x;impl_->sy+=y;}void NativeInputState::addMagnificationDelta(double value){impl_->mag+=value;}

struct NativeGameApp::Impl{std::string error;std::shared_ptr<NativeGameSurface> surface;std::shared_ptr<NativeInputState> input=std::make_shared<NativeInputState>();std::shared_ptr<Runtime> runtime=std::make_shared<Runtime>();};std::shared_ptr<NativeGameApp> NativeGameApp::create(const std::string& title,bool windowed,int32_t width,int32_t height){return std::shared_ptr<NativeGameApp>(new NativeGameApp(title,windowed,width,height));}NativeGameApp::NativeGameApp(const std::string& title,bool windowed,int32_t width,int32_t height):impl_(std::make_shared<Impl>()){int32_t window=doof_game_window_create(title.c_str(),std::max(1,width),std::max(1,height),windowed?1:0);if(!window){impl_->error="The browser or GPU does not support WebGL 2";return;}impl_->surface=std::make_shared<NativeGameSurface>(reinterpret_cast<void*>(static_cast<std::uintptr_t>(window)),nullptr,nullptr);impl_->runtime->surface=impl_->surface;impl_->runtime->input=impl_->input;gRuntime=impl_->runtime;}NativeGameApp::~NativeGameApp()=default;std::shared_ptr<NativeGameSurface> NativeGameApp::surface()const{return impl_->surface;}std::shared_ptr<NativeInputState> NativeGameApp::input()const{return impl_->input;}double NativeGameApp::fps()const{return impl_->runtime->fps;}
doof::Result<void,std::string> NativeGameApp::run(bool continuous,doof::callback<void(std::shared_ptr<NativeGameEvent>,std::shared_ptr<NativeInputState>)> onEvent,doof::callback<void(std::shared_ptr<NativeGameSurface>,std::shared_ptr<NativeInputState>)> onRender,doof::callback<int32_t()> drain){if(!impl_->surface)return doof::Failure<std::string>{impl_->error};auto runtime=impl_->runtime;runtime->continuous=continuous;runtime->onEvent=std::move(onEvent);runtime->onRender=std::move(onRender);runtime->drain=std::move(drain);runtime->running=true;runtime->renderRequested=true;gRuntime=runtime;auto frame=reinterpret_cast<void(*)()>(&doofGameFrameDispatcher);auto event=reinterpret_cast<void(*)()>(&doofGameEventDispatcher);doof_game_window_start(runtime->surface->metalDeviceHandle(),functionPointer(frame),functionPointer(event));return doof::Success<void>{};}
doof::Result<void,std::string> runNativeGameApp(const std::string& title,bool windowed,int32_t width,int32_t height,bool continuous,doof::callback<void(std::shared_ptr<NativeGameEvent>,std::shared_ptr<NativeInputState>)> onEvent,doof::callback<void(std::shared_ptr<NativeGameSurface>,std::shared_ptr<NativeInputState>)> onRender,doof::callback<int32_t()> drain){return NativeGameApp::create(title,windowed,width,height)->run(continuous,std::move(onEvent),std::move(onRender),std::move(drain));}
void requestGameAppWake(){}void requestGameAppRender(){if(gRuntime)gRuntime->renderRequested=true;}void requestGameAppStop(){if(gRuntime){gRuntime->running=false;doof_game_window_stop(gRuntime->surface->metalDeviceHandle());}}void beginGameAppPanGesture(double x,double y){if(gRuntime)gRuntime->input->setMousePosition(x,y);}void updateGameAppPanGesture(double x,double y){if(gRuntime){double dx=x-gRuntime->input->mouseX(),dy=y-gRuntime->input->mouseY();gRuntime->input->setMousePosition(x,y);gRuntime->input->addPanDelta(dx,dy);}}void endGameAppPanGesture(){}void cancelGameAppPanGesture(){}void cancelGameAppPanInertia(){}

}  // namespace doof_game
