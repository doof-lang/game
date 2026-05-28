export import class NativeGameSurface from "native_game.hpp" as doof_game::NativeGameSurface {
  pixelWidth(): int
  pixelHeight(): int
  scale(): double
  metalDeviceHandle(): long
  metalCommandQueueHandle(): long
  metalLayerHandle(): long
}

export import class NativeGameEvent from "native_game.hpp" as doof_game::NativeGameEvent {
  kindCode(): int
  keyCode(): int
  mouseButtonCode(): int
  x(): double
  y(): double
  deltaX(): double
  deltaY(): double
  wheelDeltaX(): double
  wheelDeltaY(): double
  pixelWidth(): int
  pixelHeight(): int
}

export import class NativeInputState from "native_game.hpp" as doof_game::NativeInputState {
  isKeyDownCode(key: int): bool
  isMouseButtonDownCode(button: int): bool
  mouseX(): double
  mouseY(): double
  mouseDeltaX(): double
  mouseDeltaY(): double
  wheelDeltaX(): double
  wheelDeltaY(): double
}

export import class NativeGameApp from "native_game.hpp" as doof_game::NativeGameApp {
  static create(title: string): NativeGameApp
  surface(): NativeGameSurface
  input(): NativeInputState
  fps(): double
  run(
    onEvent: (event: NativeGameEvent, input: NativeInputState): void,
    onRender: (surface: NativeGameSurface, input: NativeInputState): void,
    drainEvents: (): int,
  ): Result<void, string>
}

export import class NativeTexture from "native_game.hpp" as doof_game::NativeTexture {
  static load(path: string, metalDeviceHandle: long): Result<NativeTexture, string>
  pixelWidth(): int
  pixelHeight(): int
  metalTextureHandle(): long
}

export import class NativeRenderFrame from "native_game.hpp" as doof_game::NativeRenderFrame {
  static create(surface: NativeGameSurface): NativeRenderFrame
  beginPass(
    clearKind: int,
    clearRed: double,
    clearGreen: double,
    clearBlue: double,
    clearAlpha: double,
    clearDepth: double,
    depthMode: int,
    blendMode: int,
  ): NativeRenderPass
  commit(): void
}

export import class NativeRenderPass from "native_game.hpp" as doof_game::NativeRenderPass {
  end(): void
  drawTriangle(
    ax: double,
    ay: double,
    az: double,
    aw: double,
    bx: double,
    by: double,
    bz: double,
    bw: double,
    cx: double,
    cy: double,
    cz: double,
    cw: double,
    red: double,
    green: double,
    blue: double,
    alpha: double,
  ): void
  drawTextureQuad(
    texture: NativeTexture,
    ax: double,
    ay: double,
    az: double,
    aw: double,
    bx: double,
    by: double,
    bz: double,
    bw: double,
    cx: double,
    cy: double,
    cz: double,
    cw: double,
    dx: double,
    dy: double,
    dz: double,
    dw: double,
    sourceX: double,
    sourceY: double,
    sourceWidth: double,
    sourceHeight: double,
    red: double,
    green: double,
    blue: double,
    alpha: double,
  ): void
  metalRenderCommandEncoderHandle(): long
  metalCommandBufferHandle(): long
}

export import function runNativeGameApp(
  title: string,
  onEvent: (event: NativeGameEvent, input: NativeInputState): void,
  onRender: (surface: NativeGameSurface, input: NativeInputState): void,
  drainEvents: (): int,
): Result<void, string> from "native_game.hpp" as doof_game::runNativeGameApp

export import function requestGameAppWake(): void from "native_game.hpp" as doof_game::requestGameAppWake
export import function requestGameAppRender(): void from "native_game.hpp" as doof_game::requestGameAppRender
export import function requestGameAppStop(): void from "native_game.hpp" as doof_game::requestGameAppStop
