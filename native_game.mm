#include "native_game.hpp"

#import <AppKit/AppKit.h>
#import <CoreGraphics/CGDirectDisplayMetal.h>
#import <CoreVideo/CoreVideo.h>
#import <GameController/GameController.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <dispatch/dispatch.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <limits>
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
constexpr int32_t kKindScroll = 7;
constexpr int32_t kKindMagnify = 9;
constexpr int32_t kKindPan = 10;
constexpr int32_t kKindControllerConnected = 11;
constexpr int32_t kKindControllerDisconnected = 12;

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

constexpr double kPanVelocitySmoothing = 0.35;
constexpr double kPanInertiaHalfLifeSeconds = 0.30;
constexpr double kPanInertiaMinStartVelocity = 20.0;
constexpr double kPanInertiaStopVelocity = 8.0;
constexpr double kPanInertiaMaxStepSeconds = 0.05;
constexpr double kPanVelocityMaxSampleSeconds = 0.10;

constexpr int32_t kClearNone = 0;
constexpr int32_t kClearColor = 1;
constexpr int32_t kClearDepth = 2;
constexpr int32_t kClearColorDepth = 3;

constexpr int32_t kDepthDisabled = 0;
constexpr int32_t kDepthReadOnly = 1;
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
        if (@available(macOS 10.15, *)) {
            input->setControllerButtonDownCode(slot, kControllerButtonMenu, controllerButtonPressed(gamepad.buttonMenu));
            input->setControllerButtonDownCode(slot, kControllerButtonOptions, controllerButtonPressed(gamepad.buttonOptions));
        }
        if (@available(macOS 10.14.1, *)) {
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
        if (@available(macOS 10.15, *)) {
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
    std::ifstream file(path, std::ios::binary);
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

    auto native = std::make_shared<NativeTexture>(
        (__bridge void*)texture,
        width,
        height
    );
    [texture release];
    return doof::Result<std::shared_ptr<NativeTexture>, std::string>::success(native);
}

NSScreen* targetLaunchScreen() {
    NSArray<NSScreen*>* screens = [NSScreen screens];
    if ([screens count] == 0) {
        return [NSScreen mainScreen];
    }

    NSPoint mouseLocation = [NSEvent mouseLocation];
    for (NSScreen* screen in screens) {
        if (NSMouseInRect(mouseLocation, [screen frame], NO)) {
            return screen;
        }
    }

    NSScreen* mainScreen = [NSScreen mainScreen];
    return mainScreen != nil ? mainScreen : [screens objectAtIndex:0];
}

CGDirectDisplayID directDisplayIdForScreen(NSScreen* screen) {
    if (screen == nil) {
        return kCGNullDirectDisplay;
    }

    NSNumber* screenNumber = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
    if (screenNumber == nil) {
        return kCGNullDirectDisplay;
    }
    return static_cast<CGDirectDisplayID>([screenNumber unsignedIntValue]);
}

id<MTLDevice> newMetalDeviceForScreen(NSScreen* screen) {
    CGDirectDisplayID displayID = directDisplayIdForScreen(screen);
    if (displayID != kCGNullDirectDisplay) {
        id<MTLDevice> device = CGDirectDisplayCopyCurrentMetalDevice(displayID);
        if (device != nil) {
            return device;
        }
    }

    return MTLCreateSystemDefaultDevice();
}

double backingScaleForScreen(NSScreen* screen) {
    if (screen != nil) {
        double scale = [screen backingScaleFactor];
        return scale > 0.0 ? scale : 1.0;
    }

    NSScreen* mainScreen = [NSScreen mainScreen];
    if (mainScreen != nil) {
        double scale = [mainScreen backingScaleFactor];
        return scale > 0.0 ? scale : 1.0;
    }

    return 1.0;
}

void updateLayerDrawableSizeForScreen(CAMetalLayer* layer, NSScreen* screen) {
    if (layer == nil) {
        return;
    }

    double scale = backingScaleForScreen(screen);
    NSSize pointSize = screen != nil ? [screen frame].size : NSMakeSize(1.0, 1.0);
    layer.contentsScale = scale;
    layer.drawableSize = CGSizeMake(
        std::max(pointSize.width * scale, 1.0),
        std::max(pointSize.height * scale, 1.0)
    );
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
    NSScreen* screen = nil;
    CGDirectDisplayID displayID = kCGNullDirectDisplay;

    explicit Impl(std::string title)
        : title(std::move(title)),
          input(std::make_shared<NativeInputState>()) {
        screen = [targetLaunchScreen() retain];
        displayID = directDisplayIdForScreen(screen);

        id<MTLDevice> device = newMetalDeviceForScreen(screen);
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
        layer.maximumDrawableCount = 3;
        updateLayerDrawableSizeForScreen(layer, screen);

        surface = std::make_shared<NativeGameSurface>(
            (__bridge void*)device,
            (__bridge void*)commandQueue,
            (__bridge void*)layer
        );

        [layer release];
        [commandQueue release];
        [device release];
    }

    ~Impl() {
        [screen release];
    }
};

namespace {

struct GameRuntimeState : std::enable_shared_from_this<GameRuntimeState> {
    std::shared_ptr<NativeInputState> input;
    std::shared_ptr<NativeGameSurface> surface;
    doof::callback<void(std::shared_ptr<NativeGameEvent>, std::shared_ptr<NativeInputState>)> onEvent;
    doof::callback<void(std::shared_ptr<NativeGameSurface>, std::shared_ptr<NativeInputState>)> onRender;
    doof::callback<int32_t()> drainEvents;
    std::atomic<double>* framesPerSecond = nullptr;
    CVDisplayLinkRef displayLink = nullptr;
    std::atomic_bool running = true;
    std::atomic_bool renderRequested = false;
    std::atomic_bool renderCallbackPending = false;
    std::atomic_bool displayLinkRunning = false;
    std::atomic_bool drainPending = false;
    std::atomic_bool panInertiaStepPending = false;
    std::chrono::steady_clock::time_point fpsWindowStart = std::chrono::steady_clock::now();
    int32_t fpsFrameCount = 0;
    bool shiftDown = false;
    bool controlDown = false;
    bool optionDown = false;
    bool commandDown = false;
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
        if (!displayLinkRunning.load()) {
            scheduleDisplayLinkStart();
        }
    }

    void scheduleDisplayLinkStart() {
        auto self = shared_from_this();
        dispatch_async(dispatch_get_main_queue(), ^{
            self->startDisplayLinkIfNeeded();
        });
    }

    void startDisplayLinkIfNeeded() {
        if (!running.load() || displayLink == nullptr || !renderRequested.load()) {
            return;
        }
        if (!displayLinkRunning.exchange(true)) {
            CVDisplayLinkStart(displayLink);
        }
    }

    void stopDisplayLink() {
        if (displayLink != nullptr && displayLinkRunning.exchange(false)) {
            CVDisplayLinkStop(displayLink);
        }
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
            stopDisplayLink();
            return;
        }

        if (!renderRequested.exchange(false)) {
            stopDisplayLink();
            return;
        }

        updateControllers();
        onRender.call(surface, input);
        recordRenderedFrame();
        resetFrameDeltas();

        if (panInertia.inertialActive) {
            requestRender();
        }

        if (!renderRequested.load()) {
            stopDisplayLink();
        }
    }

    void scheduleDrainEvents() {
        if (drainPending.exchange(true)) {
            return;
        }

        auto self = shared_from_this();
        dispatch_async(dispatch_get_main_queue(), ^{
            self->drainPending.store(false);
            if (self->running.load()) {
                self->drainEvents.call();
            }
        });
    }

    void schedulePanInertiaStep() {
        if (panInertiaStepPending.exchange(true)) {
            return;
        }

        auto self = shared_from_this();
        dispatch_async(dispatch_get_main_queue(), ^{
            self->panInertiaStepPending.store(false);
            if (self->running.load() && self->panInertia.step(self.get(), CACurrentMediaTime())) {
                self->requestRender();
            }
        });
    }

    void stop() {
        running.store(false);
        panInertia.cancel();
        stopDisplayLink();
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp stop:nil];
            CFRunLoopStop(CFRunLoopGetMain());
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
        0.0,
        0.0,
        surface->pixelWidth(),
        surface->pixelHeight()
    );
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

    state->schedulePanInertiaStep();
    state->scheduleRender();

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
- (instancetype)initWithState:(doof_game::GameRuntimeState*)state frame:(NSRect)frame;
@end

@implementation DoofGameView

- (instancetype)initWithState:(doof_game::GameRuntimeState*)state frame:(NSRect)frame {
    self = [super initWithFrame:frame];
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
    bool precise = [event hasPreciseScrollingDeltas];
    NSPoint point = [self gamePointForEvent:event];
    if (precise) {
        state_->input->setMousePosition(point.x, point.y);
        state_->input->addPanDelta(dx, dy);
    } else {
        state_->input->addScrollDelta(dx, dy);
    }
    state_->emit(std::make_shared<doof_game::NativeGameEvent>(
        precise ? doof_game::kKindPan : doof_game::kKindScroll,
        doof_game::kKeyUnknown,
        doof_game::kMouseOther,
        point.x,
        point.y,
        0.0,
        0.0,
        precise ? dx : 0.0,
        precise ? dy : 0.0,
        precise ? 0.0 : dx,
        precise ? 0.0 : dy,
        0,
        0
    ));
}

- (void)magnifyWithEvent:(NSEvent*)event {
    double delta = [event magnification];
    if (std::abs(delta) <= 0.000001) {
        return;
    }
    NSPoint point = [self gamePointForEvent:event];
    state_->input->setMousePosition(point.x, point.y);
    state_->input->addMagnificationDelta(delta);
    state_->emit(std::make_shared<doof_game::NativeGameEvent>(
        doof_game::kKindMagnify,
        doof_game::kKeyUnknown,
        doof_game::kMouseOther,
        point.x,
        point.y,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0,
        0,
        delta
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
    state_->stop();
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

    if (pathHasHdrExtension(path)) {
        auto loaded = loadRadianceHdrTexture(path, device);
        if (loaded.isSuccess()) {
            std::lock_guard<std::mutex> lock(textureCacheMutex());
            textureCache()[cacheKey] = loaded.value();
        }
        return loaded;
    }

    NSString* nsPath = nsString(path);
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

NativeInputState::NativeInputState() : impl_(std::make_shared<Impl>()) {}
NativeInputState::~NativeInputState() = default;

bool NativeInputState::isKeyDownCode(int32_t key) const {
    return impl_->keysDown.count(key) > 0;
}

bool NativeInputState::isMouseButtonDownCode(int32_t button) const {
    return impl_->mouseButtonsDown.count(button) > 0;
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

        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        auto input = impl_->input;
        auto surface = impl_->surface;

        auto state = std::make_shared<GameRuntimeState>();
        state->input = input;
        state->surface = surface;
        state->onEvent = onEvent;
        state->onRender = onRender;
        state->drainEvents = drainEvents;
        state->framesPerSecond = &impl_->framesPerSecond;
        impl_->framesPerSecond.store(0.0);
        gActiveState = state.get();
        state->initializeControllers();
        CVDisplayLinkRef displayLink = nullptr;

        NSScreen* screen = impl_->screen != nil ? impl_->screen : targetLaunchScreen();
        NSRect frame = [screen frame];
        NSRect contentFrame = NSMakeRect(0.0, 0.0, NSWidth(frame), NSHeight(frame));
        DoofGameWindow* window = [[DoofGameWindow alloc] initWithContentRect:contentFrame
                                                                   styleMask:NSWindowStyleMaskBorderless
                                                                     backing:NSBackingStoreBuffered
                                                                       defer:NO
                                                                      screen:screen];
        [window setTitle:[NSString stringWithUTF8String:impl_->title.c_str()]];
        [window setLevel:NSMainMenuWindowLevel + 1];
        [window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary];
        [window setOpaque:YES];
        [window setBackgroundColor:[NSColor blackColor]];
        [window setReleasedWhenClosed:NO];
        // AppKit only sends hover movement to mouseMoved: when the window opts in.
        [window setAcceptsMouseMovedEvents:YES];

        DoofGameView* view = [[DoofGameView alloc] initWithState:state.get()
                                                           frame:NSMakeRect(0.0, 0.0, NSWidth(frame), NSHeight(frame))];
        [window setContentView:view];
        [window makeFirstResponder:view];

        DoofGameWindowDelegate* delegate = [[DoofGameWindowDelegate alloc] initWithState:state.get()];
        [window setDelegate:delegate];

        updateLayerDrawableSize(view, surface);
        [window makeKeyAndOrderFront:nil];
        [window orderFrontRegardless];
        [app activateIgnoringOtherApps:YES];

        CVReturn displayLinkResult = impl_->displayID != kCGNullDirectDisplay
            ? CVDisplayLinkCreateWithCGDisplay(impl_->displayID, &displayLink)
            : CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);
        if (displayLinkResult != kCVReturnSuccess || displayLink == nullptr) {
            displayLinkResult = CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);
        }
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
        state->displayLink = displayLink;
        CVDisplayLinkSetOutputCallback(displayLink, displayLinkCallback, state.get());

        drainEvents.call();
        state->requestRender();

        [app run];

        state->running.store(false);
        state->stopDisplayLink();
        CVDisplayLinkRelease(displayLink);
        state->displayLink = nullptr;

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
