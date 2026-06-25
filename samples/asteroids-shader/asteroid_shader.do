import { BlobBuilder } from "std/blob"
import { readTextResource } from "std/fs"
import { floor, sin } from "std/math"
import {
  GameSurface,
  Mat4,
  RenderPass,
  SimpleMeshSpec,
  ShaderBuffer,
  ShaderBufferBinding,
  ShaderBytesBinding,
  ShaderDraw,
  ShaderPipeline,
  ShaderPipelineDescriptor,
  ShaderVertexAttribute,
  ShaderVertexFormat,
  ShaderVertexLayout,
  ShaderVertexStepFunction,
  Vec3,
  createIcosphereMeshSpec,
  drawShader,
} from "std/game"
const ASTEROID_COUNT = 72
const ASTEROID_SUBDIVISIONS = 2
const ASTEROID_VERTEX_STRIDE = 28
const ASTEROID_INSTANCE_STRIDE = 64
const ASTEROID_SHADER_PATH = "shaders/asteroid.metal"

export class AsteroidShaderResources {
  readonly pipeline: ShaderPipeline
  readonly vertexBuffer: ShaderBuffer
  readonly indexBuffer: ShaderBuffer
  readonly instanceBuffer: ShaderBuffer
  readonly indexCount: int
}

function randomUnit(index: int, salt: double): double {
  value := sin((double(index) + 1.0) * 12.9898 + salt * 78.233) * 43758.5453123
  return value - floor(value)
}

function randomSigned(index: int, salt: double): double {
  return randomUnit(index, salt) * 2.0 - 1.0
}

function writeFloat3(builder: BlobBuilder, x: double, y: double, z: double): void {
  builder.writeFloat(float(x))
  builder.writeFloat(float(y))
  builder.writeFloat(float(z))
}

function writeAsteroidVertex(builder: BlobBuilder, spec: SimpleMeshSpec, index: int): void {
  position := spec.positions[index]
  normal := spec.normals[index]
  writeFloat3(builder, position.x, position.y, position.z)
  writeFloat3(builder, normal.x, normal.y, normal.z)
  vertexSeed := normal.x * 0.41 + normal.y * 1.37 + normal.z * 2.11
  builder.writeFloat(float(vertexSeed))
}

function createAsteroidGeometry(): SimpleMeshSpec {
  return createIcosphereMeshSpec{ subdivisions: ASTEROID_SUBDIVISIONS }
}

function asteroidVertexBytes(geometry: SimpleMeshSpec): readonly byte[] {
  builder := BlobBuilder {}
  for index of 0..<geometry.positions.length {
    writeAsteroidVertex(builder, geometry, index)
  }
  return builder.build()
}

function asteroidIndexBytes(geometry: SimpleMeshSpec): readonly byte[] {
  builder := BlobBuilder {}
  for index of geometry.indices {
    builder.writeUnsignedInt(index)
  }
  return builder.build()
}

function asteroidInstanceBytes(): readonly byte[] {
  builder := BlobBuilder {}
  for index of 0..<ASTEROID_COUNT {
    ring := double(index) / double(ASTEROID_COUNT)
    radius := 4.0 + randomUnit(index, 0.2) * 7.5
    angle := ring * 6.28318530718
    centerX := sin(angle) * radius
    centerY := randomSigned(index, 1.6) * 1.8
    centerZ := -7.0 - randomUnit(index, 2.7) * 11.0 - sin(angle + 1.4) * 2.0
    size := 0.18 + randomUnit(index, 3.1) * 0.55
    axis := Vec3.toNormalized(randomSigned(index, 4.2), randomSigned(index, 5.3), randomSigned(index, 6.4))
    spinSpeed := 0.25 + randomUnit(index, 7.5) * 1.55
    orbitPhase := angle + randomUnit(index, 8.6) * 1.2
    noiseSeed := randomUnit(index, 9.7) * 40.0
    warm := randomUnit(index, 10.8)

    writeFloat3(builder, centerX, centerY, centerZ)
    builder.writeFloat(float(size))
    writeFloat3(builder, axis.x, axis.y, axis.z)
    builder.writeFloat(float(spinSpeed))
    builder.writeFloat(float(orbitPhase))
    builder.writeFloat(float(noiseSeed))
    builder.writeFloat(float(0.42 + warm * 0.28))
    builder.writeFloat(0.0f)
    builder.writeFloat(float(0.37 + warm * 0.12))
    builder.writeFloat(float(0.31 + randomUnit(index, 11.9) * 0.18))
    builder.writeFloat(0.0f)
    builder.writeFloat(0.0f)
  }
  return builder.build()
}

function writeMat4Rows(builder: BlobBuilder, matrix: Mat4): void {
  builder.writeFloat(float(matrix.m00)); builder.writeFloat(float(matrix.m01)); builder.writeFloat(float(matrix.m02)); builder.writeFloat(float(matrix.m03))
  builder.writeFloat(float(matrix.m10)); builder.writeFloat(float(matrix.m11)); builder.writeFloat(float(matrix.m12)); builder.writeFloat(float(matrix.m13))
  builder.writeFloat(float(matrix.m20)); builder.writeFloat(float(matrix.m21)); builder.writeFloat(float(matrix.m22)); builder.writeFloat(float(matrix.m23))
  builder.writeFloat(float(matrix.m30)); builder.writeFloat(float(matrix.m31)); builder.writeFloat(float(matrix.m32)); builder.writeFloat(float(matrix.m33))
}

function uniformsBytes(viewProjection: Mat4, time: double): readonly byte[] {
  builder := BlobBuilder {}
  writeMat4Rows(builder, viewProjection)
  builder.writeFloat(float(time))
  builder.writeFloat(0.0f)
  builder.writeFloat(float(ASTEROID_COUNT))
  builder.writeFloat(0.0f)
  return builder.build()
}

function asteroidShaderSource(): string {
  return try! readTextResource(ASTEROID_SHADER_PATH)
}

export function createAsteroidShaderResources(surface: GameSurface): AsteroidShaderResources {
  pipeline := try! ShaderPipeline.create(
    surface,
    ShaderPipelineDescriptor {
      source: asteroidShaderSource(),
      vertexFunction: "asteroid_vertex",
      fragmentFunction: "asteroid_fragment",
      attributes: [
        ShaderVertexAttribute { attribute: 0, buffer: 0, offset: 0, format: ShaderVertexFormat.Float3 },
        ShaderVertexAttribute { attribute: 1, buffer: 0, offset: 12, format: ShaderVertexFormat.Float3 },
        ShaderVertexAttribute { attribute: 2, buffer: 0, offset: 24, format: ShaderVertexFormat.Float },
        ShaderVertexAttribute { attribute: 3, buffer: 1, offset: 0, format: ShaderVertexFormat.Float4 },
        ShaderVertexAttribute { attribute: 4, buffer: 1, offset: 16, format: ShaderVertexFormat.Float4 },
        ShaderVertexAttribute { attribute: 5, buffer: 1, offset: 32, format: ShaderVertexFormat.Float4 },
        ShaderVertexAttribute { attribute: 6, buffer: 1, offset: 48, format: ShaderVertexFormat.Float4 },
      ],
      layouts: [
        ShaderVertexLayout { buffer: 0, stride: ASTEROID_VERTEX_STRIDE },
        ShaderVertexLayout {
          buffer: 1,
          stride: ASTEROID_INSTANCE_STRIDE,
          stepFunction: ShaderVertexStepFunction.PerInstance,
        },
      ],
    },
  )
  geometry := createAsteroidGeometry()
  vertexBuffer := try! ShaderBuffer.create(surface, asteroidVertexBytes(geometry))
  indexBuffer := try! ShaderBuffer.create(surface, asteroidIndexBytes(geometry))
  instanceBuffer := try! ShaderBuffer.create(surface, asteroidInstanceBytes())
  return AsteroidShaderResources {
    pipeline,
    vertexBuffer,
    indexBuffer,
    instanceBuffer,
    indexCount: geometry.indices.length,
  }
}

export function drawAsteroids(pass: RenderPass, resources: AsteroidShaderResources, viewProjection: Mat4, time: double): void {
  uniformBytes := uniformsBytes(viewProjection, time)
  uniforms := try! ShaderBytesBinding.create(pass.surface(), 2, uniformBytes)
  fragmentUniforms := try! ShaderBytesBinding.create(pass.surface(), 0, uniformBytes)
  try! drawShader(
    pass,
    ShaderDraw {
      pipeline: resources.pipeline,
      vertexBuffers: [
        ShaderBufferBinding { index: 0, buffer: resources.vertexBuffer },
        ShaderBufferBinding { index: 1, buffer: resources.instanceBuffer },
      ],
      indexBuffer: resources.indexBuffer,
      indexCount: resources.indexCount,
      instanceCount: ASTEROID_COUNT,
      vertexBytes: [uniforms],
      fragmentBytes: [fragmentUniforms],
    },
  )
}
