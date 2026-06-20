import { Assert } from "std/assert"
import { setInterval } from "std/event"
import { Image, PixelBytes } from "std/image"
import { approxEqual } from "std/math"
import { Duration } from "std/time"

import {
  Blend,
  BlendMode,
  Atlas,
  BitmapFont,
  Camera,
  CameraKind,
  Clear,
  ClearKind,
  Color,
  ControllerAxis,
  ControllerButton,
  ControllerSlot,
  ControllerStick,
  CullMode,
  Depth,
  DepthMode,
  GameApp,
  GameEventKind,
  GameSurface,
  Key,
  Mat4,
  Mat3,
  MouseButton,
  Point,
  Point3,
  Rect,
  RenderPass,
  Rotation,
  SkyMap,
  SimpleModel,
  SimpleModelBatch,
  SimpleMeshBuilder,
  Texture,
  Transform,
  UiLayer,
  Vec2,
  Vec3,
  WindingMode,
  RenderPassDescriptor,
  createSphereMeshSpec,
  drawSimpleModelBatch,
  drawSimpleModel,
  drawSimpleMesh,
  drawEquirectangularSkyMap,
  drawTexturedSimpleMesh,
  gameEventKindFromCode,
  initGameApp,
  keyCode,
  keyFromCode,
  mouseButtonCode,
  mouseButtonFromCode,
  controllerAxisCode,
  controllerAxisFromCode,
  controllerButtonCode,
  controllerButtonFromCode,
  controllerSlotCode,
  controllerSlotFromCode,
} from "../index"

function assertApprox(actual: double, expected: double, message: string | null = null): void {
  Assert.isTrue(approxEqual(actual, expected), message)
}

function assertVec3Approx(actual: Vec3, expected: Vec3, message: string | null = null): void {
  assertApprox(actual.x, expected.x, message)
  assertApprox(actual.y, expected.y, message)
  assertApprox(actual.z, expected.z, message)
}

function assertPoint3Approx(actual: Point3, expected: Point3): void {
  assertApprox(actual.x, expected.x)
  assertApprox(actual.y, expected.y)
  assertApprox(actual.z, expected.z)
}

function verifyGameAppPanGestureApi(app: GameApp): void {
  app.beginPanGesture(10.0, 20.0)
  app.updatePanGesture(12.0, 24.0)
  app.endPanGesture()
  app.cancelPanInertia()
  app.cancelPanGesture()
}

function verifyGameAppControllerApi(app: GameApp): void {
  connected := app.input.isControllerConnected(ControllerSlot.One)
  queryConnected := app.input.controllers().connected(ControllerSlot.One)
  name := app.input.controllers().name(ControllerSlot.One)
  south := app.controllerButton(ControllerSlot.One, ControllerButton.South)
  leftX := app.controllerAxis(ControllerSlot.One, ControllerAxis.LeftX).withDeadzone(0.15)
  leftStick := app.controllerStick(ControllerSlot.One, ControllerStick.Left).withDeadzone(0.2).invertedY()

  connected
  queryConnected
  name
  south.pressed()
  leftX.value()
  leftStick.x()
}

function subtractPoint3(a: Point3, b: Point3): Point3 {
  return Point3(a.x - b.x, a.y - b.y, a.z - b.z)
}

function crossPoint3(a: Point3, b: Point3): Point3 {
  return Point3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x,
  )
}

function compileMeshSmoke(surface: GameSurface, pass: RenderPass): void {
  builder := SimpleMeshBuilder.create()
  a := builder.vertex{
    position: Point3(-0.5, -0.5, 0.0),
    color: Color(0.0, 0.7, 1.0),
  }
  b := builder.vertex{
    position: Point3(0.5, -0.5, 0.0),
    color: Color(0.0, 0.7, 1.0),
  }
  c := builder.vertex{
    position: Point3(0.0, 0.5, 0.0),
    color: Color(0.0, 0.7, 1.0),
  }
  builder.triangle(a, b, c)
  builder.quad{
    a: Point3(-0.25, -0.25, 0.0),
    b: Point3(0.25, -0.25, 0.0),
    c: Point3(0.25, 0.25, 0.0),
    d: Point3(-0.25, 0.25, 0.0),
    color: Color(1.0, 0.3, 0.1),
  }

  mesh := builder.build(surface)
  drawSimpleMesh(pass, mesh, Mat4.identity)

  model := SimpleModel(mesh)
  model
    .moveWorldBy(Vec3.xyz(1.0, 2.0, 3.0))
    .rotateLocalY(45.0)
    .scaleBy(0.5)
  drawSimpleModel(pass, model)
}

function compileTexturedSimpleMeshSmoke(texture: Texture, surface: GameSurface, pass: RenderPass): void {
  builder := SimpleMeshBuilder.create()
  builder.quad{
    a: Point3(-0.5, -0.5, 0.0),
    b: Point3(0.5, -0.5, 0.0),
    c: Point3(0.5, 0.5, 0.0),
    d: Point3(-0.5, 0.5, 0.0),
    color: Color.white,
    uvA: Point(0.0, 1.0),
    uvB: Point(1.0, 1.0),
    uvC: Point(1.0, 0.0),
    uvD: Point(0.0, 0.0),
  }

  mesh := builder.build(surface)
  drawTexturedSimpleMesh(pass, mesh, texture, Mat4.identity)
  drawSimpleModel(pass, SimpleModel(mesh, texture))
}

function compileUiLayerSmoke(font: BitmapFont, texture: Texture, surface: GameSurface, pass: RenderPass): void {
  ui := UiLayer(surface)
  ui.addPanel(Rect(16.0, 16.0, 240.0, 124.0), {})
  ui.addLabel("Score 1200", Rect(24.0, 24.0, 220.0, 40.0), {})
  ui.addButton("Start", Rect(24.0, 76.0, 160.0, 44.0), { font }, (): void => {})
  ui.draw(pass)
}

function compileSkyMapSmoke(texture: Texture, pass: RenderPass): void {
  skyMap := SkyMap { texture: texture }
  drawEquirectangularSkyMap(pass, skyMap, 1.0471975512, 1.0)
}

function compileSimpleModelBatchSmoke(texture: Texture, surface: GameSurface, pass: RenderPass): void {
  builder := SimpleMeshBuilder.create()
  builder.quad{
    a: Point3(0.0, 0.0, 0.0),
    b: Point3(121.0, 0.0, 0.0),
    c: Point3(121.0, 176.0, 0.0),
    d: Point3(0.0, 176.0, 0.0),
    color: Color.white,
    uvA: Point(0.0, 0.0),
    uvB: Point(1.0, 0.0),
    uvC: Point(1.0, 1.0),
    uvD: Point(0.0, 1.0),
  }
  mesh := builder.build(surface)
  batch := SimpleModelBatch {
    surface: surface,
    mesh: mesh,
    texture: texture,
    capacity: 4,
  }
  first := batch.add{
    transform: Transform.identity().withPosition(Point3(80.0, 90.0, 0.0)),
    whiteBlend: 0.4,
    uvOffset: Vec2.zero,
    uvScale: Vec2.xy(1.0 / 14.0, 1.0 / 4.0),
  }
  second := batch.add{
    transform: Transform.identity().withPosition(Point3(220.0, 90.0, 0.0)),
    tint: Color(1.0, 1.0, 1.0, 0.75),
    uvOffset: Vec2.xy(10.0 / 14.0, 1.0 / 4.0),
    uvScale: Vec2.xy(1.0 / 14.0, 1.0 / 4.0),
  }
  first.moveWorldBy(Vec3.xyz(1.0, 0.0, 0.0))
  first.setWhiteBlend(0.6)
  Assert.equal(first.whiteBlend(), 0.6)
  second.remove()

  Assert.equal(batch.count(), 1)
  Assert.isFalse(second.isLive())
  drawSimpleModelBatch(pass, batch)
}

function compileGameAppSmoke(): Result<void, string> {
  app := initGameApp{ title: "Doof Game Smoke" }
  inMemoryPixels := PixelBytes(1, 1, [255, 255, 255, 255])
  inMemoryImage := try! Image.fromPixelBytes(inMemoryPixels)
  inMemoryTexture := try! app.createTexture(inMemoryImage)
  pixelTexture := try! app.createTextureFromPixels(inMemoryPixels)
  Assert.equal(inMemoryTexture.pixelWidth(), 1)
  Assert.equal(inMemoryTexture.pixelHeight(), 1)
  Assert.equal(pixelTexture.pixelWidth(), 1)
  let held = false

  verifyGameAppPanGestureApi(app)
  verifyGameAppControllerApi(app)

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

  app.key(Key.Escape).onPressed((): void => app.stop())

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }
  })

  app.onRender((renderer): void => {
    rendererTexture := try! renderer.createTexture(inMemoryImage)
    rendererPixelTexture := try! renderer.createTextureFromPixels(inMemoryPixels)
    Assert.equal(rendererTexture.pixelWidth(), 1)
    Assert.equal(rendererPixelTexture.pixelWidth(), 1)
    surface := app.surface
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.colorDepth(Color.black, 1.0),
        depth: Depth.readWrite(),
        blend: Blend.opaque(),
      },
      (pass): void => {
        passSurface := pass.surface()
        surfaceWidth := passSurface.width()
        surfaceHeight := passSurface.height()
        Assert.isTrue(surfaceWidth > 0.0)
        Assert.isTrue(surfaceHeight > 0.0)
        encoderHandle := pass.metalRenderCommandEncoderHandle()
        deviceHandle := pass.metalDeviceHandle()
        blendCode := pass.nativeBlendModeCode()
        hasDepth := pass.hasDepthAttachment()
        topLeft := pass.camera().project(passSurface, Point3(0.0, 0.0, 0.0))
        bottomRight := pass.camera().project(passSurface, Point3(surfaceWidth, surfaceHeight, 0.0))
        assertApprox(topLeft.x, -1.0)
        assertApprox(topLeft.y, 1.0)
        assertApprox(bottomRight.x, 1.0)
        assertApprox(bottomRight.y, -1.0)
        projected := pass.camera().project(passSurface, Point3(10.0, 20.0, 0.0))
        matrixProjected := pass.camera().matrix(passSurface).transformPoint(Point3(10.0, 20.0, 0.0))
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

export function testControllerCodeRoundTrips(): void {
  Assert.equal(controllerSlotFromCode(controllerSlotCode(ControllerSlot.One)), ControllerSlot.One)
  Assert.equal(controllerSlotFromCode(controllerSlotCode(ControllerSlot.Four)), ControllerSlot.Four)
  Assert.equal(controllerButtonFromCode(controllerButtonCode(ControllerButton.South)), ControllerButton.South)
  Assert.equal(controllerButtonFromCode(controllerButtonCode(ControllerButton.North)), ControllerButton.North)
  Assert.equal(controllerButtonFromCode(controllerButtonCode(ControllerButton.DPadRight)), ControllerButton.DPadRight)
  Assert.equal(controllerAxisFromCode(controllerAxisCode(ControllerAxis.LeftX)), ControllerAxis.LeftX)
  Assert.equal(controllerAxisFromCode(controllerAxisCode(ControllerAxis.RightTrigger)), ControllerAxis.RightTrigger)
}

export function testUnknownControllerCodesMapToSafeDefaults(): void {
  Assert.equal(controllerSlotFromCode(999), ControllerSlot.One)
  Assert.equal(controllerButtonFromCode(999), ControllerButton.South)
  Assert.equal(controllerAxisFromCode(999), ControllerAxis.LeftX)
}

export function testGameEventKindMapping(): void {
  Assert.equal(gameEventKindFromCode(0), GameEventKind.CloseRequested)
  Assert.equal(gameEventKindFromCode(1), GameEventKind.Resized)
  Assert.equal(gameEventKindFromCode(2), GameEventKind.KeyDown)
  Assert.equal(gameEventKindFromCode(3), GameEventKind.KeyUp)
  Assert.equal(gameEventKindFromCode(4), GameEventKind.MouseDown)
  Assert.equal(gameEventKindFromCode(5), GameEventKind.MouseUp)
  Assert.equal(gameEventKindFromCode(6), GameEventKind.MouseMove)
  Assert.equal(gameEventKindFromCode(7), GameEventKind.Scroll)
  Assert.equal(gameEventKindFromCode(8), GameEventKind.DoubleTap)
  Assert.equal(gameEventKindFromCode(9), GameEventKind.Magnify)
  Assert.equal(gameEventKindFromCode(10), GameEventKind.Pan)
  Assert.equal(gameEventKindFromCode(11), GameEventKind.ControllerConnected)
  Assert.equal(gameEventKindFromCode(12), GameEventKind.ControllerDisconnected)
}

export function testRenderPassDescriptorDefaults(): void {
  desc := RenderPassDescriptor {}

  Assert.equal(desc.camera.kind, CameraKind.Screen)
  Assert.equal(desc.clear.kind, ClearKind.None)
  Assert.equal(desc.clear.depthValue, 1.0)
  Assert.equal(desc.depth.mode, DepthMode.Disabled)
  Assert.equal(desc.blend.mode, BlendMode.Opaque)
  Assert.equal(desc.winding, WindingMode.CounterClockwise)
  Assert.equal(desc.cull, CullMode.None)
}

export function testCameraHelpersBuildExpectedKinds(): void {
  Assert.equal(Camera.screen().kind, CameraKind.Screen)
  Assert.equal(Camera.identity().kind, CameraKind.Identity)
  Assert.equal(Camera.orthographic(-1.0, 1.0, -1.0, 1.0).kind, CameraKind.Orthographic)
  Assert.equal(Camera.perspective(1.0, 1.0, 0.1, 100.0).kind, CameraKind.Perspective)
}

export function testMat4IdentityTranslationAndScale(): void {
  point := Point3(1.0, 2.0, 3.0)
  moved := Mat4.translation(4.0, 5.0, 6.0).transformPoint(point)
  scaled := Mat4.scale(2.0, 3.0, 4.0).transformPoint(point)
  combined := Mat4.translation(4.0, 5.0, 6.0).multiply(Mat4.scale(2.0, 3.0, 4.0)).transformPoint(point)

  Assert.equal(Mat4.identity.transformPoint(point).x, 1.0)
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

  rotatedX := Mat4.rotationX(quarterTurn).transformPoint(Point3(0.0, 1.0, 0.0))
  rotatedY := Mat4.rotationY(quarterTurn).transformPoint(Point3(0.0, 0.0, 1.0))
  rotatedZ := Mat4.rotationZ(quarterTurn).transformPoint(Point3(1.0, 0.0, 0.0))

  Assert.isTrue(approxEqual(rotatedX.y, 0.0))
  Assert.isTrue(approxEqual(rotatedX.z, 1.0))
  Assert.isTrue(approxEqual(rotatedY.x, 1.0))
  Assert.isTrue(approxEqual(rotatedY.z, 0.0))
  Assert.isTrue(approxEqual(rotatedZ.x, 0.0))
  Assert.isTrue(approxEqual(rotatedZ.y, 1.0))
}

export function testMat4OrthographicMapsBoundsToClipSpace(): void {
  matrix := Mat4.orthographic(10.0, 30.0, 20.0, 60.0, -1.0, 1.0)
  bottomLeft := matrix.transformPoint(Point3(10.0, 20.0, 0.0))
  topRight := matrix.transformPoint(Point3(30.0, 60.0, 0.0))

  Assert.isTrue(approxEqual(bottomLeft.x, -1.0))
  Assert.isTrue(approxEqual(bottomLeft.y, -1.0))
  Assert.isTrue(approxEqual(topRight.x, 1.0))
  Assert.isTrue(approxEqual(topRight.y, 1.0))
  Assert.equal(bottomLeft.w, 1.0)
}

export function testMat4PerspectiveProducesPerspectiveDivideW(): void {
  matrix := Mat4.perspective(1.5707963267948966, 1.0, 1.0, 10.0)
  projected := matrix.transformPoint(Point3(0.0, 0.0, -5.0))

  Assert.isTrue(approxEqual(projected.x, 0.0))
  Assert.isTrue(approxEqual(projected.y, 0.0))
  Assert.equal(projected.w, 5.0)
}

export function testVec3Helpers(): void {
  value := Vec3.xyz(3.0, 4.0, 0.0)
  unit := value.normalized()
  cross := Vec3.right.cross(Vec3.up)

  Assert.equal(value.length(), 5.0)
  assertVec3Approx(unit, Vec3.xyz(0.6, 0.8, 0.0))
  assertVec3Approx(cross, Vec3.back)
  Assert.equal(Vec3.fromPoint(Point3(1.0, 2.0, 3.0)).z, 3.0)
}

export function testRotationCompositionInverseAndSlerp(): void {
  yaw := Rotation.y(90.0)
  pitch := Rotation.x(90.0)
  yawThenPitch := yaw.andThen(pitch)
  pitchThenYaw := pitch.andThen(yaw)
  forward := yawThenPitch.apply(Vec3.forward)
  manualForward := pitch.apply(yaw.apply(Vec3.forward))
  original := yawThenPitch.inverse().apply(forward)
  halfway := Rotation.slerp(Rotation.identity, yaw, 0.5).apply(Vec3.forward)

  assertVec3Approx(Rotation.x(90.0).apply(Vec3.forward), Vec3.up)
  assertVec3Approx(Rotation.x(90.0).apply(Vec3.forward), Rotation.axisAngle(Vec3.xAxis, 90.0).apply(Vec3.forward))
  assertVec3Approx(forward, manualForward, "andThen should match applying this rotation, then the next rotation")
  assertVec3Approx(forward, Vec3.left, "yaw then world-space pitch leaves the left vector on the X axis")
  assertVec3Approx(original, Vec3.forward, "applying the inverse rotation should return to the original vector")
  Assert.isFalse(approxEqual(yawThenPitch.apply(Vec3.forward).y, pitchThenYaw.apply(Vec3.forward).y), "order of composition should matter")
  assertApprox(halfway.x, -0.7071067811865476)
  assertApprox(halfway.z, -0.7071067811865476)
}

export function testRotationLookAtAndEuler(): void {
  aim := Rotation.lookAt{ direction: Vec3.forward, up: Vec3.up }
  euler := Rotation.euler{
    yaw: 90.0,
    pitch: 0.0,
    roll: 0.0
  }
  free := Rotation.axisAngle(Vec3.toNormalized(1.0, 1.0, 0.0), 30.0)

  assertVec3Approx(aim.apply(Vec3.forward), Vec3.forward)
  assertVec3Approx(euler.apply(Vec3.forward), Vec3.left)
  Assert.isTrue(approxEqual(free.apply(Vec3.forward).length(), 1.0))
}

export function testTransformReplacementRelativeMotionAndMatrices(): void {
  t1 := Transform {
    position: Point3(0.0, 0.0, -4.0),
    rotation: Rotation.y(90.0),
    scale: Vec3.one,
  }
  t2 := t1
    .withPosition(Point3(2.0, 0.0, -4.0))
    .withRotation(Rotation.identity)
    .withScale(Vec3.xyz(2.0, 2.0, 2.0))
  t3 := t1
    .movedBy(Vec3.xyz(0.0, 1.0, 0.0))
    .rotatedLocalY(15.0)
    .scaledBy(1.5)
  localMove := t1.movedLocalBy(Vec3.forward.times(2.0))
  worldMove := t1.movedWorldBy(Vec3.forward.times(2.0))
  worldPoint := t1.applyPoint(Point3(0.0, 0.0, -1.0))
  worldVector := t1.applyVector(Vec3.forward)
  localPitch := t1.rotatedLocalX(90.0).applyVector(Vec3.forward)
  worldPitch := t1.rotatedWorldX(90.0).applyVector(Vec3.forward)
  modelMatrix := t1.toMat4()
  matrixPoint := modelMatrix.transformPoint(Point3(0.0, 0.0, -1.0))
  inverseMatrixPoint := t1.toInverseMat4().transformPoint(worldPoint)
  normalMatrix := t2.toNormalMat3()

  assertPoint3Approx(t2.position, Point3(2.0, 0.0, -4.0))
  assertVec3Approx(t2.scale, Vec3.xyz(2.0, 2.0, 2.0))
  assertVec3Approx(t3.scale, Vec3.xyz(1.5, 1.5, 1.5))
  assertPoint3Approx(localMove.position, Point3(-2.0, 0.0, -4.0))
  assertPoint3Approx(worldMove.position, Point3(0.0, 0.0, -6.0))
  assertPoint3Approx(worldPoint, Point3(-1.0, 0.0, -4.0))
  assertVec3Approx(worldVector, Vec3.left)
  assertVec3Approx(localPitch, Vec3.up)
  assertVec3Approx(worldPitch, Vec3.left)
  assertApprox(matrixPoint.x, worldPoint.x)
  assertApprox(matrixPoint.y, worldPoint.y)
  assertApprox(matrixPoint.z, worldPoint.z)
  assertApprox(inverseMatrixPoint.x, 0.0)
  assertApprox(inverseMatrixPoint.y, 0.0)
  assertApprox(inverseMatrixPoint.z, -1.0)
  assertApprox(normalMatrix.m00, 0.5)
}

export function testClearHelpers(): void {
  color := Color(0.1, 0.2, 0.3, 0.4)
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
  point := Point(3.0, 4.0)
  rect := Rect(10.0, 20.0, 30.0, 40.0)
  white := Color.white
  red := Color.red

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
  Assert.equal(red.r, 1.0)
  Assert.equal(red.g, 0.0)
  Assert.equal(red.b, 0.0)
  Assert.equal(red.a, 1.0)
}

export function testSimpleMeshBuilderVertexDefaults(): void {
  builder := SimpleMeshBuilder.create()
  index := builder.vertex{ position: Point3(1.0, 2.0, 3.0) }
  spec := builder.buildSpec()

  Assert.equal(index, 0)
  Assert.equal(spec.vertexCount(), 1)
  Assert.equal(spec.indexCount(), 0)
  Assert.equal(spec.positions[0].x, 1.0)
  Assert.equal(spec.positions[0].y, 2.0)
  Assert.equal(spec.positions[0].z, 3.0)
  Assert.equal(spec.colors[0].r, 1.0)
  Assert.equal(spec.colors[0].g, 1.0)
  Assert.equal(spec.colors[0].b, 1.0)
  Assert.equal(spec.colors[0].a, 1.0)
  Assert.equal(spec.uvs[0].x, 0.0)
  Assert.equal(spec.uvs[0].y, 0.0)
  Assert.equal(spec.normals[0].x, 0.0)
  Assert.equal(spec.normals[0].y, 0.0)
  Assert.equal(spec.normals[0].z, 1.0)
}

export function testSimpleMeshBuilderTriangleAndQuadSpec(): void {
  builder := SimpleMeshBuilder.create()
  i0 := builder.vertex{
    position: Point3(0.0, 0.0, 0.0),
    color: Color.red,
    uv: Point(0.25, 0.5),
    normal: Point3(1.0, 0.0, 0.0),
  }
  i1 := builder.vertex{ position: Point3(1.0, 0.0, 0.0) }
  i2 := builder.vertex{ position: Point3(0.0, 1.0, 0.0) }
  builder.triangle(i0, i1, i2)
  builder.quad{
    a: Point3(-1.0, -1.0, 0.0),
    b: Point3(1.0, -1.0, 0.0),
    c: Point3(1.0, 1.0, 0.0),
    d: Point3(-1.0, 1.0, 0.0),
    color: Color(0.2, 0.3, 0.4),
    normal: Point3(0.0, 1.0, 0.0),
    uvA: Point(0.0, 1.0),
    uvB: Point(1.0, 1.0),
    uvC: Point(1.0, 0.0),
    uvD: Point(0.0, 0.0),
  }

  spec := builder.buildSpec()

  Assert.equal(spec.vertexCount(), 7)
  Assert.equal(spec.indexCount(), 9)
  Assert.equal(spec.indices[0], 0)
  Assert.equal(spec.indices[1], 1)
  Assert.equal(spec.indices[2], 2)
  Assert.equal(spec.indices[3], 3)
  Assert.equal(spec.indices[4], 4)
  Assert.equal(spec.indices[5], 5)
  Assert.equal(spec.indices[6], 3)
  Assert.equal(spec.indices[7], 5)
  Assert.equal(spec.indices[8], 6)
  Assert.equal(spec.colors[0].r, 1.0)
  Assert.equal(spec.uvs[0].x, 0.25)
  Assert.equal(spec.uvs[0].y, 0.5)
  Assert.equal(spec.normals[0].x, 1.0)
  Assert.equal(spec.normals[3].y, 1.0)
  Assert.equal(spec.uvs[3].x, 0.0)
  Assert.equal(spec.uvs[4].x, 1.0)
  Assert.equal(spec.uvs[5].y, 0.0)
}

export function testCreateSphereMeshSpecBuildsEquirectangularSphere(): void {
  spec := createSphereMeshSpec{
    radius: 2.0,
    tessellation: 4,
    color: Color(0.2, 0.4, 0.8),
  }

  Assert.equal(spec.vertexCount(), 45)
  Assert.equal(spec.indexCount(), 192)
  Assert.equal(spec.positions[0].x, 0.0)
  Assert.equal(spec.positions[0].y, 2.0)
  Assert.isTrue(approxEqual(spec.positions[0].z, 0.0))
  Assert.equal(spec.uvs[0].x, 1.0)
  Assert.equal(spec.uvs[0].y, 0.0)
  Assert.equal(spec.uvs[8].x, 0.0)
  Assert.equal(spec.uvs[8].y, 0.0)
  Assert.isTrue(approxEqual(spec.positions[18].x, 0.0))
  Assert.isTrue(approxEqual(spec.positions[18].y, 0.0))
  Assert.isTrue(approxEqual(spec.positions[18].z, -2.0))
  Assert.equal(spec.uvs[20].x, 0.75)
  Assert.isTrue(approxEqual(spec.positions[20].x, 2.0))
  Assert.isTrue(approxEqual(spec.normals[18].z, -1.0))
  Assert.equal(spec.colors[18].r, 0.2)
  Assert.equal(spec.indices[0], 0)
  Assert.equal(spec.indices[1], 1)
  Assert.equal(spec.indices[2], 9)

  a := spec.positions[9]
  b := spec.positions[10]
  c := spec.positions[18]
  normal := crossPoint3(subtractPoint3(b, a), subtractPoint3(c, a))
  outward := Point3(
    (a.x + b.x + c.x) / 3.0,
    (a.y + b.y + c.y) / 3.0,
    (a.z + b.z + c.z) / 3.0,
  )
  Assert.isTrue(normal.x * outward.x + normal.y * outward.y + normal.z * outward.z > 0.0)
}

function compileAtlasCellSmoke(texture: Texture): Rect {
  atlas := Atlas {
    texture: texture,
    columns: 14,
    rows: 4,
  }

  return atlas.cellRect(13, 2)
}
