import { readTextResource } from "std/fs"
import { clamp, cos, lerp, radians, round, sin } from "std/math"
import { Instant } from "std/time"

import {
  BitmapFont,
  Blend,
  Camera,
  CameraKind,
  Clear,
  Color,
  Depth,
  DepthTexture,
  GameApp,
  GameSurface,
  Key,
  Mat4,
  Point,
  Point3,
  RenderPass,
  RenderPassDescriptor,
  Renderer,
  ShaderBuffer,
  ShaderBufferBinding,
  ShaderBytesBuilder,
  ShaderBytesBinding,
  ShaderDraw,
  ShaderPipeline,
  ShaderPipelineDescriptor,
  ShaderProgram,
  ShaderTextureBinding,
  ShaderVertexAttribute,
  ShaderVertexFormat,
  ShaderVertexLayout,
  SimpleMesh,
  SimpleMeshBuilder,
  SimpleMeshSpec,
  SimpleModel,
  TextLayoutOptions,
  Vec3,
  createIcosphereMeshSpec,
  createTextModel,
  drawShader,
  drawSimpleMesh,
  drawSimpleModel,
  initGameApp,
} from "std/game"

readonly SHADOW_SIZE = 2048
readonly VERTEX_STRIDE = 40
readonly SHADOW_SHADER_PATH = "shaders/shadow_scene.metal"

// The light's orthographic box. It must enclose every shadow caster.
readonly LIGHT_EXTENT = 8.0
readonly LIGHT_DISTANCE = 14.0

readonly SKY_COLOR = Color(0.62, 0.70, 0.80)
readonly FOG_DENSITY = 0.032
readonly AMBIENT_STRENGTH = 0.42
// About two shadow-map texels in world units (2 * LIGHT_EXTENT / SHADOW_SIZE per texel).
readonly SHADOW_NORMAL_OFFSET = 0.016

readonly HUD_TEXT_COLOR = Color(0.95, 0.96, 0.98)
readonly HUD_DIM_COLOR = Color(0.72, 0.78, 0.86)

// ---------------------------------------------------------------------------
// Shadow presets

class ShadowPreset {
  readonly name: string
  readonly strength: double
  readonly radiusTexels: double
}

readonly SHADOW_PRESETS: readonly ShadowPreset[] = [
  ShadowPreset { name: "Off", strength: 0.0, radiusTexels: 0.0 },
  ShadowPreset { name: "Hard", strength: 1.0, radiusTexels: 0.0 },
  ShadowPreset { name: "Soft PCF", strength: 1.0, radiusTexels: 1.35 },
  ShadowPreset { name: "Extra soft PCF", strength: 1.0, radiusTexels: 3.2 },
]

// ---------------------------------------------------------------------------
// Scene description

class SceneMaterial {
  readonly specular: double = 0.2
  readonly shininess: double = 24.0
  readonly emissive: double = 0.0
  readonly checker: double = 0.0
}

// One mesh uploaded twice: as a SimpleMesh for the built-in depth-only pass,
// and as raw vertex/index buffers for the custom lit shader.
class SceneMesh {
  readonly depthMesh: SimpleMesh
  readonly vertexBuffer: ShaderBuffer
  readonly indexBuffer: ShaderBuffer
  readonly indexCount: int
}

class SceneObject {
  readonly mesh: SceneMesh
  readonly material: SceneMaterial = SceneMaterial {}
  readonly castsShadow: bool = true
  readonly placement: (time: double): Mat4 = (time: double): Mat4 => Mat4.translation(0.0, 0.0, 0.0)
}

class ShadowScene {
  readonly shadowMap: DepthTexture
  readonly pipeline: ShaderPipeline
  objects: SceneObject[]
  readonly sunMarker: SceneObject
}

// Everything the frame needs to know about the sun.
class SunState {
  readonly towardSun: Vec3
  readonly color: Color
  readonly viewProjection: Mat4
}

// ---------------------------------------------------------------------------
// Geometry

function vertexBytes(spec: SimpleMeshSpec): readonly byte[] {
  builder := ShaderBytesBuilder()
  for index of 0..<spec.positions.length {
    builder
      .point3(spec.positions[index])
      .point3(spec.normals[index])
      .color(spec.colors[index])
  }
  return builder.build()
}

function indexBytes(indices: readonly int[]): readonly byte[] {
  builder := ShaderBytesBuilder()
  for index of indices {
    builder.uint32(index)
  }
  return builder.build()
}

function uploadMesh(surface: GameSurface, spec: SimpleMeshSpec): SceneMesh {
  return SceneMesh {
    depthMesh: SimpleMesh(surface, spec),
    vertexBuffer: try! ShaderBuffer.create(surface, vertexBytes(spec)),
    indexBuffer: try! ShaderBuffer.create(surface, indexBytes(spec.indices)),
    indexCount: spec.indices.length,
  }
}

function boxSpec(center: Point3, size: Vec3, color: Color): SimpleMeshSpec {
  return SimpleMeshBuilder().box(center, size, color).buildSpec()
}

function groundSpec(): SimpleMeshSpec {
  half := 60.0
  return SimpleMeshBuilder()
    .quad{
      a: Point3(-half, 0.0, -half),
      b: Point3(-half, 0.0, half),
      c: Point3(half, 0.0, half),
      d: Point3(half, 0.0, -half),
      color: Color(0.58, 0.66, 0.52),
      normal: Point3(0.0, 1.0, 0.0),
    }
    .buildSpec()
}

function archSpec(): SimpleMeshSpec {
  stone := Color(0.86, 0.80, 0.70)
  return SimpleMeshBuilder()
    .box(Point3(0.0, 1.2, -1.1), Vec3.xyz(0.55, 2.4, 0.55), stone)
    .box(Point3(0.0, 1.2, 1.1), Vec3.xyz(0.55, 2.4, 0.55), stone)
    .box(Point3(0.0, 2.6, 0.0), Vec3.xyz(0.8, 0.4, 3.0), stone)
    .buildSpec()
}

function steppedTowerSpec(): SimpleMeshSpec {
  return SimpleMeshBuilder()
    .box(Point3(0.0, 0.3, 0.0), Vec3.xyz(1.8, 0.6, 1.8), Color(0.20, 0.38, 0.74))
    .box(Point3(0.0, 0.9, 0.0), Vec3.xyz(1.3, 0.6, 1.3), Color(0.26, 0.48, 0.84))
    .box(Point3(0.0, 1.5, 0.0), Vec3.xyz(0.8, 0.6, 0.8), Color(0.34, 0.58, 0.92))
    .buildSpec()
}

function windmillBladesSpec(): SimpleMeshSpec {
  white := Color(0.94, 0.93, 0.90)
  return SimpleMeshBuilder()
    .box(Point3(0.0, 0.0, 0.0), Vec3.xyz(3.8, 0.14, 0.42), white)
    .box(Point3(0.0, 0.0, 0.0), Vec3.xyz(0.42, 0.14, 3.8), white)
    .box(Point3(0.0, 0.0, 0.0), Vec3.xyz(0.5, 0.3, 0.5), Color(0.84, 0.28, 0.20))
    .buildSpec()
}

function translated(x: double, y: double, z: double): Mat4 {
  return Mat4.translation(x, y, z)
}

function createScene(renderer: Renderer): ShadowScene {
  surface := renderer.surface()
  glossy := SceneMaterial { specular: 0.65, shininess: 72.0 }
  satin := SceneMaterial { specular: 0.3, shininess: 28.0 }
  matte := SceneMaterial { specular: 0.06, shininess: 8.0 }

  ground := uploadMesh(surface, groundSpec())
  arch := uploadMesh(surface, archSpec())
  tower := uploadMesh(surface, steppedTowerSpec())
  pole := uploadMesh(surface, boxSpec(Point3(0.0, 1.35, 0.0), Vec3.xyz(0.26, 2.7, 0.26), Color(0.52, 0.46, 0.40)))
  blades := uploadMesh(surface, windmillBladesSpec())
  orb := uploadMesh(surface, createIcosphereMeshSpec(0.62, 3, Color(0.95, 0.72, 0.22)))
  cube := uploadMesh(surface, boxSpec(Point3(0.0, 0.0, 0.0), Vec3.xyz(0.9, 0.9, 0.9), Color(0.84, 0.30, 0.34)))
  moon := uploadMesh(surface, createIcosphereMeshSpec(0.22, 2, Color(0.72, 0.88, 0.80)))
  sun := uploadMesh(surface, createIcosphereMeshSpec(0.35, 2, Color(1.0, 1.0, 1.0)))

  objects: SceneObject[] := [
    SceneObject {
      mesh: ground,
      material: SceneMaterial { specular: 0.04, shininess: 6.0, checker: 1.0 },
      castsShadow: false,
    },
    SceneObject {
      mesh: arch,
      material: matte,
      placement: (time: double): Mat4 => translated(-3.4, 0.0, -0.6),
    },
    SceneObject {
      mesh: tower,
      material: satin,
      placement: (time: double): Mat4 => translated(1.2, 0.0, -2.6),
    },
    SceneObject { mesh: pole, material: matte },
    // Windmill blades sweep a shadow across everything below them.
    SceneObject {
      mesh: blades,
      material: satin,
      placement: (time: double): Mat4 => translated(0.0, 2.85, 0.0).multiply(Mat4.rotationY(time * 0.9)),
    },
    // Bobbing, spinning orb.
    SceneObject {
      mesh: orb,
      material: glossy,
      placement: (time: double): Mat4 => translated(2.9, 1.15 + sin(time * 1.6) * 0.45, 0.4)
        .multiply(Mat4.rotationY(time * 0.7)),
    },
    // Tumbling cube.
    SceneObject {
      mesh: cube,
      material: glossy,
      placement: (time: double): Mat4 => translated(-0.6, 1.25 + sin(time * 1.1 + 1.3) * 0.25, 2.6)
        .multiply(Mat4.rotationY(time * 0.8))
        .multiply(Mat4.rotationX(time * 0.55)),
    },
    // A small moon circling the orb.
    SceneObject {
      mesh: moon,
      material: glossy,
      placement: (time: double): Mat4 => translated(
        2.9 + cos(time * 2.2) * 1.2,
        1.15 + sin(time * 1.6) * 0.45 + sin(time * 2.2) * 0.3,
        0.4 + sin(time * 2.2) * 1.2,
      ),
    },
  ]

  return ShadowScene {
    shadowMap: try! renderer.createDepthTexture(SHADOW_SIZE, SHADOW_SIZE),
    pipeline: createShadowPipeline(surface),
    objects,
    sunMarker: SceneObject {
      mesh: sun,
      material: SceneMaterial { emissive: 1.4 },
      castsShadow: false,
    },
  }
}

// ---------------------------------------------------------------------------
// Pipeline

function createShadowPipeline(surface: GameSurface): ShaderPipeline {
  return try! ShaderPipeline(
    surface,
    ShaderPipelineDescriptor {
      program: ShaderProgram {
        vertexSource: try! readTextResource(SHADOW_SHADER_PATH),
        vertexFunction: "shadow_scene_vertex",
        fragmentFunction: "shadow_scene_fragment",
      },
      attributes: [
        ShaderVertexAttribute { attribute: 0, offset: 0, format: ShaderVertexFormat.Float3 },
        ShaderVertexAttribute { attribute: 1, offset: 12, format: ShaderVertexFormat.Float3 },
        ShaderVertexAttribute { attribute: 2, offset: 24, format: ShaderVertexFormat.Float4 },
      ],
      layouts: [ShaderVertexLayout { stride: VERTEX_STRIDE }],
    },
  )
}

// ---------------------------------------------------------------------------
// Sun

function matrixWithClipOffset(matrix: Mat4, offsetX: double, offsetY: double): Mat4 {
  return Mat4 {
    m00: matrix.m00, m01: matrix.m01, m02: matrix.m02, m03: matrix.m03 + offsetX,
    m10: matrix.m10, m11: matrix.m11, m12: matrix.m12, m13: matrix.m13 + offsetY,
    m20: matrix.m20, m21: matrix.m21, m22: matrix.m22, m23: matrix.m23,
    m30: matrix.m30, m31: matrix.m31, m32: matrix.m32, m33: matrix.m33,
  }
}

// Moving the light by fractions of a shadow texel makes shadow edges crawl.
// Snapping the world origin to a texel boundary keeps them stable.
function snapLightMatrixToShadowTexels(matrix: Mat4): Mat4 {
  origin := matrix.projectPoint(Point3(0.0, 0.0, 0.0))
  texelSize := 2.0 / double(SHADOW_SIZE)
  snappedX := round(origin.x / texelSize) * texelSize
  snappedY := round(origin.y / texelSize) * texelSize
  return matrixWithClipOffset(matrix, snappedX - origin.x, snappedY - origin.y)
}

function mixColor(a: Color, b: Color, t: double): Color {
  return Color(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t))
}

function sunAt(time: double, surface: GameSurface): SunState {
  azimuth := time * 0.22
  elevationDegrees := 40.0 + sin(time * 0.13) * 18.0
  elevation := radians(elevationDegrees)
  towardSun := Vec3.xyz(cos(azimuth) * cos(elevation), sin(elevation), sin(azimuth) * cos(elevation))

  // Low sun is warm and dim; high sun is bright and nearly white.
  noon := clamp((elevationDegrees - 22.0) / 36.0, 0.0, 1.0)
  color := mixColor(Color(1.05, 0.62, 0.36), Color(1.1, 1.02, 0.9), noon)

  lightCamera := Camera
    .orthographic(-LIGHT_EXTENT, LIGHT_EXTENT, -LIGHT_EXTENT, LIGHT_EXTENT, 0.1, LIGHT_DISTANCE * 2.0)
    .withPosition(towardSun.times(LIGHT_DISTANCE).toPoint3())
    .lookAt(Point3(0.0, 0.0, 0.0), Vec3.up)

  return SunState {
    towardSun,
    color,
    viewProjection: snapLightMatrixToShadowTexels(lightCamera.matrix(surface)),
  }
}

// ---------------------------------------------------------------------------
// Orbit camera

class OrbitCamera {
  let yaw: double = 0.75
  let pitch: double = 0.42
  let distance: double = 11.5
  let idleSeconds: double = 10.0
  readonly target: Point3 = Point3(0.0, 1.0, 0.0)

  update(app: GameApp, deltaSeconds: double): none {
    if app.input.isMouseButtonDown(.Left) {
      yaw -= app.input.mouseDeltaX() * 0.006
      pitch = clamp(pitch + app.input.mouseDeltaY() * 0.006, 0.06, 1.4)
      idleSeconds = 0.0
    } else {
      idleSeconds += deltaSeconds
    }

    scroll := app.input.scrollDeltaY()
    if scroll != 0.0 {
      distance = clamp(distance - scroll * 0.25, 5.0, 28.0)
    }

    // Drift slowly once the user lets go for a moment.
    if idleSeconds > 3.0 {
      yaw += deltaSeconds * 0.06
    }
  }

  reset(): none {
    yaw = 0.75
    pitch = 0.42
    distance = 11.5
  }

  eye(): Point3 {
    return Point3(
      target.x + cos(yaw) * cos(pitch) * distance,
      target.y + sin(pitch) * distance,
      target.z + sin(yaw) * cos(pitch) * distance,
    )
  }

  camera(): Camera {
    return Camera
      .perspective(0.82, 0.1, 150.0)
      .withPosition(eye())
      .lookAt(target, Vec3.up)
  }
}

// ---------------------------------------------------------------------------
// Drawing

function objectUniformBytes(
  model: Mat4,
  viewProjection: Mat4,
  sun: SunState,
  eye: Point3,
  preset: ShadowPreset,
  material: SceneMaterial,
): readonly byte[] {
  lightDirection := sun.towardSun.times(-1.0)
  return ShaderBytesBuilder()
    .mat4Rows(model)
    .mat4Rows(viewProjection)
    .mat4Rows(sun.viewProjection)
    .float4(lightDirection.x, lightDirection.y, lightDirection.z, SHADOW_NORMAL_OFFSET)
    .float4(sun.color.r, sun.color.g, sun.color.b, AMBIENT_STRENGTH)
    .float4(eye.x, eye.y, eye.z, FOG_DENSITY)
    .color(SKY_COLOR)
    .float4(0.00055, preset.strength, 0.0012, preset.radiusTexels)
    .float4(material.specular, material.shininess, material.emissive, material.checker)
    .build()
}

function drawLitObject(
  pass: RenderPass,
  scene: ShadowScene,
  object: SceneObject,
  model: Mat4,
  viewProjection: Mat4,
  sun: SunState,
  eye: Point3,
  preset: ShadowPreset,
): none {
  // The same uniform block feeds both stages, at different Metal buffer slots.
  bytes := objectUniformBytes(model, viewProjection, sun, eye, preset, object.material)
  try! drawShader(
    pass,
    ShaderDraw {
      pipeline: scene.pipeline,
      vertexBuffers: [ShaderBufferBinding { index: 0, buffer: object.mesh.vertexBuffer }],
      vertexBytes: [try! ShaderBytesBinding.create(pass.surface(), 1, bytes)],
      fragmentBytes: [try! ShaderBytesBinding.create(pass.surface(), 0, bytes)],
      fragmentTextures: [ShaderTextureBinding { index: 0, depthTexture: scene.shadowMap }],
      indexBuffer: object.mesh.indexBuffer,
      indexCount: object.mesh.indexCount,
    },
  )
}

function cameraFromMatrix(matrix: Mat4): Camera {
  return Camera {
    kind: CameraKind.Identity,
    viewProjection: matrix,
  }
}

function renderScene(
  renderer: Renderer,
  scene: ShadowScene,
  time: double,
  orbit: OrbitCamera,
  preset: ShadowPreset,
): none {
  surface := renderer.surface()
  sun := sunAt(time, surface)
  sceneCamera := orbit.camera()
  viewProjection := sceneCamera.matrix(surface)
  eye := orbit.eye()

  models: Mat4[] := []
  for object of scene.objects {
    models.push(object.placement(time))
  }

  // Pass 1: render caster depth from the sun into the shadow map.
  renderer.depthPass(
    scene.shadowMap,
    RenderPassDescriptor {
      camera: cameraFromMatrix(sun.viewProjection),
      clear: Clear.depth(1.0),
      depth: Depth.readWrite(),
      blend: Blend.opaque(),
      cull: .None,
    },
    (pass): none => {
      for index of 0..<scene.objects.length {
        object := scene.objects[index]
        if object.castsShadow {
          drawSimpleMesh(pass, object.mesh.depthMesh, models[index])
        }
      }
    },
  )

  // Pass 2: shade the scene from the viewer, sampling the shadow map.
  renderer.pass(
    RenderPassDescriptor {
      camera: sceneCamera,
      clear: Clear.colorDepth(SKY_COLOR, 1.0),
      depth: Depth.readWrite(),
      blend: Blend.opaque(),
      cull: .Back,
    },
    (pass): none => {
      for index of 0..<scene.objects.length {
        drawLitObject(pass, scene, scene.objects[index], models[index], viewProjection, sun, eye, preset)
      }
      sunPosition := sun.towardSun.times(9.0)
      drawLitObject(
        pass,
        scene,
        scene.sunMarker,
        Mat4.translation(sunPosition.x, sunPosition.y, sunPosition.z),
        viewProjection,
        sun,
        eye,
        preset,
      )
    },
  )
}

// ---------------------------------------------------------------------------
// HUD

class Hud {
  font: BitmapFont
  panel: SimpleMesh
  let title: SimpleModel
  let status: SimpleModel
  let help: SimpleModel
}

function createHud(app: GameApp, presetName: string, paused: bool): Hud {
  font := try! app.loadIntrinsicFont()
  panel := SimpleMeshBuilder()
    .quad{
      a: Point3(16.0, 16.0, 0.0),
      b: Point3(420.0, 16.0, 0.0),
      c: Point3(420.0, 124.0, 0.0),
      d: Point3(16.0, 124.0, 0.0),
      color: Color(0.04, 0.06, 0.09, 0.62),
    }
    .build(app.surface)
  return Hud {
    font,
    panel,
    title: createTextModel(
      app.surface,
      font,
      "Shadow Maps",
      TextLayoutOptions { position: Point(32.0, 30.0), color: HUD_TEXT_COLOR },
    ),
    status: hudStatus(app.surface, font, presetName, paused),
    help: createTextModel(
      app.surface,
      font,
      "Drag to orbit, scroll to zoom\n1-4 shadow mode  Space pause  R reset",
      TextLayoutOptions { position: Point(32.0, 80.0), lineSpacing: 4.0, color: HUD_DIM_COLOR },
    ),
  }
}

function hudStatus(surface: GameSurface, font: BitmapFont, presetName: string, paused: bool): SimpleModel {
  suffix := if paused then "  (paused)" else ""
  return createTextModel(
    surface,
    font,
    "Mode: ${presetName}${suffix}",
    TextLayoutOptions { position: Point(32.0, 54.0), color: Color(1.0, 0.82, 0.46) },
  )
}

function drawHud(renderer: Renderer, hud: Hud): none {
  renderer.pass(
    RenderPassDescriptor {
      camera: Camera.screen(),
      clear: Clear.disabled(),
      depth: Depth.disabled(),
      blend: Blend.alpha(),
    },
    (pass): none => {
      drawSimpleMesh(pass, hud.panel)
      drawSimpleModel(pass, hud.title)
      drawSimpleModel(pass, hud.status)
      drawSimpleModel(pass, hud.help)
    },
  )
}

// ---------------------------------------------------------------------------

function main(): int {
  app := initGameApp{ title: "Doof Game Shadow Maps" }
  orbit := OrbitCamera {}
  let scene: ShadowScene | none = none
  let presetIndex = 2
  let paused = false
  let time = 0.0
  let lastFrameAt = Instant.now()
  hud := createHud(app, SHADOW_PRESETS[presetIndex].name, paused)

  refreshStatus := (): none => {
    hud.status = hudStatus(app.surface, hud.font, SHADOW_PRESETS[presetIndex].name, paused)
  }
  selectPreset := (index: int): none => {
    presetIndex = index
    refreshStatus()
  }

  app.key(.Escape).onPressed() {
    app.stop()
  }
  app.key(.Space).onPressed() {
    paused = !paused
    refreshStatus()
  }
  app.key(.R).onPressed() {
    orbit.reset()
  }
  app.key(.Digit1).onPressed() { selectPreset(0) }
  app.key(.Digit2).onPressed() { selectPreset(1) }
  app.key(.Digit3).onPressed() { selectPreset(2) }
  app.key(.Digit4).onPressed() { selectPreset(3) }

  app.onRender((renderer): none => {
    if scene == none {
      scene = createScene(renderer)
    }

    now := Instant.now()
    deltaSeconds := clamp(lastFrameAt.durationUntil(now).toSeconds(), 0.0, 0.1)
    lastFrameAt = now
    if !paused {
      time += deltaSeconds
    }
    orbit.update(app, deltaSeconds)

    renderScene(renderer, scene!, time, orbit, SHADOW_PRESETS[presetIndex])
    drawHud(renderer, hud)
  })

  app.run() else error {
    println(error)
    return 1
  }

  return 0
}
