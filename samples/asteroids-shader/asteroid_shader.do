import { readTextResource } from "std/fs"
import { abs, floor, pow, sin } from "std/math"
import {
  Color,
  GameSurface,
  Mat4,
  Point3,
  RenderPass,
  SimpleMeshSpec,
  ShaderBuffer,
  ShaderBufferBinding,
  ShaderBytesBuilder,
  ShaderBytesBinding,
  ShaderDraw,
  ShaderPipeline,
  ShaderPipelineDescriptor,
  ShaderProgram,
  ShaderVertexAttribute,
  ShaderVertexFormat,
  ShaderVertexLayout,
  ShaderVertexStepFunction,
  Vec3,
  createIcosphereMeshSpec,
  drawShader,
} from "std/game"

readonly ASTEROID_COUNT = 900
readonly ASTEROID_SUBDIVISIONS = 4
readonly ASTEROID_VERTEX_STRIDE = 12
readonly ASTEROID_INSTANCE_STRIDE = 64
readonly BACKDROP_VERTEX_STRIDE = 8
readonly SHADER_PATH = "shaders/asteroid.metal"

// The belt is a flattened ring around the planet at the origin. The camera
// flies along its middle, so a tunnel around that path is kept clear.
export readonly BELT_RADIUS = 34.0
readonly BELT_HALF_WIDTH = 9.0
readonly BELT_HALF_HEIGHT = 2.6
export readonly CAMERA_HEIGHT = 0.4
readonly PLANET_RADIUS = 15.0

// Angular speed of a rock at radius r is KEPLER / r^1.5: inner rocks overtake outer ones.
readonly KEPLER = 2.2

export class Sun {
  readonly direction: Vec3
  readonly color: Color
  readonly exposure: double
}

export class AsteroidShaderResources {
  readonly asteroidPipeline: ShaderPipeline
  readonly backdropPipeline: ShaderPipeline
  readonly vertexBuffer: ShaderBuffer
  readonly indexBuffer: ShaderBuffer
  readonly instanceBuffer: ShaderBuffer
  readonly backdropBuffer: ShaderBuffer
  readonly indexCount: int
}

class RockType {
  readonly albedo: Color
  readonly metallic: double
}

readonly CARBON = RockType { albedo: Color(0.20, 0.19, 0.18), metallic: 0.0 }
readonly SILICATE = RockType { albedo: Color(0.52, 0.44, 0.36), metallic: 0.1 }
readonly IRON = RockType { albedo: Color(0.46, 0.38, 0.33), metallic: 0.85 }
readonly ICE = RockType { albedo: Color(0.66, 0.72, 0.80), metallic: 0.35 }

function randomUnit(index: int, salt: double): double {
  value := sin((double(index) + 1.0) * 12.9898 + salt * 78.233) * 43758.5453123
  return value - floor(value)
}

function randomSigned(index: int, salt: double): double {
  return randomUnit(index, salt) * 2.0 - 1.0
}

// Roughly bell-shaped in -1..1, so rocks bunch toward the middle of the belt.
function randomBell(index: int, salt: double): double {
  return (randomSigned(index, salt) + randomSigned(index, salt + 0.5) + randomSigned(index, salt + 0.9)) / 3.0
}

function rockType(index: int): RockType {
  roll := randomUnit(index, 12.3)
  if roll < 0.45 {
    return CARBON
  }
  if roll < 0.80 {
    return SILICATE
  }
  if roll < 0.95 {
    return IRON
  }
  return ICE
}

function asteroidVertexBytes(geometry: SimpleMeshSpec): readonly byte[] {
  builder := ShaderBytesBuilder()
  for position of geometry.positions {
    builder.point3(position)
  }
  return builder.build()
}

function asteroidIndexBytes(geometry: SimpleMeshSpec): readonly byte[] {
  builder := ShaderBytesBuilder()
  for index of geometry.indices {
    builder.uint32(index)
  }
  return builder.build()
}

function asteroidInstanceBytes(): readonly byte[] {
  builder := ShaderBytesBuilder()
  for index of 0..<ASTEROID_COUNT {
    // Mostly pebbles, with the occasional boulder.
    size := 0.08 + pow(randomUnit(index, 3.1), 7.0) * 1.7
    let radius = BELT_RADIUS + randomBell(index, 0.2) * BELT_HALF_WIDTH
    height := randomBell(index, 1.6) * BELT_HALF_HEIGHT

    // Push rocks out of the camera's flight tunnel, scattering them so they
    // don't pile up along its wall.
    clearance := 1.3 + size * 1.6
    offset := radius - BELT_RADIUS
    if abs(offset) < clearance && abs(height - CAMERA_HEIGHT) < clearance {
      push := clearance + randomUnit(index, 14.6) * BELT_HALF_WIDTH * 0.7
      radius = if offset < 0.0 then BELT_RADIUS - push else BELT_RADIUS + push
    }

    angle := randomUnit(index, 0.7) * 6.28318530718
    orbitSpeed := KEPLER / pow(radius, 1.5)
    axis := Vec3.toNormalized(randomSigned(index, 4.2), randomSigned(index, 5.3), randomSigned(index, 6.4))
    spinSpeed := 0.1 + randomUnit(index, 7.5) * 0.9 / (0.5 + size)
    seed := randomUnit(index, 9.7) * 40.0
    stretchY := 0.62 + randomUnit(index, 10.8) * 0.38
    stretchZ := 0.55 + randomUnit(index, 11.9) * 0.45
    kind := rockType(index)
    tint := 0.85 + randomUnit(index, 13.4) * 0.3

    builder
      .float4(radius, angle, height, size)
      .float4(axis.x, axis.y, axis.z, spinSpeed)
      .float4(orbitSpeed, seed, stretchY, stretchZ)
      .float4(kind.albedo.r * tint, kind.albedo.g * tint, kind.albedo.b * tint, kind.metallic)
  }
  return builder.build()
}

// A single triangle that covers the whole screen.
function backdropVertexBytes(): readonly byte[] {
  return ShaderBytesBuilder()
    .float2(-1.0, -1.0)
    .float2(3.0, -1.0)
    .float2(-1.0, 3.0)
    .build()
}

function sceneUniformBytes(viewProjection: Mat4, cameraPosition: Point3, time: double, sun: Sun): readonly byte[] {
  return ShaderBytesBuilder()
    .mat4Rows(viewProjection)
    .mat4Rows(viewProjection.inverse())
    .float4(cameraPosition.x, cameraPosition.y, cameraPosition.z, time)
    .float4(sun.direction.x, sun.direction.y, sun.direction.z, 0.0)
    .float4(sun.color.r, sun.color.g, sun.color.b, sun.exposure)
    .float4(0.0, 0.0, 0.0, PLANET_RADIUS)
    .build()
}

function createPipeline(
  surface: GameSurface,
  source: string,
  vertexFunction: string,
  fragmentFunction: string,
  attributes: readonly ShaderVertexAttribute[],
  layouts: readonly ShaderVertexLayout[],
): ShaderPipeline {
  return ShaderPipeline(
    surface,
    ShaderPipelineDescriptor {
      program: ShaderProgram { vertexSource: source, vertexFunction, fragmentFunction },
      attributes,
      layouts,
    },
  )!
}

export function createAsteroidShaderResources(surface: GameSurface): AsteroidShaderResources {
  source := readTextResource(SHADER_PATH)!
  asteroidPipeline := createPipeline(
    surface,
    source,
    "asteroid_vertex",
    "asteroid_fragment",
    [
      ShaderVertexAttribute { attribute: 0, buffer: 0, offset: 0, format: ShaderVertexFormat.Float3 },
      ShaderVertexAttribute { attribute: 1, buffer: 1, offset: 0, format: ShaderVertexFormat.Float4 },
      ShaderVertexAttribute { attribute: 2, buffer: 1, offset: 16, format: ShaderVertexFormat.Float4 },
      ShaderVertexAttribute { attribute: 3, buffer: 1, offset: 32, format: ShaderVertexFormat.Float4 },
      ShaderVertexAttribute { attribute: 4, buffer: 1, offset: 48, format: ShaderVertexFormat.Float4 },
    ],
    [
      ShaderVertexLayout { buffer: 0, stride: ASTEROID_VERTEX_STRIDE },
      ShaderVertexLayout {
        buffer: 1,
        stride: ASTEROID_INSTANCE_STRIDE,
        stepFunction: ShaderVertexStepFunction.PerInstance,
      },
    ],
  )
  backdropPipeline := createPipeline(
    surface,
    source,
    "backdrop_vertex",
    "backdrop_fragment",
    [ShaderVertexAttribute { attribute: 0, buffer: 0, offset: 0, format: ShaderVertexFormat.Float2 }],
    [ShaderVertexLayout { buffer: 0, stride: BACKDROP_VERTEX_STRIDE }],
  )

  geometry := createIcosphereMeshSpec{ subdivisions: ASTEROID_SUBDIVISIONS }
  return AsteroidShaderResources {
    asteroidPipeline,
    backdropPipeline,
    vertexBuffer: ShaderBuffer.create(surface, asteroidVertexBytes(geometry))!,
    indexBuffer: ShaderBuffer.create(surface, asteroidIndexBytes(geometry))!,
    instanceBuffer: ShaderBuffer.create(surface, asteroidInstanceBytes())!,
    backdropBuffer: ShaderBuffer.create(surface, backdropVertexBytes())!,
    indexCount: geometry.indices.length,
  }
}

// Draws the sky, sun and planet, then every asteroid in one instanced call.
export function drawAsteroidField(
  pass: RenderPass,
  resources: AsteroidShaderResources,
  viewProjection: Mat4,
  cameraPosition: Point3,
  time: double,
  sun: Sun,
): none {
  bytes := sceneUniformBytes(viewProjection, cameraPosition, time, sun)
  fragmentScene := ShaderBytesBinding.create(pass.surface(), 0, bytes)!

  drawShader(
    pass,
    ShaderDraw {
      pipeline: resources.backdropPipeline,
      vertexBuffers: [ShaderBufferBinding { index: 0, buffer: resources.backdropBuffer }],
      vertexCount: 3,
      fragmentBytes: [fragmentScene],
    },
  )!

  drawShader(
    pass,
    ShaderDraw {
      pipeline: resources.asteroidPipeline,
      vertexBuffers: [
        ShaderBufferBinding { index: 0, buffer: resources.vertexBuffer },
        ShaderBufferBinding { index: 1, buffer: resources.instanceBuffer },
      ],
      indexBuffer: resources.indexBuffer,
      indexCount: resources.indexCount,
      instanceCount: ASTEROID_COUNT,
      vertexBytes: [ShaderBytesBinding.create(pass.surface(), 2, bytes)!],
      fragmentBytes: [fragmentScene],
    },
  )!
}
