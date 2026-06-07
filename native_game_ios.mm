#include "native_game.hpp"

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <Metal/Metal.h>
#import <QuartzCore/CADisplayLink.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cctype>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

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
constexpr int32_t kMouseLeft = 0;
constexpr int32_t kMouseOther = 3;

constexpr int32_t kClearColor = 1;
constexpr int32_t kClearDepth = 2;
constexpr int32_t kClearColorDepth = 3;

constexpr int32_t kDepthDisabled = 0;
constexpr int32_t kDepthReadWrite = 2;

constexpr int32_t kWindingClockwise = 0;
constexpr int32_t kWindingCounterClockwise = 1;

constexpr int32_t kCullNone = 0;
constexpr int32_t kCullFront = 1;
constexpr int32_t kCullBack = 2;

struct DepthTextureCacheEntry {
    id<MTLTexture> texture = nil;
    int32_t width = 0;
    int32_t height = 0;
};

struct GameRuntimeState;

GameRuntimeState* gActiveState = nullptr;
std::mutex gDepthTextureCacheMutex;
std::unordered_map<void*, DepthTextureCacheEntry> gDepthTextureCache;

std::string resolveReadableAssetPath(const std::string& path);

id<MTLTexture> cachedDepthTextureForLayer(CAMetalLayer* layer, id<MTLDevice> device, id<CAMetalDrawable> drawable) {
    if (layer == nil || device == nil || drawable == nil) {
        return nil;
    }

    const int32_t width = static_cast<int32_t>(drawable.texture.width);
    const int32_t height = static_cast<int32_t>(drawable.texture.height);
    void* key = (__bridge void*)layer;

    std::lock_guard<std::mutex> lock(gDepthTextureCacheMutex);
    DepthTextureCacheEntry& entry = gDepthTextureCache[key];
    if (entry.texture != nil && entry.width == width && entry.height == height) {
        return entry.texture;
    }

    [entry.texture release];
    entry.texture = nil;
    entry.width = width;
    entry.height = height;

    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                          width:static_cast<NSUInteger>(std::max(width, 1))
                                                                                         height:static_cast<NSUInteger>(std::max(height, 1))
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget;
    descriptor.storageMode = MTLStorageModePrivate;
    entry.texture = [device newTextureWithDescriptor:descriptor];
    return entry.texture;
}

void releaseCachedDepthTextureForLayer(CAMetalLayer* layer) {
    if (layer == nil) {
        return;
    }

    void* key = (__bridge void*)layer;
    std::lock_guard<std::mutex> lock(gDepthTextureCacheMutex);
    auto it = gDepthTextureCache.find(key);
    if (it == gDepthTextureCache.end()) {
        return;
    }
    [it->second.texture release];
    gDepthTextureCache.erase(it);
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

bool pathHasHdrExtension(const std::string& path) {
    if (path.size() < 4) {
        return false;
    }

    std::string ext = path.substr(path.size() - 4);
    std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return ext == ".hdr";
}

bool readHdrLine(const std::vector<uint8_t>& bytes, size_t& offset, std::string& line) {
    if (offset >= bytes.size()) {
        return false;
    }

    line.clear();
    while (offset < bytes.size()) {
        char ch = static_cast<char>(bytes[offset++]);
        if (ch == '\n') {
            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }
            return true;
        }
        line.push_back(ch);
    }
    return true;
}

bool parseHdrResolution(const std::string& line, int32_t& width, int32_t& height) {
    char ySign = 0;
    char yAxis = 0;
    char xSign = 0;
    char xAxis = 0;
    int parsedHeight = 0;
    int parsedWidth = 0;
    if (std::sscanf(line.c_str(), " %c%c %d %c%c %d", &ySign, &yAxis, &parsedHeight, &xSign, &xAxis, &parsedWidth) != 6) {
        return false;
    }
    if ((yAxis != 'Y' && yAxis != 'y') || (xAxis != 'X' && xAxis != 'x') || parsedWidth <= 0 || parsedHeight <= 0) {
        return false;
    }
    width = static_cast<int32_t>(parsedWidth);
    height = static_cast<int32_t>(parsedHeight);
    return true;
}

float rgbeToFloat(uint8_t value, uint8_t exponent) {
    if (exponent == 0) {
        return 0.0f;
    }
    return static_cast<float>((static_cast<double>(value) + 0.5) * std::ldexp(1.0, static_cast<int>(exponent) - 136));
}

doof::Result<std::shared_ptr<NativeTexture>, std::string> loadRadianceHdrTexture(
    const std::string& path,
    id<MTLDevice> device
) {
    const std::string resolvedPath = resolveReadableAssetPath(path);
    std::ifstream file(resolvedPath, std::ios::binary);
    if (!file) {
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("Failed to load HDR image: " + path);
    }

    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    size_t offset = 0;
    std::string line;
    int32_t width = 0;
    int32_t height = 0;
    while (readHdrLine(bytes, offset, line)) {
        if (parseHdrResolution(line, width, height)) {
            break;
        }
    }

    if (width <= 0 || height <= 0) {
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("Failed to parse HDR image resolution: " + path);
    }

    const size_t pixelCount = static_cast<size_t>(width) * static_cast<size_t>(height);
    std::vector<uint8_t> rgbe(pixelCount * 4u);

    for (int32_t y = 0; y < height; ++y) {
        if (offset + 4u > bytes.size()) {
            return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("HDR image ended early: " + path);
        }

        uint8_t b0 = bytes[offset];
        uint8_t b1 = bytes[offset + 1u];
        uint8_t b2 = bytes[offset + 2u];
        uint8_t b3 = bytes[offset + 3u];
        if (b0 == 2 && b1 == 2 && (b2 & 0x80u) == 0u) {
            int32_t scanlineWidth = (static_cast<int32_t>(b2) << 8) | static_cast<int32_t>(b3);
            offset += 4u;
            if (scanlineWidth != width) {
                return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("HDR scanline width mismatch: " + path);
            }

            std::vector<uint8_t> channels(static_cast<size_t>(width) * 4u);
            for (int32_t channel = 0; channel < 4; ++channel) {
                int32_t x = 0;
                while (x < width) {
                    if (offset >= bytes.size()) {
                        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("HDR RLE data ended early: " + path);
                    }
                    uint8_t count = bytes[offset++];
                    if (count > 128) {
                        int32_t run = static_cast<int32_t>(count) - 128;
                        if (run <= 0 || x + run > width || offset >= bytes.size()) {
                            return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("HDR RLE run is invalid: " + path);
                        }
                        uint8_t value = bytes[offset++];
                        for (int32_t i = 0; i < run; ++i) {
                            channels[static_cast<size_t>(channel) * static_cast<size_t>(width) + static_cast<size_t>(x++)] = value;
                        }
                    } else {
                        int32_t run = static_cast<int32_t>(count);
                        if (run <= 0 || x + run > width || offset + static_cast<size_t>(run) > bytes.size()) {
                            return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("HDR RLE literal is invalid: " + path);
                        }
                        for (int32_t i = 0; i < run; ++i) {
                            channels[static_cast<size_t>(channel) * static_cast<size_t>(width) + static_cast<size_t>(x++)] = bytes[offset++];
                        }
                    }
                }
            }

            for (int32_t x = 0; x < width; ++x) {
                size_t out = (static_cast<size_t>(y) * static_cast<size_t>(width) + static_cast<size_t>(x)) * 4u;
                rgbe[out] = channels[static_cast<size_t>(x)];
                rgbe[out + 1u] = channels[static_cast<size_t>(width) + static_cast<size_t>(x)];
                rgbe[out + 2u] = channels[static_cast<size_t>(width) * 2u + static_cast<size_t>(x)];
                rgbe[out + 3u] = channels[static_cast<size_t>(width) * 3u + static_cast<size_t>(x)];
            }
        } else {
            size_t rowBytes = static_cast<size_t>(width) * 4u;
            if (offset + rowBytes > bytes.size()) {
                return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("HDR image ended early: " + path);
            }
            std::copy(bytes.begin() + static_cast<std::ptrdiff_t>(offset),
                      bytes.begin() + static_cast<std::ptrdiff_t>(offset + rowBytes),
                      rgbe.begin() + static_cast<std::ptrdiff_t>(static_cast<size_t>(y) * rowBytes));
            offset += rowBytes;
        }
    }

    std::vector<float> pixels(pixelCount * 4u);
    for (size_t i = 0; i < pixelCount; ++i) {
        uint8_t exponent = rgbe[i * 4u + 3u];
        pixels[i * 4u] = rgbeToFloat(rgbe[i * 4u], exponent);
        pixels[i * 4u + 1u] = rgbeToFloat(rgbe[i * 4u + 1u], exponent);
        pixels[i * 4u + 2u] = rgbeToFloat(rgbe[i * 4u + 2u], exponent);
        pixels[i * 4u + 3u] = 1.0f;
    }

    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                                                                          width:static_cast<NSUInteger>(width)
                                                                                         height:static_cast<NSUInteger>(height)
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    if (texture == nil) {
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("Failed to create HDR texture: " + path);
    }

    [texture replaceRegion:MTLRegionMake2D(0, 0, static_cast<NSUInteger>(width), static_cast<NSUInteger>(height))
               mipmapLevel:0
                 withBytes:pixels.data()
               bytesPerRow:static_cast<NSUInteger>(width) * 4u * sizeof(float)];

    auto native = std::make_shared<NativeTexture>((__bridge void*)texture, width, height);
    [texture release];
    return doof::Result<std::shared_ptr<NativeTexture>, std::string>::success(native);
}

MTLWinding metalWindingForMode(int32_t windingMode) {
    switch (windingMode) {
        case kWindingClockwise:
            return MTLWindingClockwise;
        case kWindingCounterClockwise:
        default:
            return MTLWindingCounterClockwise;
    }
}

MTLCullMode metalCullModeForMode(int32_t cullMode) {
    switch (cullMode) {
        case kCullFront:
            return MTLCullModeFront;
        case kCullBack:
            return MTLCullModeBack;
        case kCullNone:
        default:
            return MTLCullModeNone;
    }
}

NSString* nsString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

bool fileExists(const std::string& path) {
    return [[NSFileManager defaultManager] fileExistsAtPath:nsString(path)];
}

std::string bundleResourcePathForRelativePath(const std::string& path) {
    if (path.empty() || path[0] == '/') {
        return path;
    }

    NSBundle* bundle = [NSBundle mainBundle];
    NSString* resourcePath = [bundle resourcePath];
    if (resourcePath == nil) {
        return path;
    }

    NSString* resolved = [resourcePath stringByAppendingPathComponent:nsString(path)];
    return std::string([resolved fileSystemRepresentation]);
}

std::string resolveReadableAssetPath(const std::string& path) {
    if (fileExists(path)) {
        return path;
    }

    std::string bundled = bundleResourcePathForRelativePath(path);
    return fileExists(bundled) ? bundled : path;
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
        releaseCachedDepthTextureForLayer(layer);
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
        [drawable release];
        [commandBuffer release];
    }

    id<MTLTexture> depthTextureForDrawable() {
        return cachedDepthTextureForLayer(layer, device, drawable);
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
        __block id<MTLDevice> device = nil;
        __block id<MTLCommandQueue> commandQueue = nil;
        __block CAMetalLayer* layer = nil;

        dispatch_sync(dispatch_get_main_queue(), ^{
            device = MTLCreateSystemDefaultDevice();
            if (device == nil) {
                return;
            }
            commandQueue = [device newCommandQueue];
            if (commandQueue == nil) {
                return;
            }
            layer = [[CAMetalLayer alloc] init];
            layer.device = device;
            layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
            layer.framebufferOnly = YES;
            layer.opaque = YES;
            layer.maximumDrawableCount = 3;
            UIScreen* screen = UIScreen.mainScreen;
            CGFloat scale = screen != nil ? screen.scale : 1.0;
            CGSize size = screen != nil ? screen.bounds.size : CGSizeMake(1.0, 1.0);
            layer.contentsScale = scale;
            layer.drawableSize = CGSizeMake(
                std::max(size.width * scale, 1.0),
                std::max(size.height * scale, 1.0)
            );
        });

        if (device == nil) {
            initializationError = "Metal device initialization failed";
            surface = std::make_shared<NativeGameSurface>(nullptr, nullptr, nullptr);
            return;
        }
        if (commandQueue == nil) {
            initializationError = "Metal command queue initialization failed";
            surface = std::make_shared<NativeGameSurface>(nullptr, nullptr, nullptr);
            [device release];
            return;
        }
        if (layer == nil) {
            initializationError = "Metal layer initialization failed";
            surface = std::make_shared<NativeGameSurface>(nullptr, nullptr, nullptr);
            [commandQueue release];
            [device release];
            return;
        }

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

}  // namespace doof_game

@interface DoofGameDisplayLinkTarget : NSObject {
@public
    doof_game::GameRuntimeState* state_;
}
- (instancetype)initWithState:(doof_game::GameRuntimeState*)state;
- (void)tick:(CADisplayLink*)displayLink;
@end

@interface DoofGameIOSView : UIView {
@public
    doof_game::GameRuntimeState* state_;
    UITouch* primaryTouch_;
    UITouch* secondaryTouch_;
    double lastPinchDistance_;
    double lastPinchMidpointX_;
    double lastPinchMidpointY_;
    BOOL mouseDownEmitted_;
    BOOL pinching_;
}
- (instancetype)initWithState:(doof_game::GameRuntimeState*)state frame:(CGRect)frame;
@end

namespace doof_game {
namespace {

UIWindow* fallbackApplicationWindow() {
    NSSet<UIScene*>* scenes = UIApplication.sharedApplication.connectedScenes;
    for (UIScene* scene in scenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene* windowScene = (UIWindowScene*)scene;
        if (windowScene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }

        for (UIWindow* window in windowScene.windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }

        UIWindow* firstWindow = windowScene.windows.firstObject;
        if (firstWindow != nil) {
            return firstWindow;
        }
    }

    return nil;
}

void updateLayerDrawableSize(UIView* view, const std::shared_ptr<NativeGameSurface>& surface) {
    if (view == nil || !surface) {
        return;
    }

    CAMetalLayer* layer = (__bridge CAMetalLayer*)reinterpret_cast<void*>(surface->metalLayerHandle());
    if (layer == nil) {
        return;
    }

    UIScreen* screen = view.window != nil ? view.window.screen : UIScreen.mainScreen;
    CGFloat scale = screen != nil ? screen.scale : 1.0;
    CGSize pointSize = view.bounds.size;
    layer.contentsScale = scale;
    layer.frame = view.bounds;
    layer.drawableSize = CGSizeMake(
        std::max(pointSize.width * scale, 1.0),
        std::max(pointSize.height * scale, 1.0)
    );
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

CGPoint gamePointForTouch(UIView* view, UITouch* touch) {
    if (view == nil || touch == nil) {
        return CGPointZero;
    }

    CGPoint point = [touch locationInView:view];
    UIScreen* screen = view.window != nil ? view.window.screen : UIScreen.mainScreen;
    CGFloat scale = screen != nil ? screen.scale : 1.0;
    return CGPointMake(point.x * scale, point.y * scale);
}

struct GameRuntimeState : std::enable_shared_from_this<GameRuntimeState> {
    std::shared_ptr<NativeInputState> input;
    std::shared_ptr<NativeGameSurface> surface;
    doof::callback<void(std::shared_ptr<NativeGameEvent>, std::shared_ptr<NativeInputState>)> onEvent;
    doof::callback<void(std::shared_ptr<NativeGameSurface>, std::shared_ptr<NativeInputState>)> onRender;
    doof::callback<int32_t()> drainEvents;
    std::atomic<double>* framesPerSecond = nullptr;
    CADisplayLink* displayLink = nil;
    DoofGameDisplayLinkTarget* displayLinkTarget = nil;
    DoofGameIOSView* view = nil;
    std::atomic_bool running = true;
    std::atomic_bool renderRequested = false;
    std::atomic_bool renderCallbackPending = false;
    std::atomic_bool drainPending = false;
    std::mutex completionMutex;
    std::condition_variable completionReady;
    std::chrono::steady_clock::time_point fpsWindowStart = std::chrono::steady_clock::now();
    int32_t fpsFrameCount = 0;

    void emit(std::shared_ptr<NativeGameEvent> event) {
        doof::detail::ActiveActorScope active(&doof::detail::ApplicationDomain::shared());
        onEvent.call(event, input);
    }

    void resetFrameDeltas() {
        input->resetFrameDeltas();
    }

    void requestRender() {
        renderRequested.store(true);
    }

    void scheduleRender() {
        if (renderCallbackPending.exchange(true)) {
            return;
        }

        auto self = shared_from_this();
        dispatch_async(dispatch_get_main_queue(), ^{
            self->renderOnMain();
            self->renderCallbackPending.store(false);
        });
    }

    void renderOnMain() {
        if (!running.load()) {
            return;
        }

        if (!renderRequested.exchange(false)) {
            return;
        }

        {
            doof::detail::ActiveActorScope active(&doof::detail::ApplicationDomain::shared());
            onRender.call(surface, input);
        }
        recordRenderedFrame();
        resetFrameDeltas();
    }

    void scheduleDrainEvents() {
        if (drainPending.exchange(true)) {
            return;
        }

        auto self = shared_from_this();
        dispatch_async(dispatch_get_main_queue(), ^{
            self->drainPending.store(false);
            if (self->running.load()) {
                doof::detail::ActiveActorScope active(&doof::detail::ApplicationDomain::shared());
                self->drainEvents.call();
            }
        });
    }

    void stop() {
        if (!running.exchange(false)) {
            return;
        }

        auto self = shared_from_this();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->displayLink != nil) {
                [self->displayLink invalidate];
                [self->displayLink release];
                self->displayLink = nil;
            }
            if (self->displayLinkTarget != nil) {
                [self->displayLinkTarget release];
                self->displayLinkTarget = nil;
            }
            if (self->view != nil) {
                [self->view removeFromSuperview];
                [self->view release];
                self->view = nil;
            }
            self->completionReady.notify_all();
        });
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
};

std::string installIOSSurface(const std::shared_ptr<GameRuntimeState>& state) {
    __block NSString* errorMessage = nil;

    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow* window = nil;
        id delegate = UIApplication.sharedApplication.delegate;
        if ([delegate respondsToSelector:@selector(window)]) {
            window = [delegate window];
        }
        if (window == nil) {
            window = fallbackApplicationWindow();
        }
        if (window == nil) {
            errorMessage = @"UIApplication window is not ready";
            return;
        }

        UIViewController* rootViewController = window.rootViewController;
        if (rootViewController == nil) {
            rootViewController = [[[UIViewController alloc] init] autorelease];
            window.rootViewController = rootViewController;
        }

        UIView* rootView = rootViewController.view;
        if (rootView == nil) {
            errorMessage = @"UIApplication root view is not ready";
            return;
        }

        rootView.backgroundColor = UIColor.blackColor;

        DoofGameIOSView* view = [[DoofGameIOSView alloc] initWithState:state.get() frame:rootView.bounds];
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [rootView addSubview:view];
        state->view = view;

        CAMetalLayer* layer = (__bridge CAMetalLayer*)reinterpret_cast<void*>(state->surface->metalLayerHandle());
        [view.layer addSublayer:layer];
        updateLayerDrawableSize(view, state->surface);

        DoofGameDisplayLinkTarget* target = [[DoofGameDisplayLinkTarget alloc] initWithState:state.get()];
        CADisplayLink* displayLink = [CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
        displayLink.preferredFramesPerSecond = 60;
        [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        state->displayLinkTarget = target;
        state->displayLink = [displayLink retain];
    });

    return errorMessage != nil ? std::string([errorMessage UTF8String]) : std::string();
}

doof::Result<void, std::string> loadTextureWithCGImageSource(
    const std::string& path,
    id<MTLDevice> device,
    std::shared_ptr<NativeTexture>& out
) {
    std::string resolvedPath = resolveReadableAssetPath(path);
    NSURL* url = [NSURL fileURLWithPath:nsString(resolvedPath)];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
    if (source == nullptr) {
        return doof::Result<void, std::string>::failure("Failed to load image: " + path);
    }

    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
    CFRelease(source);
    if (image == nullptr) {
        return doof::Result<void, std::string>::failure("Failed to decode image: " + path);
    }

    const size_t width = CGImageGetWidth(image);
    const size_t height = CGImageGetHeight(image);
    if (width == 0 || height == 0) {
        CGImageRelease(image);
        return doof::Result<void, std::string>::failure("Image is empty: " + path);
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
        CGImageRelease(image);
        return doof::Result<void, std::string>::failure("Failed to create image decode context: " + path);
    }

    CGContextClearRect(context, CGRectMake(0, 0, static_cast<CGFloat>(width), static_cast<CGFloat>(height)));
    CGContextDrawImage(context, CGRectMake(0, 0, static_cast<CGFloat>(width), static_cast<CGFloat>(height)), image);
    CGContextRelease(context);
    CGImageRelease(image);

    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    if (texture == nil) {
        return doof::Result<void, std::string>::failure("Failed to create texture: " + path);
    }

    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0
                 withBytes:pixels.data()
               bytesPerRow:width * 4u];

    out = std::make_shared<NativeTexture>(
        (__bridge void*)texture,
        static_cast<int32_t>(width),
        static_cast<int32_t>(height)
    );
    [texture release];
    return doof::Result<void, std::string>::success();
}

}  // namespace
}  // namespace doof_game

@implementation DoofGameDisplayLinkTarget

- (instancetype)initWithState:(doof_game::GameRuntimeState*)state {
    self = [super init];
    if (self) {
        state_ = state;
    }
    return self;
}

- (void)tick:(CADisplayLink*)displayLink {
    (void)displayLink;
    if (state_ != nullptr && state_->running.load()) {
        state_->scheduleDrainEvents();
        state_->scheduleRender();
    }
}

@end

@implementation DoofGameIOSView

- (instancetype)initWithState:(doof_game::GameRuntimeState*)state frame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        state_ = state;
        primaryTouch_ = nil;
        secondaryTouch_ = nil;
        lastPinchDistance_ = 0.0;
        lastPinchMidpointX_ = 0.0;
        lastPinchMidpointY_ = 0.0;
        mouseDownEmitted_ = NO;
        pinching_ = NO;
        self.backgroundColor = UIColor.blackColor;
        self.multipleTouchEnabled = YES;
        self.opaque = YES;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    doof_game::updateLayerDrawableSize(self, state_->surface);
    state_->emit(doof_game::makeResizeEvent(state_->surface));
    state_->requestRender();
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    doof_game::updateLayerDrawableSize(self, state_->surface);
    state_->emit(doof_game::makeResizeEvent(state_->surface));
    state_->requestRender();
}

- (NSArray<UITouch*>*)activeTouchesForEvent:(UIEvent*)event {
    NSMutableArray<UITouch*>* active = [NSMutableArray arrayWithCapacity:2];
    for (UITouch* touch in [event allTouches]) {
        if (touch.view != self) {
            continue;
        }
        if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
            continue;
        }
        [active addObject:touch];
        if (active.count >= 2) {
            break;
        }
    }
    return active;
}

- (double)distanceBetweenFirstTouch:(UITouch*)first secondTouch:(UITouch*)second {
    CGPoint a = doof_game::gamePointForTouch(self, first);
    CGPoint b = doof_game::gamePointForTouch(self, second);
    const double dx = static_cast<double>(b.x - a.x);
    const double dy = static_cast<double>(b.y - a.y);
    return std::sqrt(dx * dx + dy * dy);
}

- (CGPoint)midpointBetweenFirstTouch:(UITouch*)first secondTouch:(UITouch*)second {
    CGPoint a = doof_game::gamePointForTouch(self, first);
    CGPoint b = doof_game::gamePointForTouch(self, second);
    return CGPointMake((a.x + b.x) * 0.5, (a.y + b.y) * 0.5);
}

- (void)emitMouseUpAtPoint:(CGPoint)point {
    state_->input->setMouseButtonDownCode(doof_game::kMouseLeft, false);
    state_->input->setMousePosition(point.x, point.y);
    state_->emit(std::make_shared<doof_game::NativeGameEvent>(
        doof_game::kKindMouseUp,
        doof_game::kKeyUnknown,
        doof_game::kMouseLeft,
        point.x,
        point.y
    ));
    mouseDownEmitted_ = NO;
}

- (void)beginPinchWithTouches:(NSArray<UITouch*>*)activeTouches {
    if (mouseDownEmitted_) {
        CGPoint point = doof_game::gamePointForTouch(self, primaryTouch_);
        state_->input->setMouseButtonDownCode(doof_game::kMouseLeft, false);
        state_->input->setMousePosition(point.x, point.y);
        state_->emit(std::make_shared<doof_game::NativeGameEvent>(
            doof_game::kKindMouseUp,
            doof_game::kKeyUnknown,
            doof_game::kMouseOther,
            point.x,
            point.y
        ));
        mouseDownEmitted_ = NO;
    }

    primaryTouch_ = activeTouches[0];
    secondaryTouch_ = activeTouches[1];
    lastPinchDistance_ = [self distanceBetweenFirstTouch:primaryTouch_ secondTouch:secondaryTouch_];
    CGPoint midpoint = [self midpointBetweenFirstTouch:primaryTouch_ secondTouch:secondaryTouch_];
    lastPinchMidpointX_ = midpoint.x;
    lastPinchMidpointY_ = midpoint.y;
    pinching_ = YES;
}

- (BOOL)updatePinchWithEvent:(UIEvent*)event {
    NSArray<UITouch*>* activeTouches = [self activeTouchesForEvent:event];
    if (activeTouches.count < 2) {
        pinching_ = NO;
        primaryTouch_ = nil;
        secondaryTouch_ = nil;
        lastPinchDistance_ = 0.0;
        lastPinchMidpointX_ = 0.0;
        lastPinchMidpointY_ = 0.0;
        return NO;
    }

    if (!pinching_) {
        [self beginPinchWithTouches:activeTouches];
        return YES;
    }

    primaryTouch_ = activeTouches[0];
    secondaryTouch_ = activeTouches[1];
    const double distance = [self distanceBetweenFirstTouch:primaryTouch_ secondTouch:secondaryTouch_];
    CGPoint midpoint = [self midpointBetweenFirstTouch:primaryTouch_ secondTouch:secondaryTouch_];
    if (lastPinchDistance_ <= 0.0) {
        lastPinchDistance_ = distance;
        lastPinchMidpointX_ = midpoint.x;
        lastPinchMidpointY_ = midpoint.y;
        return YES;
    }

    const double zoomDelta = distance - lastPinchDistance_;
    const double panDeltaX = static_cast<double>(midpoint.x) - lastPinchMidpointX_;
    const double panDeltaY = static_cast<double>(midpoint.y) - lastPinchMidpointY_;
    lastPinchDistance_ = distance;
    lastPinchMidpointX_ = midpoint.x;
    lastPinchMidpointY_ = midpoint.y;
    if (std::abs(zoomDelta) <= 0.01 && std::abs(panDeltaX) <= 0.01 && std::abs(panDeltaY) <= 0.01) {
        return YES;
    }

    state_->input->setMousePosition(midpoint.x, midpoint.y);
    state_->input->addMouseDelta(panDeltaX, panDeltaY);
    state_->input->addWheelDelta(0.0, zoomDelta);
    state_->emit(std::make_shared<doof_game::NativeGameEvent>(
        doof_game::kKindMouseWheel,
        doof_game::kKeyUnknown,
        doof_game::kMouseOther,
        midpoint.x,
        midpoint.y,
        panDeltaX,
        panDeltaY,
        0.0,
        zoomDelta
    ));
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    NSArray<UITouch*>* activeTouches = [self activeTouchesForEvent:event];
    if (activeTouches.count >= 2) {
        [self beginPinchWithTouches:activeTouches];
        return;
    }

    UITouch* touch = [touches anyObject];
    if (touch == nil || pinching_) {
        return;
    }
    primaryTouch_ = touch;
    CGPoint point = doof_game::gamePointForTouch(self, touch);
    state_->input->setMouseButtonDownCode(doof_game::kMouseLeft, true);
    state_->input->setMousePosition(point.x, point.y);
    state_->emit(std::make_shared<doof_game::NativeGameEvent>(
        doof_game::kKindMouseDown,
        doof_game::kKeyUnknown,
        doof_game::kMouseLeft,
        point.x,
        point.y
    ));
    mouseDownEmitted_ = YES;
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if ([self updatePinchWithEvent:event]) {
        return;
    }

    UITouch* touch = primaryTouch_ != nil ? primaryTouch_ : [touches anyObject];
    if (touch == nil || !mouseDownEmitted_) {
        return;
    }
    CGPoint point = doof_game::gamePointForTouch(self, touch);
    double dx = point.x - state_->input->mouseX();
    double dy = point.y - state_->input->mouseY();
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

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if (pinching_) {
        [self updatePinchWithEvent:event];
        return;
    }

    UITouch* touch = primaryTouch_ != nil ? primaryTouch_ : [touches anyObject];
    if (touch == nil || !mouseDownEmitted_) {
        primaryTouch_ = nil;
        return;
    }
    CGPoint point = doof_game::gamePointForTouch(self, touch);
    [self emitMouseUpAtPoint:point];
    primaryTouch_ = nil;
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self touchesEnded:touches withEvent:event];
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

    if (pathHasHdrExtension(path)) {
        auto loaded = loadRadianceHdrTexture(path, device);
        if (loaded.isSuccess()) {
            std::lock_guard<std::mutex> lock(textureCacheMutex());
            textureCache()[cacheKey] = loaded.value();
        }
        return loaded;
    }

    std::shared_ptr<NativeTexture> native;
    auto loaded = loadTextureWithCGImageSource(path, device, native);
    if (loaded.isFailure()) {
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure(loaded.error());
    }
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

int64_t NativeRenderPass::metalRenderCommandEncoderHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->encoder);
}

int64_t NativeRenderPass::metalCommandBufferHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->commandBuffer);
}

int64_t NativeRenderPass::metalDeviceHandle() const {
    return reinterpret_cast<int64_t>((__bridge void*)impl_->device);
}

bool NativeRenderPass::hasDepthAttachment() const {
    return impl_->hasDepth;
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
    int32_t blendMode,
    int32_t windingMode,
    int32_t cullMode
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

    [encoder setFrontFacingWinding:metalWindingForMode(windingMode)];
    [encoder setCullMode:metalCullModeForMode(cullMode)];

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

NativeInputState::NativeInputState()
    : impl_(std::make_shared<Impl>()) {}

NativeInputState::~NativeInputState() = default;

bool NativeInputState::isKeyDownCode(int32_t key) const {
    return impl_->keysDown.find(key) != impl_->keysDown.end();
}

bool NativeInputState::isMouseButtonDownCode(int32_t button) const {
    return impl_->mouseButtonsDown.find(button) != impl_->mouseButtonsDown.end();
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
    if (gActiveState != nullptr) {
        gActiveState->scheduleDrainEvents();
    }
}

void requestGameAppRender() {
    if (gActiveState != nullptr) {
        gActiveState->requestRender();
    }
}

void requestGameAppStop() {
    if (gActiveState != nullptr) {
        gActiveState->stop();
    }
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

        auto state = std::make_shared<GameRuntimeState>();
        state->input = impl_->input;
        state->surface = impl_->surface;
        state->onEvent = onEvent;
        state->onRender = onRender;
        state->drainEvents = drainEvents;
        state->framesPerSecond = &impl_->framesPerSecond;
        impl_->framesPerSecond.store(0.0);

        const std::string installError = installIOSSurface(state);
        if (!installError.empty()) {
            return doof::Result<void, std::string>::failure(installError);
        }

        gActiveState = state.get();
        drainEvents.call();
        state->emit(makeResizeEvent(state->surface));
        state->requestRender();

        std::unique_lock<std::mutex> lock(state->completionMutex);
        state->completionReady.wait(lock, [&state] {
            return !state->running.load();
        });

        drainEvents.call();
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
