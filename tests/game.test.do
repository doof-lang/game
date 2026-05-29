import { Assert } from "std/assert"
import { setInterval } from "std/event"
import { approxEqual } from "std/math"
import { Duration } from "std/time"

import {
  Blend,
  BlendMode,
  Atlas,
  Camera,
  CameraKind,
  Clear,
  ClearKind,
  ColorMeshBuilder,
  Color,
  Depth,
  DepthMode,
  GameEventKind,
  GameSurface,
  Key,
  Mat4,
  MouseButton,
  Point,
  Point3,
  Rect,
  RenderPass,
  Texture,
  TextureQuadBatchBuilder,
  RenderPassDescriptor,
  drawColorMesh,
  drawTextureQuadBatch,
  gameEventKindFromCode,
  initGameApp,
  keyCode,
  keyFromCode,
  mouseButtonCode,
  mouseButtonFromCode,
} from "../index"

function compileMeshSmoke(surface: GameSurface, pass: RenderPass): void {
  builder := ColorMeshBuilder.create()
  builder.addTriangle(
    Point3.xyz(-0.5, -0.5, 0.0),
    Point3.xyz(0.5, -0.5, 0.0),
    Point3.xyz(0.0, 0.5, 0.0),
    Color.rgb(0.0, 0.7, 1.0),
  )
  builder.addQuad(
    Point3.xyz(-0.25, -0.25, 0.0),
    Point3.xyz(0.25, -0.25, 0.0),
    Point3.xyz(0.25, 0.25, 0.0),
    Point3.xyz(-0.25, 0.25, 0.0),
    Color.rgb(1.0, 0.3, 0.1),
  )

  built := builder.build(surface)
  case built {
    s: Success -> drawColorMesh(pass, s.value, Mat4.identity())
    f: Failure -> {}
  }
}

function compileTextureQuadBatchSmoke(texture: Texture, surface: GameSurface, pass: RenderPass): void {
  atlas := Atlas {
    texture: texture,
    columns: 14,
    rows: 4,
  }
  builder := TextureQuadBatchBuilder.forAtlas(atlas)
  builder.addAtlasCell(atlas, 0, 0, Rect.xywh(80.0, 90.0, 121.0, 176.0))
  builder.addQuad(
    Rect.xywh(220.0, 90.0, 121.0, 176.0),
    atlas.cellRect(10, 1),
    Color.rgba(1.0, 1.0, 1.0, 0.75),
  )

  built := builder.build(surface)
  case built {
    s: Success -> drawTextureQuadBatch(pass, s.value, Mat4.identity())
    f: Failure -> {}
  }
}

function compileGameAppSmoke(): Result<void, string> {
  app := initGameApp{ title: "Doof Game Smoke" }
  let held = false

  simulationTimer := setInterval{
    interval: Duration.ofMillis(16L),
    handler: (): void => {
      held = app.input.isKeyDown(Key.Space)
      app.requestRender()
    },
  }

  heartbeatTimer := setInterval{
    interval: Duration.ofMillis(250L),
    handler: (): void => {},
  }

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.KeyDown && event.key() == Key.Escape {
      app.stop()
    }
  })

  app.onRender((renderer): void => {
    surface := app.surface
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.colorDepth(Color.black(), 1.0),
        depth: Depth.readWrite(),
        blend: Blend.opaque(),
      },
      (pass): void => {
        passSurface := pass.surface()
        encoderHandle := pass.metalRenderCommandEncoderHandle()
        deviceHandle := pass.metalDeviceHandle()
        blendCode := pass.nativeBlendModeCode()
        hasDepth := pass.hasDepthAttachment()
        projected := pass.camera().project(passSurface, Point3.xyz(10.0, 20.0, 0.0))
        matrixProjected := pass.camera().matrix(passSurface).transformPoint(Point3.xyz(10.0, 20.0, 0.0))
        Assert.isTrue(approxEqual(projected.x, matrixProjected.x))
        Assert.isTrue(approxEqual(projected.y, matrixProjected.y))
        Assert.isTrue(approxEqual(projected.z, matrixProjected.z))
        Assert.isTrue(approxEqual(projected.w, matrixProjected.w))
        compileMeshSmoke(passSurface, pass)
      },
    )
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.none(),
        depth: Depth.readOnly(),
        blend: Blend.alpha(),
      },
      (pass): void => {
        passCamera := pass.camera()
        commandBufferHandle := pass.metalCommandBufferHandle()
      },
    )
  })

  return app.run()
}

export function testKeyCodeRoundTripsCommonKeys(): void {
  Assert.equal(keyFromCode(keyCode(Key.A)), Key.A)
  Assert.equal(keyFromCode(keyCode(Key.Z)), Key.Z)
  Assert.equal(keyFromCode(keyCode(Key.Digit0)), Key.Digit0)
  Assert.equal(keyFromCode(keyCode(Key.Digit9)), Key.Digit9)
  Assert.equal(keyFromCode(keyCode(Key.ArrowLeft)), Key.ArrowLeft)
  Assert.equal(keyFromCode(keyCode(Key.ArrowRight)), Key.ArrowRight)
  Assert.equal(keyFromCode(keyCode(Key.ArrowUp)), Key.ArrowUp)
  Assert.equal(keyFromCode(keyCode(Key.ArrowDown)), Key.ArrowDown)
  Assert.equal(keyFromCode(keyCode(Key.Escape)), Key.Escape)
  Assert.equal(keyFromCode(keyCode(Key.Enter)), Key.Enter)
  Assert.equal(keyFromCode(keyCode(Key.Space)), Key.Space)
  Assert.equal(keyFromCode(keyCode(Key.Backspace)), Key.Backspace)
  Assert.equal(keyFromCode(keyCode(Key.Tab)), Key.Tab)
  Assert.equal(keyFromCode(keyCode(Key.Shift)), Key.Shift)
  Assert.equal(keyFromCode(keyCode(Key.Control)), Key.Control)
  Assert.equal(keyFromCode(keyCode(Key.Option)), Key.Option)
  Assert.equal(keyFromCode(keyCode(Key.Command)), Key.Command)
  Assert.equal(keyFromCode(keyCode(Key.F1)), Key.F1)
  Assert.equal(keyFromCode(keyCode(Key.F12)), Key.F12)
}

export function testUnknownKeyCodeMapsToUnknown(): void {
  Assert.equal(keyCode(Key.Unknown), 0)
  Assert.equal(keyFromCode(-1), Key.Unknown)
  Assert.equal(keyFromCode(999), Key.Unknown)
}

export function testMouseButtonCodeRoundTrips(): void {
  Assert.equal(mouseButtonFromCode(mouseButtonCode(MouseButton.Left)), MouseButton.Left)
  Assert.equal(mouseButtonFromCode(mouseButtonCode(MouseButton.Right)), MouseButton.Right)
  Assert.equal(mouseButtonFromCode(mouseButtonCode(MouseButton.Middle)), MouseButton.Middle)
  Assert.equal(mouseButtonFromCode(mouseButtonCode(MouseButton.Other)), MouseButton.Other)
  Assert.equal(mouseButtonFromCode(999), MouseButton.Other)
}

export function testGameEventKindMapping(): void {
  Assert.equal(gameEventKindFromCode(0), GameEventKind.CloseRequested)
  Assert.equal(gameEventKindFromCode(1), GameEventKind.Resized)
  Assert.equal(gameEventKindFromCode(2), GameEventKind.KeyDown)
  Assert.equal(gameEventKindFromCode(3), GameEventKind.KeyUp)
  Assert.equal(gameEventKindFromCode(4), GameEventKind.MouseDown)
  Assert.equal(gameEventKindFromCode(5), GameEventKind.MouseUp)
  Assert.equal(gameEventKindFromCode(6), GameEventKind.MouseMove)
  Assert.equal(gameEventKindFromCode(7), GameEventKind.MouseWheel)
}

export function testRenderPassDescriptorDefaults(): void {
  desc := RenderPassDescriptor {}

  Assert.equal(desc.camera.kind, CameraKind.Screen)
  Assert.equal(desc.clear.kind, ClearKind.None)
  Assert.equal(desc.clear.depthValue, 1.0)
  Assert.equal(desc.depth.mode, DepthMode.Disabled)
  Assert.equal(desc.blend.mode, BlendMode.Opaque)
}

export function testCameraHelpersBuildExpectedKinds(): void {
  Assert.equal(Camera.screen().kind, CameraKind.Screen)
  Assert.equal(Camera.identity().kind, CameraKind.Identity)
  Assert.equal(Camera.orthographic(-1.0, 1.0, -1.0, 1.0).kind, CameraKind.Orthographic)
  Assert.equal(Camera.perspective(1.0, 1.0, 0.1, 100.0).kind, CameraKind.Perspective)
}

export function testMat4IdentityTranslationAndScale(): void {
  point := Point3.xyz(1.0, 2.0, 3.0)
  moved := Mat4.translation(4.0, 5.0, 6.0).transformPoint(point)
  scaled := Mat4.scale(2.0, 3.0, 4.0).transformPoint(point)
  combined := Mat4.translation(4.0, 5.0, 6.0).multiply(Mat4.scale(2.0, 3.0, 4.0)).transformPoint(point)

  Assert.equal(Mat4.identity().transformPoint(point).x, 1.0)
  Assert.equal(moved.x, 5.0)
  Assert.equal(moved.y, 7.0)
  Assert.equal(moved.z, 9.0)
  Assert.equal(scaled.x, 2.0)
  Assert.equal(scaled.y, 6.0)
  Assert.equal(scaled.z, 12.0)
  Assert.equal(combined.x, 6.0)
  Assert.equal(combined.y, 11.0)
  Assert.equal(combined.z, 18.0)
  Assert.equal(combined.w, 1.0)
}

export function testMat4Rotations(): void {
  quarterTurn := 1.5707963267948966

  rotatedX := Mat4.rotationX(quarterTurn).transformPoint(Point3.xyz(0.0, 1.0, 0.0))
  rotatedY := Mat4.rotationY(quarterTurn).transformPoint(Point3.xyz(0.0, 0.0, 1.0))
  rotatedZ := Mat4.rotationZ(quarterTurn).transformPoint(Point3.xyz(1.0, 0.0, 0.0))

  Assert.isTrue(approxEqual(rotatedX.y, 0.0))
  Assert.isTrue(approxEqual(rotatedX.z, 1.0))
  Assert.isTrue(approxEqual(rotatedY.x, 1.0))
  Assert.isTrue(approxEqual(rotatedY.z, 0.0))
  Assert.isTrue(approxEqual(rotatedZ.x, 0.0))
  Assert.isTrue(approxEqual(rotatedZ.y, 1.0))
}

export function testMat4OrthographicMapsBoundsToClipSpace(): void {
  matrix := Mat4.orthographic(10.0, 30.0, 20.0, 60.0, -1.0, 1.0)
  bottomLeft := matrix.transformPoint(Point3.xyz(10.0, 20.0, 0.0))
  topRight := matrix.transformPoint(Point3.xyz(30.0, 60.0, 0.0))

  Assert.isTrue(approxEqual(bottomLeft.x, -1.0))
  Assert.isTrue(approxEqual(bottomLeft.y, -1.0))
  Assert.isTrue(approxEqual(topRight.x, 1.0))
  Assert.isTrue(approxEqual(topRight.y, 1.0))
  Assert.equal(bottomLeft.w, 1.0)
}

export function testMat4PerspectiveProducesPerspectiveDivideW(): void {
  matrix := Mat4.perspective(1.5707963267948966, 1.0, 1.0, 10.0)
  projected := matrix.transformPoint(Point3.xyz(0.0, 0.0, -5.0))

  Assert.isTrue(approxEqual(projected.x, 0.0))
  Assert.isTrue(approxEqual(projected.y, 0.0))
  Assert.equal(projected.w, 5.0)
}

export function testClearHelpers(): void {
  color := Color.rgba(0.1, 0.2, 0.3, 0.4)
  clearColor := Clear.color(color)
  clearDepth := Clear.depth(0.5)
  clearColorDepth := Clear.colorDepth(color, 0.25)

  Assert.equal(clearColor.kind, ClearKind.Color)
  Assert.equal(clearColor.colorValue.r, 0.1)
  Assert.equal(clearColor.colorValue.g, 0.2)
  Assert.equal(clearColor.colorValue.b, 0.3)
  Assert.equal(clearColor.colorValue.a, 0.4)
  Assert.equal(clearDepth.kind, ClearKind.Depth)
  Assert.equal(clearDepth.depthValue, 0.5)
  Assert.equal(clearColorDepth.kind, ClearKind.ColorDepth)
  Assert.equal(clearColorDepth.depthValue, 0.25)
}

export function testDepthAndBlendHelpers(): void {
  Assert.equal(Depth.disabled().mode, DepthMode.Disabled)
  Assert.equal(Depth.readOnly().mode, DepthMode.ReadOnly)
  Assert.equal(Depth.readWrite().mode, DepthMode.ReadWrite)
  Assert.equal(Blend.opaque().mode, BlendMode.Opaque)
  Assert.equal(Blend.alpha().mode, BlendMode.Alpha)
}

export function testPointRectAndColorHelpers(): void {
  point := Point.xy(3.0, 4.0)
  rect := Rect.xywh(10.0, 20.0, 30.0, 40.0)
  white := Color.white()

  Assert.equal(point.x, 3.0)
  Assert.equal(point.y, 4.0)
  Assert.equal(rect.x, 10.0)
  Assert.equal(rect.y, 20.0)
  Assert.equal(rect.width, 30.0)
  Assert.equal(rect.height, 40.0)
  Assert.equal(white.r, 1.0)
  Assert.equal(white.g, 1.0)
  Assert.equal(white.b, 1.0)
  Assert.equal(white.a, 1.0)
}

function compileAtlasCellSmoke(texture: Texture): Rect {
  atlas := Atlas {
    texture: texture,
    columns: 14,
    rows: 4,
  }

  return atlas.cellRect(13, 2)
}
