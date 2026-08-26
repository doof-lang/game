import { readTextResource } from "std/fs"
import { cos, round, sin } from "std/math"
import { Instant } from "std/time"

import {
  Blend,
  Camera,
  CameraKind,
  Clear,
  Color,
  Depth,
  DepthTexture,
  GameSurface,
  Mat4,
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
  ShaderTextureBinding,
  ShaderVertexAttribute,
  ShaderVertexFormat,
  ShaderVertexLayout,
  SimpleMesh,
  SimpleMeshBuilder,
  SimpleMeshSpec,
  Vec3,
  drawShader,
  drawSimpleMesh,
  initGameApp,
} from "std/game"

readonly SHADOW_SIZE = 2048
readonly VERTEX_STRIDE = 40
readonly SHADOW_SHADER_PATH = "shaders/shadow_scene.metal"

class SceneGeometry {
  spec: SimpleMeshSpec
  casterSpec: SimpleMeshSpec
  vertexBytes: readonly byte[]
  indexBytes: readonly byte[]
}

class ShadowResources {
  readonly shadowMap: DepthTexture
  readonly depthMesh: SimpleMesh
  readonly pipeline: ShaderPipeline
  readonly vertexBuffer: ShaderBuffer
  readonly indexBuffer: ShaderBuffer
  readonly indexCount: int
}

function matrixWithClipOffset(matrix: Mat4, offsetX: double, offsetY: double): Mat4 {
  return Mat4 {
    m00: matrix.m00, m01: matrix.m01, m02: matrix.m02, m03: matrix.m03 + offsetX,
    m10: matrix.m10, m11: matrix.m11, m12: matrix.m12, m13: matrix.m13 + offsetY,
    m20: matrix.m20, m21: matrix.m21, m22: matrix.m22, m23: matrix.m23,
    m30: matrix.m30, m31: matrix.m31, m32: matrix.m32, m33: matrix.m33,
  }
}

function snapLightMatrixToShadowTexels(matrix: Mat4): Mat4 {
  origin := matrix.projectPoint(Point3(0.0, 0.0, 0.0))
  texelSize := 2.0 / double(SHADOW_SIZE)
  snappedX := round(origin.x / texelSize) * texelSize
  snappedY := round(origin.y / texelSize) * texelSize
  return matrixWithClipOffset(matrix, snappedX - origin.x, snappedY - origin.y)
}

function cameraFromMatrix(matrix: Mat4): Camera {
  return Camera {
    kind: CameraKind.Identity,
    viewProjection: matrix,
  }
}

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

function createSceneGeometry(): SceneGeometry {
  geometry := SimpleMeshBuilder()
  casters := SimpleMeshBuilder()
  ground := Color(0.45, 0.55, 0.46)
  geometry.quad{
    a: Point3(-8.0, 0.0, -7.0),
    b: Point3(-8.0, 0.0, 7.0),
    c: Point3(8.0, 0.0, 7.0),
    d: Point3(8.0, 0.0, -7.0),
    color: ground,
    normal: Point3(0.0, 1.0, 0.0),
  }
  red := Color(0.84, 0.28, 0.20)
  blue := Color(0.18, 0.42, 0.82)
  yellow := Color(0.88, 0.68, 0.22)
  geometry.box(Point3(-1.8, 0.7, -0.6), Vec3.xyz(1.1, 1.4, 1.1), red)
  casters.box(Point3(-1.8, 0.7, -0.6), Vec3.xyz(1.1, 1.4, 1.1), red)
  geometry.box(Point3(0.5, 1.05, 0.2), Vec3.xyz(1.25, 2.1, 1.25), blue)
  casters.box(Point3(0.5, 1.05, 0.2), Vec3.xyz(1.25, 2.1, 1.25), blue)
  geometry.box(Point3(2.3, 0.45, 1.0), Vec3.xyz(1.35, 0.9, 1.35), yellow)
  casters.box(Point3(2.3, 0.45, 1.0), Vec3.xyz(1.35, 0.9, 1.35), yellow)
  spec := geometry.buildSpec()
  casterSpec := casters.buildSpec()

  return SceneGeometry {
    spec,
    casterSpec,
    vertexBytes: vertexBytes(spec),
    indexBytes: indexBytes(spec.indices),
  }
}

function shaderSource(): string {
  return try! readTextResource(SHADOW_SHADER_PATH)
}

function createShadowPipeline(surface: GameSurface): ShaderPipeline {
  return try! ShaderPipeline(
    surface,
    ShaderPipelineDescriptor {
      source: shaderSource(),
      vertexFunction: "shadow_scene_vertex",
      fragmentFunction: "shadow_scene_fragment",
      attributes: [
        ShaderVertexAttribute { attribute: 0, offset: 0, format: ShaderVertexFormat.Float3 },
        ShaderVertexAttribute { attribute: 1, offset: 12, format: ShaderVertexFormat.Float3 },
        ShaderVertexAttribute { attribute: 2, offset: 24, format: ShaderVertexFormat.Float4 },
      ],
      layouts: [ShaderVertexLayout { stride: VERTEX_STRIDE }],
    },
  )
}

function createShadowResources(renderer: Renderer): ShadowResources {
  surface := renderer.surface()
  geometry := createSceneGeometry()
  shadowMap := try! renderer.createDepthTexture(SHADOW_SIZE, SHADOW_SIZE)
  return ShadowResources {
    shadowMap,
    depthMesh: SimpleMesh(surface, geometry.casterSpec),
    pipeline: createShadowPipeline(surface),
    vertexBuffer: try! ShaderBuffer.create(surface, geometry.vertexBytes),
    indexBuffer: try! ShaderBuffer.create(surface, geometry.indexBytes),
    indexCount: geometry.spec.indices.length,
  }
}

function sceneUniformBytes(viewProjection: Mat4, lightViewProjection: Mat4, lightDirection: Vec3): readonly byte[] {
  return ShaderBytesBuilder()
    .mat4Rows(viewProjection)
    .mat4Rows(lightViewProjection)
    .vec3(lightDirection)
    .paddingFloat32()
    .float32(0.00055)
    .float32(0.72)
    .float32(0.0012)
    .float32(1.35)
    .build()
}

function drawShadowedScene(
  pass: RenderPass,
  resources: ShadowResources,
  viewProjection: Mat4,
  lightViewProjection: Mat4,
  lightDirection: Vec3,
): none {
  uniforms := try! ShaderBytesBinding.create(pass.surface(), 1, sceneUniformBytes(viewProjection, lightViewProjection, lightDirection))
  fragmentUniforms := try! ShaderBytesBinding.create(pass.surface(), 0, sceneUniformBytes(viewProjection, lightViewProjection, lightDirection))
  try! drawShader(
    pass,
    ShaderDraw {
      pipeline: resources.pipeline,
      vertexBuffers: [ShaderBufferBinding { index: 0, buffer: resources.vertexBuffer }],
      vertexBytes: [uniforms],
      fragmentBytes: [fragmentUniforms],
      fragmentTextures: [ShaderTextureBinding { index: 0, depthTexture: resources.shadowMap }],
      indexBuffer: resources.indexBuffer,
      indexCount: resources.indexCount,
    },
  )
}

function main(): int {
  app := initGameApp{ title: "Doof Game Shadow Maps" }
  start := Instant.now()
  let resources: ShadowResources | none = none

  app.key(.Escape).onPressed() {
    app.stop()
  }

  app.onRender((renderer): none => {
    if resources == none {
      resources = createShadowResources(renderer)
    }
    surface := renderer.surface()

    elapsed := start.durationUntil(Instant.now()).toSeconds()
    lightAngle := elapsed * 0.28
    lightPosition := Point3(cos(lightAngle) * 5.0, 7.0, sin(lightAngle) * 5.0)
    lightCamera := Camera
      .orthographic(-7.0, 7.0, -7.0, 7.0, 0.1, 24.0)
      .withPosition(lightPosition)
      .lookAt(Point3(0.0, 0.0, 0.0), Vec3.up)
    lightMatrix := snapLightMatrixToShadowTexels(lightCamera.matrix(surface))
    lightPassCamera := cameraFromMatrix(lightMatrix)
    lightDirection := Vec3.fromPoint(Point3(0.0, 0.0, 0.0)).minus(Vec3.fromPoint(lightPosition)).normalized()

    sceneCamera := Camera
      .perspective(0.82, 0.1, 80.0)
      .withPosition(Point3(5.8, 4.6, 7.0))
      .lookAt(Point3(0.0, 0.8, 0.0), Vec3.up)

    renderer.depthPass(
      resources!.shadowMap,
      RenderPassDescriptor {
        camera: lightPassCamera,
        clear: Clear.depth(1.0),
        depth: Depth.readWrite(),
        blend: Blend.opaque(),
        cull: .None,
      },
      (pass): none => {
        drawSimpleMesh(pass, resources!.depthMesh)
      },
    )

    renderer.pass(
      RenderPassDescriptor {
        camera: sceneCamera,
        clear: Clear.colorDepth(Color(0.035, 0.045, 0.055), 1.0),
        depth: Depth.readWrite(),
        blend: Blend.opaque(),
        cull: .Back,
      },
      (pass): none => {
        drawShadowedScene(
          pass,
          resources!,
          sceneCamera.matrix(surface),
          lightMatrix,
          lightDirection,
        )
      },
    )
  })

  app.run() else error {
    println(error)
    return 1
  }

  return 0
}
