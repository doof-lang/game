#include "native_game.hpp"

#import <AppKit/AppKit.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <dispatch/dispatch.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <sstream>
#include <vector>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <utility>

namespace doof_game {

namespace {

constexpr int32_t kKindCloseRequested = 0;
constexpr int32_t kKindResized = 1;
constexpr int32_t kKindKeyDown = 2;
constexpr int32_t kKindKeyUp = 3;
constexpr int32_t kKindMouseDown = 4;
constexpr int32_t kKindMouseUp = 5;
constexpr int32_t kKindMouseMove = 6;
constexpr int32_t kKindMouseWheel = 7;

constexpr int32_t kKeyUnknown = 0;
constexpr int32_t kKeyA = 1;
constexpr int32_t kKeyB = 2;
constexpr int32_t kKeyC = 3;
constexpr int32_t kKeyD = 4;
constexpr int32_t kKeyE = 5;
constexpr int32_t kKeyF = 6;
constexpr int32_t kKeyG = 7;
constexpr int32_t kKeyH = 8;
constexpr int32_t kKeyI = 9;
constexpr int32_t kKeyJ = 10;
constexpr int32_t kKeyK = 11;
constexpr int32_t kKeyL = 12;
constexpr int32_t kKeyM = 13;
constexpr int32_t kKeyN = 14;
constexpr int32_t kKeyO = 15;
constexpr int32_t kKeyP = 16;
constexpr int32_t kKeyQ = 17;
constexpr int32_t kKeyR = 18;
constexpr int32_t kKeyS = 19;
constexpr int32_t kKeyT = 20;
constexpr int32_t kKeyU = 21;
constexpr int32_t kKeyV = 22;
constexpr int32_t kKeyW = 23;
constexpr int32_t kKeyX = 24;
constexpr int32_t kKeyY = 25;
constexpr int32_t kKeyZ = 26;
constexpr int32_t kKeyDigit0 = 27;
constexpr int32_t kKeyDigit1 = 28;
constexpr int32_t kKeyDigit2 = 29;
constexpr int32_t kKeyDigit3 = 30;
constexpr int32_t kKeyDigit4 = 31;
constexpr int32_t kKeyDigit5 = 32;
constexpr int32_t kKeyDigit6 = 33;
constexpr int32_t kKeyDigit7 = 34;
constexpr int32_t kKeyDigit8 = 35;
constexpr int32_t kKeyDigit9 = 36;
constexpr int32_t kKeyArrowLeft = 37;
constexpr int32_t kKeyArrowRight = 38;
constexpr int32_t kKeyArrowUp = 39;
constexpr int32_t kKeyArrowDown = 40;
constexpr int32_t kKeyEscape = 41;
constexpr int32_t kKeyEnter = 42;
constexpr int32_t kKeySpace = 43;
constexpr int32_t kKeyBackspace = 44;
constexpr int32_t kKeyTab = 45;
constexpr int32_t kKeyShift = 46;
constexpr int32_t kKeyControl = 47;
constexpr int32_t kKeyOption = 48;
constexpr int32_t kKeyCommand = 49;
constexpr int32_t kKeyF1 = 50;
constexpr int32_t kKeyF2 = 51;
constexpr int32_t kKeyF3 = 52;
constexpr int32_t kKeyF4 = 53;
constexpr int32_t kKeyF5 = 54;
constexpr int32_t kKeyF6 = 55;
constexpr int32_t kKeyF7 = 56;
constexpr int32_t kKeyF8 = 57;
constexpr int32_t kKeyF9 = 58;
constexpr int32_t kKeyF10 = 59;
constexpr int32_t kKeyF11 = 60;
constexpr int32_t kKeyF12 = 61;

constexpr int32_t kMouseLeft = 0;
constexpr int32_t kMouseRight = 1;
constexpr int32_t kMouseMiddle = 2;
constexpr int32_t kMouseOther = 3;

constexpr int32_t kClearNone = 0;
constexpr int32_t kClearColor = 1;
constexpr int32_t kClearDepth = 2;
constexpr int32_t kClearColorDepth = 3;

constexpr int32_t kDepthDisabled = 0;
constexpr int32_t kDepthReadOnly = 1;
constexpr int32_t kDepthReadWrite = 2;

constexpr int64_t kAppEventWake = 0;
constexpr int64_t kAppEventDisplayTick = 1;

struct SimpleDrawVertex {
    float x;
    float y;
    float z;
    float w;
    float r;
    float g;
    float b;
    float a;
};

struct TextureDrawVertex {
    float x;
    float y;
    float z;
    float w;
    float u;
    float v;
    float r;
    float g;
    float b;
    float a;
};

struct GameRuntimeState;

GameRuntimeState* gActiveState = nullptr;

int32_t mapKeyCode(unsigned short keyCode) {
    switch (keyCode) {
        case 0: return kKeyA;
        case 1: return kKeyS;
        case 2: return kKeyD;
        case 3: return kKeyF;
        case 4: return kKeyH;
        case 5: return kKeyG;
        case 6: return kKeyZ;
        case 7: return kKeyX;
        case 8: return kKeyC;
        case 9: return kKeyV;
        case 11: return kKeyB;
        case 12: return kKeyQ;
        case 13: return kKeyW;
        case 14: return kKeyE;
        case 15: return kKeyR;
        case 16: return kKeyY;
        case 17: return kKeyT;
        case 18: return kKeyDigit1;
        case 19: return kKeyDigit2;
        case 20: return kKeyDigit3;
        case 21: return kKeyDigit4;
        case 22: return kKeyDigit6;
        case 23: return kKeyDigit5;
        case 25: return kKeyDigit9;
        case 26: return kKeyDigit7;
        case 28: return kKeyDigit8;
        case 29: return kKeyDigit0;
        case 31: return kKeyO;
        case 32: return kKeyU;
        case 34: return kKeyI;
        case 35: return kKeyP;
        case 36: return kKeyEnter;
        case 37: return kKeyL;
        case 38: return kKeyJ;
        case 40: return kKeyK;
        case 45: return kKeyN;
        case 46: return kKeyM;
        case 48: return kKeyTab;
        case 49: return kKeySpace;
        case 51: return kKeyBackspace;
        case 53: return kKeyEscape;
        case 55: return kKeyCommand;
        case 56: return kKeyShift;
        case 58: return kKeyOption;
        case 59: return kKeyControl;
        case 60: return kKeyShift;
        case 61: return kKeyOption;
        case 62: return kKeyControl;
        case 96: return kKeyF5;
        case 97: return kKeyF6;
        case 98: return kKeyF7;
        case 99: return kKeyF3;
        case 100: return kKeyF8;
        case 101: return kKeyF9;
        case 103: return kKeyF11;
        case 109: return kKeyF10;
        case 111: return kKeyF12;
        case 118: return kKeyF4;
        case 120: return kKeyF2;
        case 122: return kKeyF1;
        case 123: return kKeyArrowLeft;
        case 124: return kKeyArrowRight;
        case 125: return kKeyArrowDown;
        case 126: return kKeyArrowUp;
        default: return kKeyUnknown;
    }
}

int32_t mapMouseButton(NSInteger buttonNumber) {
    if (buttonNumber == 0) {
        return kMouseLeft;
    }
    if (buttonNumber == 1) {
        return kMouseRight;
    }
    if (buttonNumber == 2) {
        return kMouseMiddle;
    }
    return kMouseOther;
}

std::string textureCacheKey(int64_t metalDeviceHandle, const std::string& path) {
    std::ostringstream out;
    out << metalDeviceHandle << "|" << path;
    return out.str();
}

std::mutex& textureCacheMutex() {
    static std::mutex mutex;
    return mutex;
}

std::unordered_map<std::string, std::weak_ptr<NativeTexture>>& textureCache() {
    static std::unordered_map<std::string, std::weak_ptr<NativeTexture>> cache;
    return cache;
}

id<MTLRenderPipelineState> simpleDrawPipeline(id<MTLDevice> device, int32_t blendMode, bool hasDepth) {
    if (device == nil) {
        return nil;
    }

    static id<MTLRenderPipelineState> opaqueNoDepth = nil;
    static id<MTLRenderPipelineState> alphaNoDepth = nil;
    static id<MTLRenderPipelineState> opaqueDepth = nil;
    static id<MTLRenderPipelineState> alphaDepth = nil;

    id<MTLRenderPipelineState>* slot = nullptr;
    if (blendMode == 1 && hasDepth) {
        slot = &alphaDepth;
    } else if (blendMode == 1) {
        slot = &alphaNoDepth;
    } else if (hasDepth) {
        slot = &opaqueDepth;
    } else {
        slot = &opaqueNoDepth;
    }

    if (*slot != nil) {
        return *slot;
    }

    NSString* source =
        @"#include <metal_stdlib>\n"
        @"using namespace metal;\n"
        @"struct VertexIn { packed_float4 position; packed_float4 color; };\n"
        @"struct VertexOut { float4 position [[position]]; float4 color; };\n"
        @"vertex VertexOut doof_game_vertex(const device VertexIn* vertices [[buffer(0)]], uint vertexId [[vertex_id]]) {\n"
        @"  VertexOut out;\n"
        @"  out.position = vertices[vertexId].position;\n"
        @"  out.color = vertices[vertexId].color;\n"
        @"  return out;\n"
        @"}\n"
        @"fragment float4 doof_game_fragment(VertexOut in [[stage_in]]) {\n"
        @"  return in.color;\n"
        @"}\n";

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) {
        return nil;
    }

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"doof_game_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"doof_game_fragment"];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    if (hasDepth) {
        descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    }

    if (blendMode == 1) {
        descriptor.colorAttachments[0].blendingEnabled = YES;
        descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    }

    id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    [descriptor.vertexFunction release];
    [descriptor.fragmentFunction release];
    [descriptor release];
    [library release];
    if (pipeline == nil) {
        return nil;
    }

    *slot = pipeline;
    return *slot;
}

id<MTLRenderPipelineState> textureDrawPipeline(id<MTLDevice> device, int32_t blendMode, bool hasDepth) {
    if (device == nil) {
        return nil;
    }

    static id<MTLRenderPipelineState> opaqueNoDepth = nil;
    static id<MTLRenderPipelineState> alphaNoDepth = nil;
    static id<MTLRenderPipelineState> opaqueDepth = nil;
    static id<MTLRenderPipelineState> alphaDepth = nil;

    id<MTLRenderPipelineState>* slot = nullptr;
    if (blendMode == 1 && hasDepth) {
        slot = &alphaDepth;
    } else if (blendMode == 1) {
        slot = &alphaNoDepth;
    } else if (hasDepth) {
        slot = &opaqueDepth;
    } else {
        slot = &opaqueNoDepth;
    }

    if (*slot != nil) {
        return *slot;
    }

    NSString* source =
        @"#include <metal_stdlib>\n"
        @"using namespace metal;\n"
        @"struct VertexIn { packed_float4 position; packed_float2 uv; packed_float4 tint; };\n"
        @"struct VertexOut { float4 position [[position]]; float2 uv; float4 tint; };\n"
        @"vertex VertexOut doof_game_texture_vertex(const device VertexIn* vertices [[buffer(0)]], uint vertexId [[vertex_id]]) {\n"
        @"  VertexOut out;\n"
        @"  out.position = vertices[vertexId].position;\n"
        @"  out.uv = vertices[vertexId].uv;\n"
        @"  out.tint = vertices[vertexId].tint;\n"
        @"  return out;\n"
        @"}\n"
        @"fragment float4 doof_game_texture_fragment(VertexOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler textureSampler [[sampler(0)]]) {\n"
        @"  return tex.sample(textureSampler, in.uv) * in.tint;\n"
        @"}\n";

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (library == nil) {
        return nil;
    }

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"doof_game_texture_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"doof_game_texture_fragment"];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    if (hasDepth) {
        descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    }

    if (blendMode == 1) {
        descriptor.colorAttachments[0].blendingEnabled = YES;
        descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    }

    id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    [descriptor.vertexFunction release];
    [descriptor.fragmentFunction release];
    [descriptor release];
    [library release];
    if (pipeline == nil) {
        return nil;
    }

    *slot = pipeline;
    return *slot;
}

}  // namespace

struct NativeGameSurface::Impl {
    id<MTLDevice> device = nil;
    id<MTLCommandQueue> commandQueue = nil;
    CAMetalLayer* layer = nil;

    Impl(void* rawDevice, void* rawCommandQueue, void* rawLayer)
        : device((__bridge id<MTLDevice>)rawDevice),
          commandQueue((__bridge id<MTLCommandQueue>)rawCommandQueue),
          layer((__bridge CAMetalLayer*)rawLayer) {
        [device retain];
        [commandQueue retain];
        [layer retain];
    }

    ~Impl() {
        [layer release];
        [commandQueue release];
        [device release];
    }
};

struct NativeTexture::Impl {
    id<MTLTexture> texture = nil;
    int32_t pixelWidth = 0;
    int32_t pixelHeight = 0;

    Impl(void* rawTexture, int32_t pixelWidth, int32_t pixelHeight)
        : texture((__bridge id<MTLTexture>)rawTexture),
          pixelWidth(pixelWidth),
          pixelHeight(pixelHeight) {
        [texture retain];
    }

    ~Impl() {
        [texture release];
    }
};

struct NativeRenderPass::Impl {
    id<MTLRenderCommandEncoder> encoder = nil;
    id<MTLCommandBuffer> commandBuffer = nil;
    id<MTLDevice> device = nil;
    int32_t blendMode = 0;
    bool hasDepth = false;
    bool ended = false;

    Impl(void* rawEncoder, void* rawCommandBuffer, void* rawDevice, int32_t blendMode, bool hasDepth)
        : encoder((__bridge id<MTLRenderCommandEncoder>)rawEncoder),
          commandBuffer((__bridge id<MTLCommandBuffer>)rawCommandBuffer),
          device((__bridge id<MTLDevice>)rawDevice),
          blendMode(blendMode),
          hasDepth(hasDepth) {
        [encoder retain];
        [commandBuffer retain];
        [device retain];
    }

    ~Impl() {
        if (!ended && encoder != nil) {
            [encoder endEncoding];
        }
        [encoder release];
        [commandBuffer release];
        [device release];
    }
};

struct NativeRenderFrame::Impl {
    std::shared_ptr<NativeGameSurface> surface;
    id<MTLDevice> device = nil;
    id<MTLCommandQueue> commandQueue = nil;
    CAMetalLayer* layer = nil;
    id<CAMetalDrawable> drawable = nil;
    id<MTLCommandBuffer> commandBuffer = nil;
    id<MTLTexture> depthTexture = nil;
    int32_t depthWidth = 0;
    int32_t depthHeight = 0;
    bool committed = false;
    bool valid = false;

    explicit Impl(std::shared_ptr<NativeGameSurface> surface)
        : surface(std::move(surface)) {
        if (!this->surface) {
            return;
        }

        device = (__bridge id<MTLDevice>)reinterpret_cast<void*>(this->surface->metalDeviceHandle());
        commandQueue = (__bridge id<MTLCommandQueue>)reinterpret_cast<void*>(this->surface->metalCommandQueueHandle());
        layer = (__bridge CAMetalLayer*)reinterpret_cast<void*>(this->surface->metalLayerHandle());
        if (device == nil || commandQueue == nil || layer == nil) {
            return;
        }

        commandBuffer = [commandQueue commandBuffer];
        drawable = [layer nextDrawable];
        if (commandBuffer == nil || drawable == nil) {
            commandBuffer = nil;
            drawable = nil;
            return;
        }

        [commandBuffer retain];
        [drawable retain];
        valid = true;
    }

    ~Impl() {
        if (!committed && commandBuffer != nil) {
            [commandBuffer commit];
            committed = true;
        }
        [depthTexture release];
        [drawable release];
        [commandBuffer release];
    }

    id<MTLTexture> depthTextureForDrawable() {
        if (drawable == nil) {
            return nil;
        }

        const int32_t width = static_cast<int32_t>(drawable.texture.width);
        const int32_t height = static_cast<int32_t>(drawable.texture.height);
        if (depthTexture != nil && depthWidth == width && depthHeight == height) {
            return depthTexture;
        }

        [depthTexture release];
        depthTexture = nil;
        depthWidth = width;
        depthHeight = height;

        MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                              width:static_cast<NSUInteger>(std::max(width, 1))
                                                                                             height:static_cast<NSUInteger>(std::max(height, 1))
                                                                                          mipmapped:NO];
        descriptor.usage = MTLTextureUsageRenderTarget;
        descriptor.storageMode = MTLStorageModePrivate;
        depthTexture = [device newTextureWithDescriptor:descriptor];
        return depthTexture;
    }
};

struct NativeInputState::Impl {
    std::unordered_set<int32_t> keysDown;
    std::unordered_set<int32_t> mouseButtonsDown;
    double mouseX = 0.0;
    double mouseY = 0.0;
    double mouseDeltaX = 0.0;
    double mouseDeltaY = 0.0;
    double wheelDeltaX = 0.0;
    double wheelDeltaY = 0.0;
};

struct NativeGameApp::Impl {
    std::string title;
    std::shared_ptr<NativeInputState> input;
    std::shared_ptr<NativeGameSurface> surface;
    std::string initializationError;
    std::atomic<double> framesPerSecond = 0.0;

    explicit Impl(std::string title)
        : title(std::move(title)),
          input(std::make_shared<NativeInputState>()) {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) {
            initializationError = "Metal device initialization failed";
            surface = std::make_shared<NativeGameSurface>(nullptr, nullptr, nullptr);
            return;
        }

        id<MTLCommandQueue> commandQueue = [device newCommandQueue];
        if (commandQueue == nil) {
            initializationError = "Metal command queue initialization failed";
            surface = std::make_shared<NativeGameSurface>(nullptr, nullptr, nullptr);
            [device release];
            return;
        }

        CAMetalLayer* layer = [[CAMetalLayer alloc] init];
        layer.device = device;
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.framebufferOnly = YES;
        layer.opaque = YES;

        surface = std::make_shared<NativeGameSurface>(
            (__bridge void*)device,
            (__bridge void*)commandQueue,
            (__bridge void*)layer
        );

        [layer release];
        [commandQueue release];
        [device release];
    }
};

namespace {

struct GameRuntimeState {
    std::shared_ptr<NativeInputState> input;
    std::shared_ptr<NativeGameSurface> surface;
    doof::callback<void(std::shared_ptr<NativeGameEvent>, std::shared_ptr<NativeInputState>)> onEvent;
    std::atomic<double>* framesPerSecond = nullptr;
    std::atomic_bool running = true;
    std::atomic_bool renderRequested = true;
    std::atomic_bool displayTickPending = false;
    std::chrono::steady_clock::time_point fpsWindowStart = std::chrono::steady_clock::now();
    int32_t fpsFrameCount = 0;
    bool shiftDown = false;
    bool controlDown = false;
    bool optionDown = false;
    bool commandDown = false;

    void emit(std::shared_ptr<NativeGameEvent> event) {
        onEvent.call(event, input);
    }

    void resetFrameDeltas() {
        input->resetFrameDeltas();
    }

    void requestRender() {
        renderRequested.store(true);
    }

    void recordRenderedFrame() {
        ++fpsFrameCount;
        auto now = std::chrono::steady_clock::now();
        std::chrono::duration<double> elapsed = now - fpsWindowStart;
        if (elapsed.count() < 1.0) {
            return;
        }

        if (framesPerSecond != nullptr) {
            framesPerSecond->store(static_cast<double>(fpsFrameCount) / elapsed.count());
        }
        fpsFrameCount = 0;
        fpsWindowStart = now;
    }

    void setKey(int32_t key, bool isDown) {
        if (key == kKeyUnknown) {
            return;
        }
        input->setKeyDownCode(key, isDown);
        emit(std::make_shared<NativeGameEvent>(isDown ? kKindKeyDown : kKindKeyUp, key));
    }

    void updateModifier(int32_t key, bool& previous, bool current) {
        if (previous == current) {
            return;
        }
        previous = current;
        setKey(key, current);
    }
};

void updateLayerDrawableSize(NSView* view, const std::shared_ptr<NativeGameSurface>& surface) {
    if (!view || !surface) {
        return;
    }

    CAMetalLayer* layer = (__bridge CAMetalLayer*)reinterpret_cast<void*>(surface->metalLayerHandle());
    NSSize pointSize = [view bounds].size;
    NSSize pixelSize = [view convertSizeToBacking:pointSize];
    layer.contentsScale = [view window] ? [[view window] backingScaleFactor] : [NSScreen mainScreen].backingScaleFactor;
    layer.drawableSize = CGSizeMake(std::max(pixelSize.width, 1.0), std::max(pixelSize.height, 1.0));
}

std::shared_ptr<NativeGameEvent> makeResizeEvent(const std::shared_ptr<NativeGameSurface>& surface) {
    return std::make_shared<NativeGameEvent>(
        kKindResized,
        kKeyUnknown,
        kMouseOther,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        surface->pixelWidth(),
        surface->pixelHeight()
    );
}

void postApplicationDefinedEvent(int64_t kind = 0) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (NSApp != nil) {
            NSEvent* event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                                location:NSZeroPoint
                                           modifierFlags:0
                                               timestamp:0
                                            windowNumber:0
                                                   context:nil
                                                 subtype:0
                                                  data1:kind
                                                  data2:0];
            [NSApp postEvent:event atStart:NO];
        }
    });
}

CVReturn displayLinkCallback(
    CVDisplayLinkRef displayLink,
    const CVTimeStamp* now,
    const CVTimeStamp* outputTime,
    CVOptionFlags flagsIn,
    CVOptionFlags* flagsOut,
    void* displayLinkContext
) {
    (void)displayLink;
    (void)now;
    (void)outputTime;
    (void)flagsIn;
    (void)flagsOut;

    auto* state = static_cast<GameRuntimeState*>(displayLinkContext);
    if (state == nullptr || !state->running.load()) {
        return kCVReturnSuccess;
    }

    if (!state->displayTickPending.exchange(true)) {
        postApplicationDefinedEvent(kAppEventDisplayTick);
    }

    return kCVReturnSuccess;
}

}  // namespace

}  // namespace doof_game

@interface DoofGameWindow : NSWindow
@end

@implementation DoofGameWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

@end

@interface DoofGameView : NSView {
@public
    doof_game::GameRuntimeState* state_;
}
- (instancetype)initWithState:(doof_game::GameRuntimeState*)state;
@end

@implementation DoofGameView

- (instancetype)initWithState:(doof_game::GameRuntimeState*)state {
    self = [super initWithFrame:[[NSScreen mainScreen] frame]];
    if (self) {
        state_ = state;
        [self setWantsLayer:YES];
        [self setLayer:(__bridge CAMetalLayer*)reinterpret_cast<void*>(state->surface->metalLayerHandle())];
        [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [self setAcceptsTouchEvents:NO];
        [self.window makeFirstResponder:self];
    }
    return self;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)canBecomeKeyView {
    return YES;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    doof_game::updateLayerDrawableSize(self, state_->surface);
    state_->emit(doof_game::makeResizeEvent(state_->surface));
    state_->requestRender();
}

- (NSPoint)gamePointForEvent:(NSEvent*)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSRect bounds = [self bounds];
    return NSMakePoint(point.x, bounds.size.height - point.y);
}

- (void)mouseDown:(NSEvent*)event {
    NSInteger button = [event buttonNumber];
    int32_t mapped = doof_game::mapMouseButton(button);
    state_->input->setMouseButtonDownCode(mapped, true);
    NSPoint point = [self gamePointForEvent:event];
    state_->input->setMousePosition(point.x, point.y);
    state_->emit(std::make_shared<doof_game::NativeGameEvent>(doof_game::kKindMouseDown, doof_game::kKeyUnknown, mapped, point.x, point.y));
}

- (void)rightMouseDown:(NSEvent*)event {
    [self mouseDown:event];
}

- (void)otherMouseDown:(NSEvent*)event {
    [self mouseDown:event];
}

- (void)mouseUp:(NSEvent*)event {
    NSInteger button = [event buttonNumber];
    int32_t mapped = doof_game::mapMouseButton(button);
    state_->input->setMouseButtonDownCode(mapped, false);
    NSPoint point = [self gamePointForEvent:event];
    state_->input->setMousePosition(point.x, point.y);
    state_->emit(std::make_shared<doof_game::NativeGameEvent>(doof_game::kKindMouseUp, doof_game::kKeyUnknown, mapped, point.x, point.y));
}

- (void)rightMouseUp:(NSEvent*)event {
    [self mouseUp:event];
}

- (void)otherMouseUp:(NSEvent*)event {
    [self mouseUp:event];
}

- (void)mouseMoved:(NSEvent*)event {
    NSPoint point = [self gamePointForEvent:event];
    double dx = [event deltaX];
    double dy = [event deltaY];
    state_->input->setMousePosition(point.x, point.y);
    state_->input->addMouseDelta(dx, dy);
    state_->emit(std::make_shared<doof_game::NativeGameEvent>(
        doof_game::kKindMouseMove,
        doof_game::kKeyUnknown,
        doof_game::kMouseOther,
        point.x,
        point.y,
        dx,
        dy
    ));
}

- (void)mouseDragged:(NSEvent*)event {
    [self mouseMoved:event];
}

- (void)rightMouseDragged:(NSEvent*)event {
    [self mouseMoved:event];
}

- (void)otherMouseDragged:(NSEvent*)event {
    [self mouseMoved:event];
}

- (void)scrollWheel:(NSEvent*)event {
    double dx = [event scrollingDeltaX];
    double dy = [event scrollingDeltaY];
    state_->input->addWheelDelta(dx, dy);
    NSPoint point = [self gamePointForEvent:event];
    state_->emit(std::make_shared<doof_game::NativeGameEvent>(
        doof_game::kKindMouseWheel,
        doof_game::kKeyUnknown,
        doof_game::kMouseOther,
        point.x,
        point.y,
        0.0,
        0.0,
        dx,
        dy
    ));
}

- (void)keyDown:(NSEvent*)event {
    if ([event isARepeat]) {
        return;
    }
    state_->setKey(doof_game::mapKeyCode([event keyCode]), true);
}

- (void)cancelOperation:(id)sender {
    (void)sender;
    state_->setKey(doof_game::kKeyEscape, true);
    state_->setKey(doof_game::kKeyEscape, false);
}

- (void)keyUp:(NSEvent*)event {
    state_->setKey(doof_game::mapKeyCode([event keyCode]), false);
}

- (void)flagsChanged:(NSEvent*)event {
    NSEventModifierFlags flags = [event modifierFlags];
    state_->updateModifier(doof_game::kKeyShift, state_->shiftDown, (flags & NSEventModifierFlagShift) != 0);
    state_->updateModifier(doof_game::kKeyControl, state_->controlDown, (flags & NSEventModifierFlagControl) != 0);
    state_->updateModifier(doof_game::kKeyOption, state_->optionDown, (flags & NSEventModifierFlagOption) != 0);
    state_->updateModifier(doof_game::kKeyCommand, state_->commandDown, (flags & NSEventModifierFlagCommand) != 0);
}

@end

@interface DoofGameWindowDelegate : NSObject <NSWindowDelegate> {
@public
    doof_game::GameRuntimeState* state_;
}
- (instancetype)initWithState:(doof_game::GameRuntimeState*)state;
@end

@implementation DoofGameWindowDelegate

- (instancetype)initWithState:(doof_game::GameRuntimeState*)state {
    self = [super init];
    if (self) {
        state_ = state;
    }
    return self;
}

- (BOOL)windowShouldClose:(id)sender {
    (void)sender;
    state_->emit(std::make_shared<doof_game::NativeGameEvent>(doof_game::kKindCloseRequested));
    state_->running.store(false);
    return YES;
}

@end

namespace doof_game {

NativeGameSurface::NativeGameSurface(void* device, void* commandQueue, void* layer)
    : impl_(std::make_shared<Impl>(device, commandQueue, layer)) {}

NativeGameSurface::~NativeGameSurface() = default;

int32_t NativeGameSurface::pixelWidth() const {
    CGSize size = impl_->layer.drawableSize;
    return static_cast<int32_t>(size.width);
}

int32_t NativeGameSurface::pixelHeight() const {
    CGSize size = impl_->layer.drawableSize;
    return static_cast<int32_t>(size.height);
}

double NativeGameSurface::scale() const {
    return static_cast<double>(impl_->layer.contentsScale);
}

int64_t NativeGameSurface::metalDeviceHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->device);
}

int64_t NativeGameSurface::metalCommandQueueHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->commandQueue);
}

int64_t NativeGameSurface::metalLayerHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->layer);
}

doof::Result<std::shared_ptr<NativeTexture>, std::string> NativeTexture::load(
    const std::string& path,
    int64_t metalDeviceHandle
) {
    id<MTLDevice> device = (__bridge id<MTLDevice>)reinterpret_cast<void*>(metalDeviceHandle);
    if (device == nil) {
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("Metal device handle is invalid");
    }

    const std::string cacheKey = textureCacheKey(metalDeviceHandle, path);
    {
        std::lock_guard<std::mutex> lock(textureCacheMutex());
        auto found = textureCache().find(cacheKey);
        if (found != textureCache().end()) {
            if (auto cached = found->second.lock()) {
                return doof::Result<std::shared_ptr<NativeTexture>, std::string>::success(cached);
            }
            textureCache().erase(found);
        }
    }

    NSString* nsPath = [NSString stringWithUTF8String:path.c_str()];
    NSImage* image = [[NSImage alloc] initWithContentsOfFile:nsPath];
    if (image == nil) {
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("Failed to load image: " + path);
    }

    CGImageRef cgImage = [image CGImageForProposedRect:nullptr context:nil hints:nil];
    if (cgImage == nullptr) {
        [image release];
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("Failed to decode image: " + path);
    }

    const size_t width = CGImageGetWidth(cgImage);
    const size_t height = CGImageGetHeight(cgImage);
    if (width == 0 || height == 0) {
        [image release];
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("Image is empty: " + path);
    }

    std::vector<uint8_t> pixels(width * height * 4u);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        pixels.data(),
        width,
        height,
        8,
        width * 4u,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(colorSpace);
    if (context == nullptr) {
        [image release];
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("Failed to create image decode context: " + path);
    }

    CGContextClearRect(context, CGRectMake(0, 0, static_cast<CGFloat>(width), static_cast<CGFloat>(height)));
    CGContextDrawImage(context, CGRectMake(0, 0, static_cast<CGFloat>(width), static_cast<CGFloat>(height)), cgImage);
    CGContextRelease(context);
    [image release];

    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    if (texture == nil) {
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("Failed to create texture: " + path);
    }

    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0
                 withBytes:pixels.data()
               bytesPerRow:width * 4u];

    auto native = std::make_shared<NativeTexture>(
        (__bridge void*)texture,
        static_cast<int32_t>(width),
        static_cast<int32_t>(height)
    );
    [texture release];
    {
        std::lock_guard<std::mutex> lock(textureCacheMutex());
        textureCache()[cacheKey] = native;
    }
    return doof::Result<std::shared_ptr<NativeTexture>, std::string>::success(native);
}

NativeTexture::NativeTexture(void* texture, int32_t pixelWidth, int32_t pixelHeight)
    : impl_(std::make_shared<Impl>(texture, pixelWidth, pixelHeight)) {}

NativeTexture::~NativeTexture() = default;

int32_t NativeTexture::pixelWidth() const {
    return impl_->pixelWidth;
}

int32_t NativeTexture::pixelHeight() const {
    return impl_->pixelHeight;
}

int64_t NativeTexture::metalTextureHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->texture);
}

NativeRenderPass::NativeRenderPass(void* encoder, void* commandBuffer, void* device, int32_t blendMode, bool hasDepth)
    : impl_(std::make_shared<Impl>(encoder, commandBuffer, device, blendMode, hasDepth)) {}

NativeRenderPass::~NativeRenderPass() = default;

void NativeRenderPass::end() {
    if (impl_->ended) {
        return;
    }
    impl_->ended = true;
    if (impl_->encoder != nil) {
        [impl_->encoder endEncoding];
    }
}

void NativeRenderPass::drawTriangle(
    double ax,
    double ay,
    double az,
    double aw,
    double bx,
    double by,
    double bz,
    double bw,
    double cx,
    double cy,
    double cz,
    double cw,
    double red,
    double green,
    double blue,
    double alpha
) {
    if (impl_->ended || impl_->encoder == nil || impl_->device == nil) {
        return;
    }

    id<MTLRenderPipelineState> pipeline = simpleDrawPipeline(impl_->device, impl_->blendMode, impl_->hasDepth);
    if (pipeline == nil) {
        return;
    }

    SimpleDrawVertex vertices[3] = {
        { static_cast<float>(ax), static_cast<float>(ay), static_cast<float>(az), static_cast<float>(aw), static_cast<float>(red), static_cast<float>(green), static_cast<float>(blue), static_cast<float>(alpha) },
        { static_cast<float>(bx), static_cast<float>(by), static_cast<float>(bz), static_cast<float>(bw), static_cast<float>(red), static_cast<float>(green), static_cast<float>(blue), static_cast<float>(alpha) },
        { static_cast<float>(cx), static_cast<float>(cy), static_cast<float>(cz), static_cast<float>(cw), static_cast<float>(red), static_cast<float>(green), static_cast<float>(blue), static_cast<float>(alpha) },
    };

    [impl_->encoder setRenderPipelineState:pipeline];
    [impl_->encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
    [impl_->encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
}

void NativeRenderPass::drawTextureQuad(
    std::shared_ptr<NativeTexture> texture,
    double ax,
    double ay,
    double az,
    double aw,
    double bx,
    double by,
    double bz,
    double bw,
    double cx,
    double cy,
    double cz,
    double cw,
    double dx,
    double dy,
    double dz,
    double dw,
    double sourceX,
    double sourceY,
    double sourceWidth,
    double sourceHeight,
    double red,
    double green,
    double blue,
    double alpha
) {
    if (
        impl_->ended ||
        impl_->encoder == nil ||
        impl_->device == nil ||
        !texture ||
        texture->pixelWidth() <= 0 ||
        texture->pixelHeight() <= 0
    ) {
        return;
    }

    id<MTLRenderPipelineState> pipeline = textureDrawPipeline(impl_->device, impl_->blendMode, impl_->hasDepth);
    if (pipeline == nil) {
        return;
    }

    id<MTLTexture> metalTexture = (__bridge id<MTLTexture>)reinterpret_cast<void*>(texture->metalTextureHandle());
    if (metalTexture == nil) {
        return;
    }

    static id<MTLSamplerState> sampler = nil;
    if (sampler == nil) {
        MTLSamplerDescriptor* descriptor = [[MTLSamplerDescriptor alloc] init];
        descriptor.minFilter = MTLSamplerMinMagFilterLinear;
        descriptor.magFilter = MTLSamplerMinMagFilterLinear;
        descriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
        descriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
        sampler = [impl_->device newSamplerStateWithDescriptor:descriptor];
        [descriptor release];
        if (sampler == nil) {
            return;
        }
    }

    const double textureWidth = static_cast<double>(texture->pixelWidth());
    const double textureHeight = static_cast<double>(texture->pixelHeight());
    const float u0 = static_cast<float>(sourceX / textureWidth);
    const float v0 = static_cast<float>(sourceY / textureHeight);
    const float u1 = static_cast<float>((sourceX + sourceWidth) / textureWidth);
    const float v1 = static_cast<float>((sourceY + sourceHeight) / textureHeight);

    const float r = static_cast<float>(red);
    const float g = static_cast<float>(green);
    const float b = static_cast<float>(blue);
    const float a = static_cast<float>(alpha);

    TextureDrawVertex vertices[6] = {
        { static_cast<float>(ax), static_cast<float>(ay), static_cast<float>(az), static_cast<float>(aw), u0, v0, r, g, b, a },
        { static_cast<float>(bx), static_cast<float>(by), static_cast<float>(bz), static_cast<float>(bw), u1, v0, r, g, b, a },
        { static_cast<float>(cx), static_cast<float>(cy), static_cast<float>(cz), static_cast<float>(cw), u0, v1, r, g, b, a },
        { static_cast<float>(bx), static_cast<float>(by), static_cast<float>(bz), static_cast<float>(bw), u1, v0, r, g, b, a },
        { static_cast<float>(dx), static_cast<float>(dy), static_cast<float>(dz), static_cast<float>(dw), u1, v1, r, g, b, a },
        { static_cast<float>(cx), static_cast<float>(cy), static_cast<float>(cz), static_cast<float>(cw), u0, v1, r, g, b, a },
    };

    [impl_->encoder setRenderPipelineState:pipeline];
    [impl_->encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
    [impl_->encoder setFragmentTexture:metalTexture atIndex:0];
    [impl_->encoder setFragmentSamplerState:sampler atIndex:0];
    [impl_->encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
}

int64_t NativeRenderPass::metalRenderCommandEncoderHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->encoder);
}

int64_t NativeRenderPass::metalCommandBufferHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->commandBuffer);
}

std::shared_ptr<NativeRenderFrame> NativeRenderFrame::create(std::shared_ptr<NativeGameSurface> surface) {
    return std::shared_ptr<NativeRenderFrame>(new NativeRenderFrame(std::move(surface)));
}

NativeRenderFrame::NativeRenderFrame(std::shared_ptr<NativeGameSurface> surface)
    : impl_(std::make_shared<Impl>(std::move(surface))) {}

NativeRenderFrame::~NativeRenderFrame() = default;

std::shared_ptr<NativeRenderPass> NativeRenderFrame::beginPass(
    int32_t clearKind,
    double clearRed,
    double clearGreen,
    double clearBlue,
    double clearAlpha,
    double clearDepth,
    int32_t depthMode,
    int32_t blendMode
) {
    if (!impl_->valid || impl_->commandBuffer == nil || impl_->drawable == nil) {
        return std::shared_ptr<NativeRenderPass>(new NativeRenderPass(nullptr, nullptr, nullptr, blendMode, false));
    }

    MTLRenderPassDescriptor* descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    descriptor.colorAttachments[0].texture = impl_->drawable.texture;
    descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    descriptor.colorAttachments[0].clearColor = MTLClearColorMake(clearRed, clearGreen, clearBlue, clearAlpha);
    descriptor.colorAttachments[0].loadAction =
        (clearKind == kClearColor || clearKind == kClearColorDepth) ? MTLLoadActionClear : MTLLoadActionLoad;

    const bool needsDepthAttachment =
        depthMode != kDepthDisabled || clearKind == kClearDepth || clearKind == kClearColorDepth;
    if (needsDepthAttachment) {
        descriptor.depthAttachment.texture = impl_->depthTextureForDrawable();
        descriptor.depthAttachment.storeAction = MTLStoreActionStore;
        descriptor.depthAttachment.clearDepth = clearDepth;
        descriptor.depthAttachment.loadAction =
            (clearKind == kClearDepth || clearKind == kClearColorDepth) ? MTLLoadActionClear : MTLLoadActionLoad;
    }

    id<MTLRenderCommandEncoder> encoder = [impl_->commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    if (encoder == nil) {
        return std::shared_ptr<NativeRenderPass>(new NativeRenderPass(nullptr, impl_->commandBuffer, impl_->device, blendMode, needsDepthAttachment));
    }

    if (needsDepthAttachment) {
        MTLDepthStencilDescriptor* depthDescriptor = [[MTLDepthStencilDescriptor alloc] init];
        depthDescriptor.depthCompareFunction = depthMode == kDepthDisabled ? MTLCompareFunctionAlways : MTLCompareFunctionLessEqual;
        depthDescriptor.depthWriteEnabled = depthMode == kDepthReadWrite;
        id<MTLDepthStencilState> depthState = [impl_->device newDepthStencilStateWithDescriptor:depthDescriptor];
        [depthDescriptor release];
        if (depthState != nil) {
            [encoder setDepthStencilState:depthState];
            [depthState release];
        }
    }

    return std::shared_ptr<NativeRenderPass>(new NativeRenderPass(
        (__bridge void*)encoder,
        (__bridge void*)impl_->commandBuffer,
        (__bridge void*)impl_->device,
        blendMode,
        needsDepthAttachment
    ));
}

void NativeRenderFrame::commit() {
    if (impl_->committed) {
        return;
    }
    impl_->committed = true;
    if (impl_->commandBuffer == nil) {
        return;
    }
    if (impl_->drawable != nil) {
        [impl_->commandBuffer presentDrawable:impl_->drawable];
    }
    [impl_->commandBuffer commit];
}

NativeGameEvent::NativeGameEvent(
    int32_t kindCode,
    int32_t keyCode,
    int32_t mouseButtonCode,
    double x,
    double y,
    double deltaX,
    double deltaY,
    double wheelDeltaX,
    double wheelDeltaY,
    int32_t pixelWidth,
    int32_t pixelHeight
) : kindCode_(kindCode),
    keyCode_(keyCode),
    mouseButtonCode_(mouseButtonCode),
    x_(x),
    y_(y),
    deltaX_(deltaX),
    deltaY_(deltaY),
    wheelDeltaX_(wheelDeltaX),
    wheelDeltaY_(wheelDeltaY),
    pixelWidth_(pixelWidth),
    pixelHeight_(pixelHeight) {}

int32_t NativeGameEvent::kindCode() const { return kindCode_; }
int32_t NativeGameEvent::keyCode() const { return keyCode_; }
int32_t NativeGameEvent::mouseButtonCode() const { return mouseButtonCode_; }
double NativeGameEvent::x() const { return x_; }
double NativeGameEvent::y() const { return y_; }
double NativeGameEvent::deltaX() const { return deltaX_; }
double NativeGameEvent::deltaY() const { return deltaY_; }
double NativeGameEvent::wheelDeltaX() const { return wheelDeltaX_; }
double NativeGameEvent::wheelDeltaY() const { return wheelDeltaY_; }
int32_t NativeGameEvent::pixelWidth() const { return pixelWidth_; }
int32_t NativeGameEvent::pixelHeight() const { return pixelHeight_; }

NativeInputState::NativeInputState() : impl_(std::make_shared<Impl>()) {}
NativeInputState::~NativeInputState() = default;

bool NativeInputState::isKeyDownCode(int32_t key) const {
    return impl_->keysDown.count(key) > 0;
}

bool NativeInputState::isMouseButtonDownCode(int32_t button) const {
    return impl_->mouseButtonsDown.count(button) > 0;
}

double NativeInputState::mouseX() const { return impl_->mouseX; }
double NativeInputState::mouseY() const { return impl_->mouseY; }
double NativeInputState::mouseDeltaX() const { return impl_->mouseDeltaX; }
double NativeInputState::mouseDeltaY() const { return impl_->mouseDeltaY; }
double NativeInputState::wheelDeltaX() const { return impl_->wheelDeltaX; }
double NativeInputState::wheelDeltaY() const { return impl_->wheelDeltaY; }

void NativeInputState::resetFrameDeltas() {
    impl_->mouseDeltaX = 0.0;
    impl_->mouseDeltaY = 0.0;
    impl_->wheelDeltaX = 0.0;
    impl_->wheelDeltaY = 0.0;
}

void NativeInputState::setKeyDownCode(int32_t key, bool isDown) {
    if (isDown) {
        impl_->keysDown.insert(key);
    } else {
        impl_->keysDown.erase(key);
    }
}

void NativeInputState::setMouseButtonDownCode(int32_t button, bool isDown) {
    if (isDown) {
        impl_->mouseButtonsDown.insert(button);
    } else {
        impl_->mouseButtonsDown.erase(button);
    }
}

void NativeInputState::setMousePosition(double x, double y) {
    impl_->mouseX = x;
    impl_->mouseY = y;
}

void NativeInputState::addMouseDelta(double x, double y) {
    impl_->mouseDeltaX += x;
    impl_->mouseDeltaY += y;
}

void NativeInputState::addWheelDelta(double x, double y) {
    impl_->wheelDeltaX += x;
    impl_->wheelDeltaY += y;
}

std::shared_ptr<NativeGameApp> NativeGameApp::create(const std::string& title) {
    return std::shared_ptr<NativeGameApp>(new NativeGameApp(title));
}

NativeGameApp::NativeGameApp(const std::string& title)
    : impl_(std::make_shared<Impl>(title)) {}

NativeGameApp::~NativeGameApp() = default;

std::shared_ptr<NativeGameSurface> NativeGameApp::surface() const {
    return impl_->surface;
}

std::shared_ptr<NativeInputState> NativeGameApp::input() const {
    return impl_->input;
}

double NativeGameApp::fps() const {
    return impl_->framesPerSecond.load();
}

void requestGameAppWake() {
    postApplicationDefinedEvent(kAppEventWake);
}

void requestGameAppRender() {
    if (gActiveState != nullptr) {
        gActiveState->requestRender();
    }
}

void requestGameAppStop() {
    if (gActiveState != nullptr) {
        gActiveState->running.store(false);
    }
    requestGameAppWake();
}

doof::Result<void, std::string> NativeGameApp::run(
    doof::callback<void(std::shared_ptr<NativeGameEvent>, std::shared_ptr<NativeInputState>)> onEvent,
    doof::callback<void(std::shared_ptr<NativeGameSurface>, std::shared_ptr<NativeInputState>)> onRender,
    doof::callback<int32_t()> drainEvents
) {
    @autoreleasepool {
        if (!impl_->initializationError.empty()) {
            return doof::Result<void, std::string>::failure(impl_->initializationError);
        }

        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        auto input = impl_->input;
        auto surface = impl_->surface;

        GameRuntimeState state;
        state.input = input;
        state.surface = surface;
        state.onEvent = onEvent;
        state.framesPerSecond = &impl_->framesPerSecond;
        impl_->framesPerSecond.store(0.0);
        gActiveState = &state;
        CVDisplayLinkRef displayLink = nullptr;

        NSScreen* screen = [NSScreen mainScreen];
        NSRect frame = [screen frame];
        DoofGameWindow* window = [[DoofGameWindow alloc] initWithContentRect:frame
                                                                   styleMask:NSWindowStyleMaskBorderless
                                                                     backing:NSBackingStoreBuffered
                                                                       defer:NO
                                                                      screen:screen];
        [window setTitle:[NSString stringWithUTF8String:impl_->title.c_str()]];
        [window setLevel:NSMainMenuWindowLevel + 1];
        [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
        [window setReleasedWhenClosed:NO];

        DoofGameView* view = [[DoofGameView alloc] initWithState:&state];
        [window setContentView:view];
        [window makeFirstResponder:view];

        DoofGameWindowDelegate* delegate = [[DoofGameWindowDelegate alloc] initWithState:&state];
        [window setDelegate:delegate];

        updateLayerDrawableSize(view, surface);
        [window makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];

        CVReturn displayLinkResult = CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);
        if (displayLinkResult != kCVReturnSuccess || displayLink == nullptr) {
            [window orderOut:nil];
            [window setDelegate:nil];
            [delegate release];
            [view release];
            [window close];
            [window release];
            gActiveState = nullptr;
            return doof::Result<void, std::string>::failure("Display link initialization failed");
        }
        CVDisplayLinkSetOutputCallback(displayLink, displayLinkCallback, &state);
        CVDisplayLinkStart(displayLink);

        drainEvents.call();

        while (state.running.load()) {
            @autoreleasepool {
                bool sawDisplayTick = false;

                NSEvent* event = [app nextEventMatchingMask:NSEventMaskAny
                                                  untilDate:[NSDate distantFuture]
                                                     inMode:NSDefaultRunLoopMode
                                                    dequeue:YES];
                if (event != nil) {
                    if ([event type] == NSEventTypeApplicationDefined) {
                        if ([event data1] == kAppEventDisplayTick) {
                            sawDisplayTick = true;
                            state.displayTickPending.store(false);
                        }
                        drainEvents.call();
                    } else {
                        [app sendEvent:event];
                    }
                }

                do {
                    event = [app nextEventMatchingMask:NSEventMaskAny
                                             untilDate:[NSDate distantPast]
                                                inMode:NSDefaultRunLoopMode
                                               dequeue:YES];
                    if (event == nil) {
                        break;
                    }

                    if ([event type] == NSEventTypeApplicationDefined) {
                        if ([event data1] == kAppEventDisplayTick) {
                            sawDisplayTick = true;
                            state.displayTickPending.store(false);
                        }
                        drainEvents.call();
                    } else {
                        [app sendEvent:event];
                    }
                } while (state.running.load());

                drainEvents.call();

                if (sawDisplayTick && state.renderRequested.exchange(false)) {
                    onRender.call(surface, input);
                    state.recordRenderedFrame();
                    state.resetFrameDeltas();
                }
            }
        }

        CVDisplayLinkStop(displayLink);
        CVDisplayLinkRelease(displayLink);

        drainEvents.call();

        [window orderOut:nil];
        [window setDelegate:nil];
        [delegate release];
        [view release];
        [window close];
        [window release];
        gActiveState = nullptr;

        return doof::Result<void, std::string>::success();
    }
}

doof::Result<void, std::string> runNativeGameApp(
    const std::string& title,
    doof::callback<void(std::shared_ptr<NativeGameEvent>, std::shared_ptr<NativeInputState>)> onEvent,
    doof::callback<void(std::shared_ptr<NativeGameSurface>, std::shared_ptr<NativeInputState>)> onRender,
    doof::callback<int32_t()> drainEvents
) {
    return NativeGameApp::create(title)->run(std::move(onEvent), std::move(onRender), std::move(drainEvents));
}

}  // namespace doof_game
