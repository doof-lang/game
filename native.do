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
  metalRenderCommandEncoderHandle(): long
  metalCommandBufferHandle(): long
  metalDeviceHandle(): long
  hasDepthAttachment(): bool
}

export import class NativeSimpleMeshBuilder from "native_mesh.hpp" as doof_game::NativeSimpleMeshBuilder {
  static create(): NativeSimpleMeshBuilder
  addVertex(
    x: double,
    y: double,
    z: double,
    red: double,
    green: double,
    blue: double,
    alpha: double,
    u: double,
    v: double,
    normalX: double,
    normalY: double,
    normalZ: double,
  ): int
  addTriangle(a: int, b: int, c: int): NativeSimpleMeshBuilder
  build(metalDeviceHandle: long): Result<NativeSimpleMesh, string>
}

export import class NativeSimpleMesh from "native_mesh.hpp" as doof_game::NativeSimpleMesh {
  vertexCount(): int
  indexCount(): int
}

export import class NativeTextureQuadBatchBuilder from "native_sprite.hpp" as doof_game::NativeTextureQuadBatchBuilder {
  static create(): NativeTextureQuadBatchBuilder
  addQuad(
    x: double,
    y: double,
    width: double,
    height: double,
    u0: double,
    v0: double,
    u1: double,
    v1: double,
    red: double,
    green: double,
    blue: double,
    alpha: double,
  ): NativeTextureQuadBatchBuilder
  build(metalDeviceHandle: long): Result<NativeTextureQuadBatch, string>
}

export import class NativeTextureQuadBatch from "native_sprite.hpp" as doof_game::NativeTextureQuadBatch {
  quadCount(): int
}

export import function drawNativeSimpleMesh(
  mesh: NativeSimpleMesh,
  metalRenderCommandEncoderHandle: long,
  metalDeviceHandle: long,
  blendMode: int,
  hasDepthAttachment: bool,
  m00: double,
  m01: double,
  m02: double,
  m03: double,
  m10: double,
  m11: double,
  m12: double,
  m13: double,
  m20: double,
  m21: double,
  m22: double,
  m23: double,
  m30: double,
  m31: double,
  m32: double,
  m33: double,
): void from "native_mesh.hpp" as doof_game::drawNativeSimpleMesh

export import function drawNativeTexturedSimpleMesh(
  mesh: NativeSimpleMesh,
  metalTextureHandle: long,
  metalRenderCommandEncoderHandle: long,
  metalDeviceHandle: long,
  blendMode: int,
  hasDepthAttachment: bool,
  m00: double,
  m01: double,
  m02: double,
  m03: double,
  m10: double,
  m11: double,
  m12: double,
  m13: double,
  m20: double,
  m21: double,
  m22: double,
  m23: double,
  m30: double,
  m31: double,
  m32: double,
  m33: double,
): void from "native_mesh.hpp" as doof_game::drawNativeTexturedSimpleMesh

export import function drawNativeTextureQuadBatch(
  batch: NativeTextureQuadBatch,
  metalTextureHandle: long,
  metalRenderCommandEncoderHandle: long,
  metalDeviceHandle: long,
  blendMode: int,
  hasDepthAttachment: bool,
  m00: double,
  m01: double,
  m02: double,
  m03: double,
  m10: double,
  m11: double,
  m12: double,
  m13: double,
  m20: double,
  m21: double,
  m22: double,
  m23: double,
  m30: double,
  m31: double,
  m32: double,
  m33: double,
): void from "native_sprite.hpp" as doof_game::drawNativeTextureQuadBatch

export import function runNativeGameApp(
  title: string,
  onEvent: (event: NativeGameEvent, input: NativeInputState): void,
  onRender: (surface: NativeGameSurface, input: NativeInputState): void,
  drainEvents: (): int,
): Result<void, string> from "native_game.hpp" as doof_game::runNativeGameApp

export import function requestGameAppWake(): void from "native_game.hpp" as doof_game::requestGameAppWake
export import function requestGameAppRender(): void from "native_game.hpp" as doof_game::requestGameAppRender
export import function requestGameAppStop(): void from "native_game.hpp" as doof_game::requestGameAppStop
