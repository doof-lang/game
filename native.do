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
    windingMode: int,
    cullMode: int,
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

export import class NativeSimpleModelBatch from "native_mesh.hpp" as doof_game::NativeSimpleModelBatch {
  static create(metalDeviceHandle: long, capacity: int): Result<NativeSimpleModelBatch, string>
  capacity(): int
  count(): int
  setCount(count: int): void
  setInstance(
    slot: int,
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
    red: double,
    green: double,
    blue: double,
    alpha: double,
    uvOffsetX: double,
    uvOffsetY: double,
    uvScaleX: double,
    uvScaleY: double,
  ): void
}

export import class NativeSpaceDustBuilder from "native_mesh.hpp" as doof_game::NativeSpaceDustBuilder {
  static create(): NativeSpaceDustBuilder
  addParticle(x: double, y: double, z: double, brightness: double): NativeSpaceDustBuilder
  build(metalDeviceHandle: long): Result<NativeSpaceDust, string>
}

export import class NativeSpaceDust from "native_mesh.hpp" as doof_game::NativeSpaceDust {
  particleCount(): int
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

export import function drawNativeSimpleModelBatch(
  mesh: NativeSimpleMesh,
  batch: NativeSimpleModelBatch,
  metalTextureHandle: long,
  textured: bool,
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
): void from "native_mesh.hpp" as doof_game::drawNativeSimpleModelBatch

export import function drawNativeEquirectangularSkyMap(
  metalTextureHandle: long,
  metalRenderCommandEncoderHandle: long,
  metalDeviceHandle: long,
  hasDepthAttachment: bool,
  pixelWidth: int,
  pixelHeight: int,
  fovYRadians: double,
  exposure: double,
  rotationM00: double,
  rotationM01: double,
  rotationM02: double,
  rotationM10: double,
  rotationM11: double,
  rotationM12: double,
  rotationM20: double,
  rotationM21: double,
  rotationM22: double,
): void from "native_mesh.hpp" as doof_game::drawNativeEquirectangularSkyMap

export import function drawNativeSpaceDust(
  dust: NativeSpaceDust,
  metalRenderCommandEncoderHandle: long,
  metalDeviceHandle: long,
  hasDepthAttachment: bool,
  pixelWidth: int,
  pixelHeight: int,
  cameraX: double,
  cameraY: double,
  cameraZ: double,
  fieldSize: double,
  particleSize: double,
  fadeStart: double,
  fadeEnd: double,
  opacity: double,
  red: double,
  green: double,
  blue: double,
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
): void from "native_mesh.hpp" as doof_game::drawNativeSpaceDust

export import function runNativeGameApp(
  title: string,
  onEvent: (event: NativeGameEvent, input: NativeInputState): void,
  onRender: (surface: NativeGameSurface, input: NativeInputState): void,
  drainEvents: (): int,
): Result<void, string> from "native_game.hpp" as doof_game::runNativeGameApp

export import function requestGameAppWake(): void from "native_game.hpp" as doof_game::requestGameAppWake
export import function requestGameAppRender(): void from "native_game.hpp" as doof_game::requestGameAppRender
export import function requestGameAppStop(): void from "native_game.hpp" as doof_game::requestGameAppStop
