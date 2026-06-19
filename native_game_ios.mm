#include "native_game.hpp"

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <ImageIO/ImageIO.h>
#import <Metal/Metal.h>
#import <QuartzCore/CADisplayLink.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cctype>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <limits>
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
constexpr int32_t kKindScroll = 7;
constexpr int32_t kKindDoubleTap = 8;
constexpr int32_t kKindMagnify = 9;
constexpr int32_t kKindPan = 10;
constexpr int32_t kKindControllerConnected = 11;
constexpr int32_t kKindControllerDisconnected = 12;

constexpr int32_t kKeyUnknown = 0;
constexpr int32_t kMouseLeft = 0;
constexpr int32_t kMouseOther = 3;

constexpr int32_t kControllerSlotCount = 4;
constexpr int32_t kControllerButtonCount = 16;
constexpr int32_t kControllerAxisCount = 6;

constexpr int32_t kControllerButtonSouth = 0;
constexpr int32_t kControllerButtonEast = 1;
constexpr int32_t kControllerButtonWest = 2;
constexpr int32_t kControllerButtonNorth = 3;
constexpr int32_t kControllerButtonLeftShoulder = 4;
constexpr int32_t kControllerButtonRightShoulder = 5;
constexpr int32_t kControllerButtonLeftTrigger = 6;
constexpr int32_t kControllerButtonRightTrigger = 7;
constexpr int32_t kControllerButtonMenu = 8;
constexpr int32_t kControllerButtonOptions = 9;
constexpr int32_t kControllerButtonLeftStick = 10;
constexpr int32_t kControllerButtonRightStick = 11;
constexpr int32_t kControllerButtonDPadUp = 12;
constexpr int32_t kControllerButtonDPadDown = 13;
constexpr int32_t kControllerButtonDPadLeft = 14;
constexpr int32_t kControllerButtonDPadRight = 15;

constexpr int32_t kControllerAxisLeftX = 0;
constexpr int32_t kControllerAxisLeftY = 1;
constexpr int32_t kControllerAxisRightX = 2;
constexpr int32_t kControllerAxisRightY = 3;
constexpr int32_t kControllerAxisLeftTrigger = 4;
constexpr int32_t kControllerAxisRightTrigger = 5;

constexpr double kDoubleTapMaxIntervalSeconds = 0.32;
constexpr double kDoubleTapMaxDistancePoints = 28.0;
constexpr double kTapMoveTolerancePoints = 10.0;
constexpr double kPanVelocitySmoothing = 0.35;
constexpr double kPanInertiaHalfLifeSeconds = 0.30;
constexpr double kPanInertiaMinStartVelocity = 20.0;
constexpr double kPanInertiaStopVelocity = 8.0;
constexpr double kPanInertiaMaxStepSeconds = 0.05;
constexpr double kPanVelocityMaxSampleSeconds = 0.10;

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

struct PanInertiaState {
    bool gestureActive = false;
    bool inertialActive = false;
    double lastX = 0.0;
    double lastY = 0.0;
    double lastVelocityTime = 0.0;
    double velocityX = 0.0;
    double velocityY = 0.0;
    double lastInertialTime = 0.0;
    double inertialVelocityX = 0.0;
    double inertialVelocityY = 0.0;

    void begin(GameRuntimeState* state, double x, double y, double timestamp);
    void update(GameRuntimeState* state, double x, double y, double timestamp);
    void finish(GameRuntimeState* state, double timestamp);
    void cancel();
    bool step(GameRuntimeState* state, double timestamp);

private:
    void emitPan(GameRuntimeState* state, double x, double y, double deltaX, double deltaY);
    void updateVelocity(double deltaX, double deltaY, double timestamp);
    void resetVelocity();
};

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
    std::array<bool, kControllerSlotCount> controllerConnected = { false, false, false, false };
    std::array<std::string, kControllerSlotCount> controllerNames;
    std::array<std::array<bool, kControllerButtonCount>, kControllerSlotCount> controllerButtonsDown = {};
    std::array<std::array<double, kControllerAxisCount>, kControllerSlotCount> controllerAxes = {};
    double mouseX = 0.0;
    double mouseY = 0.0;
    double mouseDeltaX = 0.0;
    double mouseDeltaY = 0.0;
    double panDeltaX = 0.0;
    double panDeltaY = 0.0;
    double scrollDeltaX = 0.0;
    double scrollDeltaY = 0.0;
    double magnificationDelta = 0.0;
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

@interface DoofGameIOSViewController : UIViewController
@end

@interface DoofGameIOSView : UIView {
@public
    doof_game::GameRuntimeState* state_;
    UITouch* primaryTouch_;
    UITouch* secondaryTouch_;
    double lastPinchDistance_;
    double lastPinchMidpointX_;
    double lastPinchMidpointY_;
    NSTimeInterval lastPanVelocityTime_;
    double panVelocityX_;
    double panVelocityY_;
    double touchStartX_;
    double touchStartY_;
    NSTimeInterval lastTapTime_;
    double lastTapX_;
    double lastTapY_;
    BOOL mouseDownEmitted_;
    BOOL pinching_;
    BOOL touchMovedTooFar_;
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

    return [touch locationInView:view];
}

bool validControllerSlot(int32_t slot) {
    return slot >= 0 && slot < kControllerSlotCount;
}

bool validControllerButton(int32_t button) {
    return button >= 0 && button < kControllerButtonCount;
}

bool validControllerAxis(int32_t axis) {
    return axis >= 0 && axis < kControllerAxisCount;
}

std::string stringFromNSString(NSString* value) {
    if (value == nil) {
        return "";
    }
    const char* utf8 = [value UTF8String];
    return utf8 == nullptr ? "" : std::string(utf8);
}

std::string controllerDisplayName(GCController* controller) {
    if (controller == nil) {
        return "";
    }
    if (controller.vendorName != nil && controller.vendorName.length > 0) {
        return stringFromNSString(controller.vendorName);
    }
    if (controller.productCategory != nil && controller.productCategory.length > 0) {
        return stringFromNSString(controller.productCategory);
    }
    return "Controller";
}

bool controllerButtonPressed(GCControllerButtonInput* button) {
    return button != nil && button.isPressed;
}

double controllerButtonValue(GCControllerButtonInput* button) {
    return button == nil ? 0.0 : static_cast<double>(button.value);
}

void resetControllerSlotInput(const std::shared_ptr<NativeInputState>& input, int32_t slot) {
    if (!input || !validControllerSlot(slot)) {
        return;
    }
    for (int32_t button = 0; button < kControllerButtonCount; ++button) {
        input->setControllerButtonDownCode(slot, button, false);
    }
    for (int32_t axis = 0; axis < kControllerAxisCount; ++axis) {
        input->setControllerAxisCode(slot, axis, 0.0);
    }
}

void updateControllerInputSlot(const std::shared_ptr<NativeInputState>& input, int32_t slot, GCController* controller) {
    if (!input || !validControllerSlot(slot)) {
        return;
    }

    if (controller == nil) {
        input->setControllerConnectedCode(slot, "", false);
        resetControllerSlotInput(input, slot);
        return;
    }

    input->setControllerConnectedCode(slot, controllerDisplayName(controller), true);
    resetControllerSlotInput(input, slot);

    GCExtendedGamepad* gamepad = controller.extendedGamepad;
    if (gamepad != nil) {
        input->setControllerButtonDownCode(slot, kControllerButtonSouth, controllerButtonPressed(gamepad.buttonA));
        input->setControllerButtonDownCode(slot, kControllerButtonEast, controllerButtonPressed(gamepad.buttonB));
        input->setControllerButtonDownCode(slot, kControllerButtonWest, controllerButtonPressed(gamepad.buttonX));
        input->setControllerButtonDownCode(slot, kControllerButtonNorth, controllerButtonPressed(gamepad.buttonY));
        input->setControllerButtonDownCode(slot, kControllerButtonLeftShoulder, controllerButtonPressed(gamepad.leftShoulder));
        input->setControllerButtonDownCode(slot, kControllerButtonRightShoulder, controllerButtonPressed(gamepad.rightShoulder));
        input->setControllerButtonDownCode(slot, kControllerButtonLeftTrigger, controllerButtonPressed(gamepad.leftTrigger));
        input->setControllerButtonDownCode(slot, kControllerButtonRightTrigger, controllerButtonPressed(gamepad.rightTrigger));
        if (@available(iOS 13.0, *)) {
            input->setControllerButtonDownCode(slot, kControllerButtonMenu, controllerButtonPressed(gamepad.buttonMenu));
            input->setControllerButtonDownCode(slot, kControllerButtonOptions, controllerButtonPressed(gamepad.buttonOptions));
        }
        if (@available(iOS 12.1, *)) {
            input->setControllerButtonDownCode(slot, kControllerButtonLeftStick, controllerButtonPressed(gamepad.leftThumbstickButton));
            input->setControllerButtonDownCode(slot, kControllerButtonRightStick, controllerButtonPressed(gamepad.rightThumbstickButton));
        }
        input->setControllerButtonDownCode(slot, kControllerButtonDPadUp, controllerButtonPressed(gamepad.dpad.up));
        input->setControllerButtonDownCode(slot, kControllerButtonDPadDown, controllerButtonPressed(gamepad.dpad.down));
        input->setControllerButtonDownCode(slot, kControllerButtonDPadLeft, controllerButtonPressed(gamepad.dpad.left));
        input->setControllerButtonDownCode(slot, kControllerButtonDPadRight, controllerButtonPressed(gamepad.dpad.right));

        input->setControllerAxisCode(slot, kControllerAxisLeftX, static_cast<double>(gamepad.leftThumbstick.xAxis.value));
        input->setControllerAxisCode(slot, kControllerAxisLeftY, static_cast<double>(gamepad.leftThumbstick.yAxis.value));
        input->setControllerAxisCode(slot, kControllerAxisRightX, static_cast<double>(gamepad.rightThumbstick.xAxis.value));
        input->setControllerAxisCode(slot, kControllerAxisRightY, static_cast<double>(gamepad.rightThumbstick.yAxis.value));
        input->setControllerAxisCode(slot, kControllerAxisLeftTrigger, controllerButtonValue(gamepad.leftTrigger));
        input->setControllerAxisCode(slot, kControllerAxisRightTrigger, controllerButtonValue(gamepad.rightTrigger));
        return;
    }

    GCMicroGamepad* micro = controller.microGamepad;
    if (micro != nil) {
        input->setControllerButtonDownCode(slot, kControllerButtonSouth, controllerButtonPressed(micro.buttonA));
        input->setControllerButtonDownCode(slot, kControllerButtonWest, controllerButtonPressed(micro.buttonX));
        if (@available(iOS 13.0, *)) {
            input->setControllerButtonDownCode(slot, kControllerButtonMenu, controllerButtonPressed(micro.buttonMenu));
        }
        input->setControllerButtonDownCode(slot, kControllerButtonDPadUp, controllerButtonPressed(micro.dpad.up));
        input->setControllerButtonDownCode(slot, kControllerButtonDPadDown, controllerButtonPressed(micro.dpad.down));
        input->setControllerButtonDownCode(slot, kControllerButtonDPadLeft, controllerButtonPressed(micro.dpad.left));
        input->setControllerButtonDownCode(slot, kControllerButtonDPadRight, controllerButtonPressed(micro.dpad.right));
        input->setControllerAxisCode(slot, kControllerAxisLeftX, static_cast<double>(micro.dpad.xAxis.value));
        input->setControllerAxisCode(slot, kControllerAxisLeftY, static_cast<double>(micro.dpad.yAxis.value));
    }
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
    PanInertiaState panInertia;
    std::array<GCController*, kControllerSlotCount> controllerSlots = { nil, nil, nil, nil };
    id controllerConnectObserver = nil;
    id controllerDisconnectObserver = nil;

    ~GameRuntimeState() {
        if (controllerConnectObserver != nil) {
            [NSNotificationCenter.defaultCenter removeObserver:controllerConnectObserver];
            controllerConnectObserver = nil;
        }
        if (controllerDisconnectObserver != nil) {
            [NSNotificationCenter.defaultCenter removeObserver:controllerDisconnectObserver];
            controllerDisconnectObserver = nil;
        }
        for (GCController* controller : controllerSlots) {
            [controller release];
        }
    }

    void emit(std::shared_ptr<NativeGameEvent> event) {
        doof::detail::ActiveActorScope active(&doof::detail::ApplicationDomain::shared());
        onEvent.call(event, input);
    }

    void initializeControllers() {
        for (GCController* controller in [GCController controllers]) {
            assignController(controller, false);
        }

        std::weak_ptr<GameRuntimeState> weakSelf = shared_from_this();
        controllerConnectObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:GCControllerDidConnectNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification* note) {
                        auto self = weakSelf.lock();
                        if (!self) {
                            return;
                        }
                        GCController* controller = (GCController*)note.object;
                        self->assignController(controller, true);
                    }];
        controllerDisconnectObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:GCControllerDidDisconnectNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification* note) {
                        auto self = weakSelf.lock();
                        if (!self) {
                            return;
                        }
                        GCController* controller = (GCController*)note.object;
                        self->disconnectController(controller);
                    }];
    }

    void assignController(GCController* controller, bool emitEvent) {
        if (controller == nil) {
            return;
        }
        for (int32_t slot = 0; slot < kControllerSlotCount; ++slot) {
            if (controllerSlots[slot] == controller) {
                updateControllerInputSlot(input, slot, controller);
                return;
            }
        }
        for (int32_t slot = 0; slot < kControllerSlotCount; ++slot) {
            if (controllerSlots[slot] != nil) {
                continue;
            }
            controllerSlots[slot] = [controller retain];
            updateControllerInputSlot(input, slot, controller);
            if (emitEvent) {
                emit(std::make_shared<NativeGameEvent>(
                    kKindControllerConnected,
                    kKeyUnknown,
                    kMouseOther,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0,
                    0,
                    0.0,
                    slot,
                    controllerDisplayName(controller)
                ));
            }
            return;
        }
    }

    void disconnectController(GCController* controller) {
        for (int32_t slot = 0; slot < kControllerSlotCount; ++slot) {
            if (controllerSlots[slot] != controller) {
                continue;
            }
            std::string name = controllerDisplayName(controllerSlots[slot]);
            [controllerSlots[slot] release];
            controllerSlots[slot] = nil;
            input->setControllerConnectedCode(slot, "", false);
            resetControllerSlotInput(input, slot);
            emit(std::make_shared<NativeGameEvent>(
                kKindControllerDisconnected,
                kKeyUnknown,
                kMouseOther,
                0.0,
                0.0,
                0.0,
                0.0,
                0.0,
                0.0,
                0.0,
                0.0,
                0,
                0,
                0.0,
                slot,
                name
            ));
            return;
        }
    }

    void updateControllers() {
        for (int32_t slot = 0; slot < kControllerSlotCount; ++slot) {
            updateControllerInputSlot(input, slot, controllerSlots[slot]);
        }
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

        updateControllers();
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
        panInertia.cancel();

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

void PanInertiaState::resetVelocity() {
    lastVelocityTime = 0.0;
    velocityX = 0.0;
    velocityY = 0.0;
}

void PanInertiaState::cancel() {
    gestureActive = false;
    inertialActive = false;
    lastInertialTime = 0.0;
    inertialVelocityX = 0.0;
    inertialVelocityY = 0.0;
    resetVelocity();
}

void PanInertiaState::begin(GameRuntimeState* state, double x, double y, double timestamp) {
    if (state == nullptr) {
        return;
    }
    cancel();
    gestureActive = true;
    lastX = x;
    lastY = y;
    lastVelocityTime = timestamp;
    state->input->setMousePosition(x, y);
}

void PanInertiaState::updateVelocity(double deltaX, double deltaY, double timestamp) {
    if (lastVelocityTime > 0.0) {
        const double dt = timestamp - lastVelocityTime;
        if (dt > 0.0 && dt <= kPanVelocityMaxSampleSeconds) {
            const double sampleVelocityX = deltaX / dt;
            const double sampleVelocityY = deltaY / dt;
            if (std::abs(velocityX) <= 0.000001 && std::abs(velocityY) <= 0.000001) {
                velocityX = sampleVelocityX;
                velocityY = sampleVelocityY;
            } else {
                velocityX = velocityX * (1.0 - kPanVelocitySmoothing) +
                    sampleVelocityX * kPanVelocitySmoothing;
                velocityY = velocityY * (1.0 - kPanVelocitySmoothing) +
                    sampleVelocityY * kPanVelocitySmoothing;
            }
        }
    }
    lastVelocityTime = timestamp;
}

void PanInertiaState::emitPan(GameRuntimeState* state, double x, double y, double deltaX, double deltaY) {
    if (state == nullptr) {
        return;
    }
    state->input->setMousePosition(x, y);
    state->input->addPanDelta(deltaX, deltaY);
    state->emit(std::make_shared<NativeGameEvent>(
        kKindPan,
        kKeyUnknown,
        kMouseOther,
        x,
        y,
        0.0,
        0.0,
        deltaX,
        deltaY,
        0.0,
        0.0,
        0,
        0
    ));
}

void PanInertiaState::update(GameRuntimeState* state, double x, double y, double timestamp) {
    if (state == nullptr || !gestureActive) {
        return;
    }
    const double deltaX = x - lastX;
    const double deltaY = y - lastY;
    updateVelocity(deltaX, deltaY, timestamp);
    lastX = x;
    lastY = y;
    if (std::abs(deltaX) <= 0.01 && std::abs(deltaY) <= 0.01) {
        state->input->setMousePosition(x, y);
        return;
    }
    emitPan(state, x, y, deltaX, deltaY);
}

void PanInertiaState::finish(GameRuntimeState* state, double timestamp) {
    if (state == nullptr || !gestureActive) {
        return;
    }
    gestureActive = false;
    const double speed = std::sqrt(velocityX * velocityX + velocityY * velocityY);
    if (speed >= kPanInertiaMinStartVelocity) {
        inertialActive = true;
        inertialVelocityX = velocityX;
        inertialVelocityY = velocityY;
        lastInertialTime = timestamp;
        state->requestRender();
    } else {
        inertialActive = false;
        lastInertialTime = 0.0;
        inertialVelocityX = 0.0;
        inertialVelocityY = 0.0;
    }
    resetVelocity();
}

bool PanInertiaState::step(GameRuntimeState* state, double timestamp) {
    if (state == nullptr || !inertialActive) {
        return false;
    }
    if (lastInertialTime <= 0.0) {
        lastInertialTime = timestamp;
        return true;
    }

    double dt = timestamp - lastInertialTime;
    lastInertialTime = timestamp;
    if (dt <= 0.0) {
        return true;
    }
    dt = std::min(dt, kPanInertiaMaxStepSeconds);

    const double speed = std::sqrt(
        inertialVelocityX * inertialVelocityX +
        inertialVelocityY * inertialVelocityY
    );
    if (speed < kPanInertiaStopVelocity) {
        inertialActive = false;
        lastInertialTime = 0.0;
        inertialVelocityX = 0.0;
        inertialVelocityY = 0.0;
        return false;
    }

    const double deltaX = inertialVelocityX * dt;
    const double deltaY = inertialVelocityY * dt;
    lastX += deltaX;
    lastY += deltaY;
    emitPan(state, lastX, lastY, deltaX, deltaY);

    const double decay = std::pow(0.5, dt / kPanInertiaHalfLifeSeconds);
    inertialVelocityX *= decay;
    inertialVelocityY *= decay;
    return true;
}

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
            rootViewController = [[[DoofGameIOSViewController alloc] init] autorelease];
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

        [rootViewController setNeedsUpdateOfScreenEdgesDeferringSystemGestures];
        [rootViewController setNeedsUpdateOfHomeIndicatorAutoHidden];
        [rootViewController setNeedsStatusBarAppearanceUpdate];

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
    if (state_ != nullptr && state_->running.load()) {
        if (state_->panInertia.step(state_, displayLink.timestamp)) {
            state_->requestRender();
        }
        state_->scheduleDrainEvents();
        state_->scheduleRender();
    }
}

@end

@implementation DoofGameIOSViewController

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    // Keeping the indicator visible preserves bottom-edge gesture deferral.
    return NO;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
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
        lastPanVelocityTime_ = 0.0;
        panVelocityX_ = 0.0;
        panVelocityY_ = 0.0;
        touchStartX_ = 0.0;
        touchStartY_ = 0.0;
        lastTapTime_ = 0.0;
        lastTapX_ = 0.0;
        lastTapY_ = 0.0;
        mouseDownEmitted_ = NO;
        pinching_ = NO;
        touchMovedTooFar_ = NO;
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
    state_->input->setMouseButtonDownCode(doof_game::kMouseOther, false);
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

- (void)cancelInertialPan {
    if (state_ != nullptr) {
        state_->panInertia.cancel();
    }
}

- (void)updatePanVelocityWithDeltaX:(double)deltaX deltaY:(double)deltaY timestamp:(NSTimeInterval)timestamp {
    if (lastPanVelocityTime_ > 0.0) {
        const double dt = timestamp - lastPanVelocityTime_;
        if (dt > 0.0 && dt <= doof_game::kPanVelocityMaxSampleSeconds) {
            const double sampleVelocityX = deltaX / dt;
            const double sampleVelocityY = deltaY / dt;
            if (std::abs(panVelocityX_) <= 0.000001 && std::abs(panVelocityY_) <= 0.000001) {
                panVelocityX_ = sampleVelocityX;
                panVelocityY_ = sampleVelocityY;
            } else {
                panVelocityX_ = panVelocityX_ * (1.0 - doof_game::kPanVelocitySmoothing) +
                    sampleVelocityX * doof_game::kPanVelocitySmoothing;
                panVelocityY_ = panVelocityY_ * (1.0 - doof_game::kPanVelocitySmoothing) +
                    sampleVelocityY * doof_game::kPanVelocitySmoothing;
            }
        }
    }
    lastPanVelocityTime_ = timestamp;
}

- (void)finishPinchGestureAtTime:(NSTimeInterval)timestamp {
    const double speed = std::sqrt(panVelocityX_ * panVelocityX_ + panVelocityY_ * panVelocityY_);
    if (state_ != nullptr && speed >= doof_game::kPanInertiaMinStartVelocity) {
        state_->panInertia.cancel();
        state_->panInertia.gestureActive = true;
        state_->panInertia.lastX = lastPinchMidpointX_;
        state_->panInertia.lastY = lastPinchMidpointY_;
        state_->panInertia.velocityX = panVelocityX_;
        state_->panInertia.velocityY = panVelocityY_;
        state_->panInertia.finish(state_, timestamp > 0.0 ? timestamp : CACurrentMediaTime());
    } else {
        [self cancelInertialPan];
    }

    pinching_ = NO;
    primaryTouch_ = nil;
    secondaryTouch_ = nil;
    lastPinchDistance_ = 0.0;
    lastPanVelocityTime_ = 0.0;
    panVelocityX_ = 0.0;
    panVelocityY_ = 0.0;
}

- (void)beginPinchWithTouches:(NSArray<UITouch*>*)activeTouches {
    [self cancelInertialPan];
    if (mouseDownEmitted_) {
        CGPoint point = doof_game::gamePointForTouch(self, primaryTouch_);
        state_->input->setMouseButtonDownCode(doof_game::kMouseOther, false);
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
    touchMovedTooFar_ = YES;

    primaryTouch_ = activeTouches[0];
    secondaryTouch_ = activeTouches[1];
    lastPinchDistance_ = [self distanceBetweenFirstTouch:primaryTouch_ secondTouch:secondaryTouch_];
    CGPoint midpoint = [self midpointBetweenFirstTouch:primaryTouch_ secondTouch:secondaryTouch_];
    lastPinchMidpointX_ = midpoint.x;
    lastPinchMidpointY_ = midpoint.y;
    lastPanVelocityTime_ = std::max(primaryTouch_.timestamp, secondaryTouch_.timestamp);
    panVelocityX_ = 0.0;
    panVelocityY_ = 0.0;
    pinching_ = YES;
}

- (BOOL)updatePinchWithEvent:(UIEvent*)event {
    NSArray<UITouch*>* activeTouches = [self activeTouchesForEvent:event];
    if (activeTouches.count < 2) {
        if (pinching_) {
            [self finishPinchGestureAtTime:event.timestamp];
        }
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

    const double magnificationDelta = distance / lastPinchDistance_ - 1.0;
    const double panDeltaX = static_cast<double>(midpoint.x) - lastPinchMidpointX_;
    const double panDeltaY = static_cast<double>(midpoint.y) - lastPinchMidpointY_;
    [self updatePanVelocityWithDeltaX:panDeltaX
                               deltaY:panDeltaY
                            timestamp:std::max(primaryTouch_.timestamp, secondaryTouch_.timestamp)];
    lastPinchDistance_ = distance;
    lastPinchMidpointX_ = midpoint.x;
    lastPinchMidpointY_ = midpoint.y;
    if (std::abs(magnificationDelta) <= 0.000001 && std::abs(panDeltaX) <= 0.01 && std::abs(panDeltaY) <= 0.01) {
        return YES;
    }

    state_->input->setMousePosition(midpoint.x, midpoint.y);
    state_->input->addPanDelta(panDeltaX, panDeltaY);
    state_->input->addMagnificationDelta(magnificationDelta);
    state_->emit(std::make_shared<doof_game::NativeGameEvent>(
        doof_game::kKindMagnify,
        doof_game::kKeyUnknown,
        doof_game::kMouseOther,
        midpoint.x,
        midpoint.y,
        0.0,
        0.0,
        panDeltaX,
        panDeltaY,
        0.0,
        0.0,
        0,
        0,
        magnificationDelta
    ));
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self cancelInertialPan];
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
    touchStartX_ = point.x;
    touchStartY_ = point.y;
    touchMovedTooFar_ = NO;
    state_->input->setMousePosition(point.x, point.y);

    state_->input->setMouseButtonDownCode(doof_game::kMouseOther, true);
    state_->input->setMousePosition(point.x, point.y);
    state_->emit(std::make_shared<doof_game::NativeGameEvent>(
        doof_game::kKindMouseDown,
        doof_game::kKeyUnknown,
        doof_game::kMouseOther,
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
    double totalDx = point.x - touchStartX_;
    double totalDy = point.y - touchStartY_;
    if (std::sqrt(totalDx * totalDx + totalDy * totalDy) > doof_game::kTapMoveTolerancePoints) {
        touchMovedTooFar_ = YES;
    }
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

    if (!touchMovedTooFar_) {
        NSTimeInterval tapTime = touch.timestamp;
        double tapDx = point.x - lastTapX_;
        double tapDy = point.y - lastTapY_;
        double tapDistance = std::sqrt(tapDx * tapDx + tapDy * tapDy);
        if (lastTapTime_ > 0.0 &&
            tapTime - lastTapTime_ <= doof_game::kDoubleTapMaxIntervalSeconds &&
            tapDistance <= doof_game::kDoubleTapMaxDistancePoints) {
            state_->emit(std::make_shared<doof_game::NativeGameEvent>(
                doof_game::kKindDoubleTap,
                doof_game::kKeyUnknown,
                doof_game::kMouseOther,
                point.x,
                point.y
            ));
            lastTapTime_ = 0.0;
        } else {
            lastTapTime_ = tapTime;
            lastTapX_ = point.x;
            lastTapY_ = point.y;
        }
    } else {
        lastTapTime_ = 0.0;
    }

    primaryTouch_ = nil;
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    touchMovedTooFar_ = YES;
    lastTapTime_ = 0.0;
    if (pinching_) {
        [self cancelInertialPan];
        pinching_ = NO;
        primaryTouch_ = nil;
        secondaryTouch_ = nil;
        lastPinchDistance_ = 0.0;
        lastPanVelocityTime_ = 0.0;
        panVelocityX_ = 0.0;
        panVelocityY_ = 0.0;
        return;
    }
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

doof::Result<std::shared_ptr<NativeTexture>, std::string> NativeTexture::createAlpha4(
    const std::shared_ptr<std::vector<uint8_t>>& data,
    int32_t pixelWidth,
    int32_t pixelHeight,
    int64_t metalDeviceHandle
) {
    id<MTLDevice> device = (__bridge id<MTLDevice>)reinterpret_cast<void*>(metalDeviceHandle);
    if (device == nil) {
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure("Metal device handle is invalid");
    }
    if (pixelWidth <= 0 || pixelHeight <= 0) {
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure(
            "Alpha texture dimensions must be positive"
        );
    }

    const size_t width = static_cast<size_t>(pixelWidth);
    const size_t height = static_cast<size_t>(pixelHeight);
    if (width > std::numeric_limits<size_t>::max() / height ||
        width * height > std::numeric_limits<size_t>::max() / 4u) {
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure(
            "Alpha texture dimensions are too large"
        );
    }

    const size_t pixelCount = width * height;
    const size_t expectedSize = (pixelCount + 1u) / 2u;
    if (!data || data->size() != expectedSize) {
        const size_t actualSize = data ? data->size() : 0u;
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure(
            "Alpha4 buffer has " + std::to_string(actualSize) +
            " bytes; expected " + std::to_string(expectedSize)
        );
    }

    std::vector<uint8_t> pixels(pixelCount * 4u);
    for (size_t pixelIndex = 0; pixelIndex < pixelCount; ++pixelIndex) {
        const uint8_t packed = (*data)[pixelIndex / 2u];
        const uint8_t alpha4 = (pixelIndex % 2u == 0u)
            ? static_cast<uint8_t>(packed >> 4u)
            : static_cast<uint8_t>(packed & 0x0fu);
        const size_t rgbaIndex = pixelIndex * 4u;
        pixels[rgbaIndex] = 255u;
        pixels[rgbaIndex + 1u] = 255u;
        pixels[rgbaIndex + 2u] = 255u;
        pixels[rgbaIndex + 3u] = static_cast<uint8_t>(alpha4 * 17u);
    }

    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    if (texture == nil) {
        return doof::Result<std::shared_ptr<NativeTexture>, std::string>::failure(
            "Failed to create Alpha4 texture"
        );
    }

    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0
                 withBytes:pixels.data()
               bytesPerRow:width * 4u];

    auto native = std::make_shared<NativeTexture>(
        (__bridge void*)texture,
        pixelWidth,
        pixelHeight
    );
    [texture release];
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
    double panDeltaX,
    double panDeltaY,
    double scrollDeltaX,
    double scrollDeltaY,
    int32_t pixelWidth,
    int32_t pixelHeight,
    double magnificationDelta,
    int32_t controllerSlotCode,
    const std::string& controllerName
) : kindCode_(kindCode),
    keyCode_(keyCode),
    mouseButtonCode_(mouseButtonCode),
    controllerSlotCode_(controllerSlotCode),
    controllerName_(controllerName),
    x_(x),
    y_(y),
    deltaX_(deltaX),
    deltaY_(deltaY),
    panDeltaX_(panDeltaX),
    panDeltaY_(panDeltaY),
    scrollDeltaX_(scrollDeltaX),
    scrollDeltaY_(scrollDeltaY),
    pixelWidth_(pixelWidth),
    pixelHeight_(pixelHeight),
    magnificationDelta_(magnificationDelta) {}

int32_t NativeGameEvent::kindCode() const { return kindCode_; }
int32_t NativeGameEvent::keyCode() const { return keyCode_; }
int32_t NativeGameEvent::mouseButtonCode() const { return mouseButtonCode_; }
int32_t NativeGameEvent::controllerSlotCode() const { return controllerSlotCode_; }
std::string NativeGameEvent::controllerName() const { return controllerName_; }
double NativeGameEvent::x() const { return x_; }
double NativeGameEvent::y() const { return y_; }
double NativeGameEvent::deltaX() const { return deltaX_; }
double NativeGameEvent::deltaY() const { return deltaY_; }
double NativeGameEvent::panDeltaX() const { return panDeltaX_; }
double NativeGameEvent::panDeltaY() const { return panDeltaY_; }
double NativeGameEvent::scrollDeltaX() const { return scrollDeltaX_; }
double NativeGameEvent::scrollDeltaY() const { return scrollDeltaY_; }
int32_t NativeGameEvent::pixelWidth() const { return pixelWidth_; }
int32_t NativeGameEvent::pixelHeight() const { return pixelHeight_; }
double NativeGameEvent::magnificationDelta() const { return magnificationDelta_; }

NativeInputState::NativeInputState()
    : impl_(std::make_shared<Impl>()) {}

NativeInputState::~NativeInputState() = default;

bool NativeInputState::isKeyDownCode(int32_t key) const {
    return impl_->keysDown.find(key) != impl_->keysDown.end();
}

bool NativeInputState::isMouseButtonDownCode(int32_t button) const {
    return impl_->mouseButtonsDown.find(button) != impl_->mouseButtonsDown.end();
}

bool NativeInputState::isControllerConnectedCode(int32_t slot) const {
    return validControllerSlot(slot) && impl_->controllerConnected[slot];
}

std::string NativeInputState::controllerNameCode(int32_t slot) const {
    return validControllerSlot(slot) ? impl_->controllerNames[slot] : "";
}

bool NativeInputState::isControllerButtonDownCode(int32_t slot, int32_t button) const {
    if (!validControllerSlot(slot) || !validControllerButton(button)) {
        return false;
    }
    return impl_->controllerButtonsDown[slot][button];
}

double NativeInputState::controllerAxisCode(int32_t slot, int32_t axis) const {
    if (!validControllerSlot(slot) || !validControllerAxis(axis)) {
        return 0.0;
    }
    return impl_->controllerAxes[slot][axis];
}

double NativeInputState::mouseX() const { return impl_->mouseX; }
double NativeInputState::mouseY() const { return impl_->mouseY; }
double NativeInputState::mouseDeltaX() const { return impl_->mouseDeltaX; }
double NativeInputState::mouseDeltaY() const { return impl_->mouseDeltaY; }
double NativeInputState::panDeltaX() const { return impl_->panDeltaX; }
double NativeInputState::panDeltaY() const { return impl_->panDeltaY; }
double NativeInputState::scrollDeltaX() const { return impl_->scrollDeltaX; }
double NativeInputState::scrollDeltaY() const { return impl_->scrollDeltaY; }
double NativeInputState::magnificationDelta() const { return impl_->magnificationDelta; }

void NativeInputState::resetFrameDeltas() {
    impl_->mouseDeltaX = 0.0;
    impl_->mouseDeltaY = 0.0;
    impl_->panDeltaX = 0.0;
    impl_->panDeltaY = 0.0;
    impl_->scrollDeltaX = 0.0;
    impl_->scrollDeltaY = 0.0;
    impl_->magnificationDelta = 0.0;
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

void NativeInputState::setControllerConnectedCode(int32_t slot, const std::string& name, bool isConnected) {
    if (!validControllerSlot(slot)) {
        return;
    }
    impl_->controllerConnected[slot] = isConnected;
    impl_->controllerNames[slot] = isConnected ? name : "";
}

void NativeInputState::setControllerButtonDownCode(int32_t slot, int32_t button, bool isDown) {
    if (!validControllerSlot(slot) || !validControllerButton(button)) {
        return;
    }
    impl_->controllerButtonsDown[slot][button] = isDown;
}

void NativeInputState::setControllerAxisCode(int32_t slot, int32_t axis, double value) {
    if (!validControllerSlot(slot) || !validControllerAxis(axis)) {
        return;
    }
    impl_->controllerAxes[slot][axis] = value;
}

void NativeInputState::setMousePosition(double x, double y) {
    impl_->mouseX = x;
    impl_->mouseY = y;
}

void NativeInputState::addMouseDelta(double x, double y) {
    impl_->mouseDeltaX += x;
    impl_->mouseDeltaY += y;
}

void NativeInputState::addPanDelta(double x, double y) {
    impl_->panDeltaX += x;
    impl_->panDeltaY += y;
}

void NativeInputState::addScrollDelta(double x, double y) {
    impl_->scrollDeltaX += x;
    impl_->scrollDeltaY += y;
}

void NativeInputState::addMagnificationDelta(double delta) {
    impl_->magnificationDelta += delta;
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

void beginGameAppPanGesture(double x, double y) {
    if (gActiveState != nullptr) {
        gActiveState->panInertia.begin(gActiveState, x, y, CACurrentMediaTime());
    }
}

void updateGameAppPanGesture(double x, double y) {
    if (gActiveState != nullptr) {
        gActiveState->panInertia.update(gActiveState, x, y, CACurrentMediaTime());
    }
}

void endGameAppPanGesture() {
    if (gActiveState != nullptr) {
        gActiveState->panInertia.finish(gActiveState, CACurrentMediaTime());
    }
}

void cancelGameAppPanGesture() {
    if (gActiveState != nullptr) {
        gActiveState->panInertia.cancel();
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
        state->initializeControllers();
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
