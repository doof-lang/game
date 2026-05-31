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
  Color,
  Depth,
  DepthMode,
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
  SimpleMeshBuilder,
  Texture,
  TextureQuadBatchBuilder,
  Transform,
  Vec3,
  RenderPassDescriptor,
  drawSimpleModel,
  drawSimpleMesh,
  drawEquirectangularSkyMap,
  drawTexturedSimpleMesh,
  drawTextureQuadBatch,
  gameEventKindFromCode,
  initGameApp,
  keyCode,
  keyFromCode,
  mouseButtonCode,
  mouseButtonFromCode,
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

function compileSkyMapSmoke(texture: Texture, pass: RenderPass): void {
  skyMap := SkyMap { texture: texture }
  drawEquirectangularSkyMap(pass, skyMap, 1.0471975512, 1.0)
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
    Color(1.0, 1.0, 1.0, 0.75),
  )

  built := builder.build(surface)
  case built {
    s: Success -> drawTextureQuadBatch(pass, s.value, Mat4.identity)
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
        clear: Clear.colorDepth(Color.black, 1.0),
        depth: Depth.readWrite(),
        blend: Blend.opaque(),
      },
      (pass): void => {
        passSurface := pass.surface()
        encoderHandle := pass.metalRenderCommandEncoderHandle()
        deviceHandle := pass.metalDeviceHandle()
        blendCode := pass.nativeBlendModeCode()
        hasDepth := pass.hasDepthAttachment()
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

export function testCameraTransformHelpersUpdateCameraPose(): void {
  camera := Camera
    .perspective(1.0, 1.0, 0.1, 100.0)
    .withPosition(Point3(0.0, 0.0, 5.0))
    .movedLocalBy(Vec3.forward.times(2.0))
    .scaledBy(2.0)
  rotated := camera.rotatedLocalY(90.0)

  viewedOrigin := camera.transform.toInverseMat4().transformPoint(Point3(0.0, 0.0, 0.0))
  withExtraView := rotated.withView(Mat4.translation(1.0, 2.0, 3.0))

  assertPoint3Approx(camera.transform.position, Point3(0.0, 0.0, 3.0))
  assertVec3Approx(camera.transform.scale, Vec3.xyz(2.0, 2.0, 2.0))
  assertVec3Approx(rotated.transform.rotation.apply(Vec3.forward), Vec3.left)
  Assert.equal(withExtraView.kind, CameraKind.Perspective)
  assertPoint3Approx(withExtraView.transform.position, rotated.transform.position)
  assertApprox(viewedOrigin.z, -1.5)
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
  rect := Rect.xywh(10.0, 20.0, 30.0, 40.0)
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

function compileAtlasCellSmoke(texture: Texture): Rect {
  atlas := Atlas {
    texture: texture,
    columns: 14,
    rows: 4,
  }

  return atlas.cellRect(13, 2)
}
