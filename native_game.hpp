#pragma once

#include "doof_runtime.hpp"

#include <cstdint>
#include <memory>
#include <string>

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
        int32_t blendMode
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
        double wheelDeltaX = 0.0,
        double wheelDeltaY = 0.0,
        int32_t pixelWidth = 0,
        int32_t pixelHeight = 0
    );

    int32_t kindCode() const;
    int32_t keyCode() const;
    int32_t mouseButtonCode() const;
    double x() const;
    double y() const;
    double deltaX() const;
    double deltaY() const;
    double wheelDeltaX() const;
    double wheelDeltaY() const;
    int32_t pixelWidth() const;
    int32_t pixelHeight() const;

private:
    int32_t kindCode_;
    int32_t keyCode_;
    int32_t mouseButtonCode_;
    double x_;
    double y_;
    double deltaX_;
    double deltaY_;
    double wheelDeltaX_;
    double wheelDeltaY_;
    int32_t pixelWidth_;
    int32_t pixelHeight_;
};

class NativeInputState {
public:
    NativeInputState();
    ~NativeInputState();

    bool isKeyDownCode(int32_t key) const;
    bool isMouseButtonDownCode(int32_t button) const;
    double mouseX() const;
    double mouseY() const;
    double mouseDeltaX() const;
    double mouseDeltaY() const;
    double wheelDeltaX() const;
    double wheelDeltaY() const;
    void resetFrameDeltas();
    void setKeyDownCode(int32_t key, bool isDown);
    void setMouseButtonDownCode(int32_t button, bool isDown);
    void setMousePosition(double x, double y);
    void addMouseDelta(double x, double y);
    void addWheelDelta(double x, double y);

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

}  // namespace doof_game
