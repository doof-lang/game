#pragma once

#include "doof_runtime.hpp"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace doof_game {

class NativeGameSurface {
public:
    NativeGameSurface(void* device, void* commandQueue, void* layer);
    ~NativeGameSurface();

    int32_t pixelWidth() const;
    int32_t pixelHeight() const;
    double scale() const;
    int64_t metalDeviceHandle() const;
    int64_t metalCommandQueueHandle() const;
    int64_t metalLayerHandle() const;

private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};

class NativeTexture {
public:
    static doof::Result<std::shared_ptr<NativeTexture>, std::string> load(
        const std::string& path,
        int64_t metalDeviceHandle
    );
    static doof::Result<std::shared_ptr<NativeTexture>, std::string> createRgba(
        const std::shared_ptr<std::vector<uint8_t>>& data,
        int32_t pixelWidth,
        int32_t pixelHeight,
        int32_t alphaMode,
        int64_t metalDeviceHandle
    );
    static doof::Result<std::shared_ptr<NativeTexture>, std::string> createAlpha4(
        const std::shared_ptr<std::vector<uint8_t>>& data,
        int32_t pixelWidth,
        int32_t pixelHeight,
        int64_t metalDeviceHandle
    );
    NativeTexture(void* texture, int32_t pixelWidth, int32_t pixelHeight);
    ~NativeTexture();

    int32_t pixelWidth() const;
    int32_t pixelHeight() const;
    int64_t metalTextureHandle() const;

private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};

class NativeRenderPass {
public:
    ~NativeRenderPass();

    void end();
    int64_t metalRenderCommandEncoderHandle() const;
    int64_t metalCommandBufferHandle() const;
    int64_t metalDeviceHandle() const;
    bool hasDepthAttachment() const;

private:
    friend class NativeRenderFrame;

    NativeRenderPass(void* encoder, void* commandBuffer, void* device, int32_t blendMode, bool hasDepth);

    struct Impl;
    std::shared_ptr<Impl> impl_;
};

class NativeRenderFrame {
public:
    static std::shared_ptr<NativeRenderFrame> create(std::shared_ptr<NativeGameSurface> surface);
    ~NativeRenderFrame();

    std::shared_ptr<NativeRenderPass> beginPass(
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
    );
    void commit();

private:
    explicit NativeRenderFrame(std::shared_ptr<NativeGameSurface> surface);

    struct Impl;
    std::shared_ptr<Impl> impl_;
};

class NativeGameEvent {
public:
    NativeGameEvent(
        int32_t kindCode,
        int32_t keyCode = 0,
        int32_t mouseButtonCode = 0,
        double x = 0.0,
        double y = 0.0,
        double deltaX = 0.0,
        double deltaY = 0.0,
        double panDeltaX = 0.0,
        double panDeltaY = 0.0,
        double scrollDeltaX = 0.0,
        double scrollDeltaY = 0.0,
        int32_t pixelWidth = 0,
        int32_t pixelHeight = 0,
        double magnificationDelta = 0.0,
        int32_t controllerSlotCode = 0,
        const std::string& controllerName = ""
    );

    int32_t kindCode() const;
    int32_t keyCode() const;
    int32_t mouseButtonCode() const;
    int32_t controllerSlotCode() const;
    std::string controllerName() const;
    double x() const;
    double y() const;
    double deltaX() const;
    double deltaY() const;
    double panDeltaX() const;
    double panDeltaY() const;
    double scrollDeltaX() const;
    double scrollDeltaY() const;
    int32_t pixelWidth() const;
    int32_t pixelHeight() const;
    double magnificationDelta() const;

private:
    int32_t kindCode_;
    int32_t keyCode_;
    int32_t mouseButtonCode_;
    int32_t controllerSlotCode_;
    std::string controllerName_;
    double x_;
    double y_;
    double deltaX_;
    double deltaY_;
    double panDeltaX_;
    double panDeltaY_;
    double scrollDeltaX_;
    double scrollDeltaY_;
    int32_t pixelWidth_;
    int32_t pixelHeight_;
    double magnificationDelta_;
};

class NativeInputState {
public:
    NativeInputState();
    ~NativeInputState();

    bool isKeyDownCode(int32_t key) const;
    bool isMouseButtonDownCode(int32_t button) const;
    bool isControllerConnectedCode(int32_t slot) const;
    std::string controllerNameCode(int32_t slot) const;
    bool isControllerButtonDownCode(int32_t slot, int32_t button) const;
    double controllerAxisCode(int32_t slot, int32_t axis) const;
    double mouseX() const;
    double mouseY() const;
    double mouseDeltaX() const;
    double mouseDeltaY() const;
    double panDeltaX() const;
    double panDeltaY() const;
    double scrollDeltaX() const;
    double scrollDeltaY() const;
    double magnificationDelta() const;
    void resetFrameDeltas();
    void setKeyDownCode(int32_t key, bool isDown);
    void setMouseButtonDownCode(int32_t button, bool isDown);
    void setControllerConnectedCode(int32_t slot, const std::string& name, bool isConnected);
    void setControllerButtonDownCode(int32_t slot, int32_t button, bool isDown);
    void setControllerAxisCode(int32_t slot, int32_t axis, double value);
    void setMousePosition(double x, double y);
    void addMouseDelta(double x, double y);
    void addPanDelta(double x, double y);
    void addScrollDelta(double x, double y);
    void addMagnificationDelta(double delta);

private:
    friend doof::Result<void, std::string> runNativeGameApp(
        const std::string& title,
        doof::callback<void(std::shared_ptr<NativeGameEvent>, std::shared_ptr<NativeInputState>)> onEvent,
        doof::callback<void(std::shared_ptr<NativeGameSurface>, std::shared_ptr<NativeInputState>)> onRender,
        doof::callback<int32_t()> drainEvents
    );

    struct Impl;
    std::shared_ptr<Impl> impl_;
};

class NativeGameApp {
public:
    static std::shared_ptr<NativeGameApp> create(const std::string& title);
    ~NativeGameApp();

    std::shared_ptr<NativeGameSurface> surface() const;
    std::shared_ptr<NativeInputState> input() const;
    double fps() const;
    doof::Result<void, std::string> run(
        doof::callback<void(std::shared_ptr<NativeGameEvent>, std::shared_ptr<NativeInputState>)> onEvent,
        doof::callback<void(std::shared_ptr<NativeGameSurface>, std::shared_ptr<NativeInputState>)> onRender,
        doof::callback<int32_t()> drainEvents
    );

private:
    explicit NativeGameApp(const std::string& title);

    struct Impl;
    std::shared_ptr<Impl> impl_;
};

doof::Result<void, std::string> runNativeGameApp(
    const std::string& title,
    doof::callback<void(std::shared_ptr<NativeGameEvent>, std::shared_ptr<NativeInputState>)> onEvent,
    doof::callback<void(std::shared_ptr<NativeGameSurface>, std::shared_ptr<NativeInputState>)> onRender,
    doof::callback<int32_t()> drainEvents
);

void requestGameAppWake();
void requestGameAppRender();
void requestGameAppStop();
void beginGameAppPanGesture(double x, double y);
void updateGameAppPanGesture(double x, double y);
void endGameAppPanGesture();
void cancelGameAppPanGesture();

}  // namespace doof_game
