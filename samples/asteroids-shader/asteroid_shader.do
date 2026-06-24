import { BlobBuilder } from "std/blob"
import { readText } from "std/fs"
import { floor, sin, sqrt } from "std/math"
import { join, resourcesDirectory } from "std/path"
import {
  GameSurface,
  Mat4,
  Point3,
  RenderPass,
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

class AsteroidGeometry {
  vertices: Point3[] = []
  indices: int[] = []
}

function randomUnit(index: int, salt: double): double {
  value := sin((double(index) + 1.0) * 12.9898 + salt * 78.233) * 43758.5453123
  return value - floor(value)
}

function randomSigned(index: int, salt: double): double {
  return randomUnit(index, salt) * 2.0 - 1.0
}

function normalizePoint(point: Point3): Point3 {
  length := sqrt(point.x * point.x + point.y * point.y + point.z * point.z)
  return Point3(point.x / length, point.y / length, point.z / length)
}

function writeFloat3(builder: BlobBuilder, x: double, y: double, z: double): void {
  builder.writeFloat(float(x))
  builder.writeFloat(float(y))
  builder.writeFloat(float(z))
}

function writeAsteroidVertex(builder: BlobBuilder, point: Point3): void {
  normal := normalizePoint(point)
  writeFloat3(builder, normal.x, normal.y, normal.z)
  writeFloat3(builder, normal.x, normal.y, normal.z)
  vertexSeed := normal.x * 0.41 + normal.y * 1.37 + normal.z * 2.11
  builder.writeFloat(float(vertexSeed))
}

function midpoint(a: Point3, b: Point3): Point3 {
  return Point3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5)
}

function addAsteroidVertex(geometry: AsteroidGeometry, point: Point3): int {
  geometry.vertices.push(normalizePoint(point))
  return geometry.vertices.length - 1
}

function asteroidEdgeKey(a: int, b: int): long {
  let low = a
  let high = b
  if low > high {
    low = b
    high = a
  }
  return long(low) * 1_000_000L + long(high)
}

function midpointIndex(geometry: AsteroidGeometry, midpointCache: Map<long, int>, a: int, b: int): int {
  key := asteroidEdgeKey(a, b)
  cached := midpointCache.get(key) else {
    point := midpoint(geometry.vertices[a], geometry.vertices[b])
    index := addAsteroidVertex(geometry, point)
    midpointCache.set(key, index)
    return index
  }
  return cached
}

function addRawTriangle(geometry: AsteroidGeometry, a: int, b: int, c: int): void {
  geometry.indices.push(a)
  geometry.indices.push(b)
  geometry.indices.push(c)
}

function addSubdividedTriangle(geometry: AsteroidGeometry, midpointCache: Map<long, int>, a: int, b: int, c: int, depth: int): void {
  if depth <= 0 {
    addRawTriangle(geometry, a, b, c)
    return
  }

  ab := midpointIndex(geometry, midpointCache, a, b)
  bc := midpointIndex(geometry, midpointCache, b, c)
  ca := midpointIndex(geometry, midpointCache, c, a)
  next := depth - 1
  addSubdividedTriangle(geometry, midpointCache, a, ab, ca, next)
  addSubdividedTriangle(geometry, midpointCache, ab, b, bc, next)
  addSubdividedTriangle(geometry, midpointCache, ca, bc, c, next)
  addSubdividedTriangle(geometry, midpointCache, ab, bc, ca, next)
}

function addTriangle(geometry: AsteroidGeometry, midpointCache: Map<long, int>, a: int, b: int, c: int): void {
  addSubdividedTriangle(geometry, midpointCache, a, b, c, ASTEROID_SUBDIVISIONS)
}

function addIcosahedronVertices(geometry: AsteroidGeometry): void {
  phi := 1.61803398875
  vertices := [
    Point3(-1.0, phi, 0.0),
    Point3(1.0, phi, 0.0),
    Point3(-1.0, -phi, 0.0),
    Point3(1.0, -phi, 0.0),
    Point3(0.0, -1.0, phi),
    Point3(0.0, 1.0, phi),
    Point3(0.0, -1.0, -phi),
    Point3(0.0, 1.0, -phi),
    Point3(phi, 0.0, -1.0),
    Point3(phi, 0.0, 1.0),
    Point3(-phi, 0.0, -1.0),
    Point3(-phi, 0.0, 1.0),
  ]
  for vertex of vertices {
    addAsteroidVertex(geometry, vertex)
  }
}

function addIcosahedronFaces(geometry: AsteroidGeometry, midpointCache: Map<long, int>): void {
  faces := [
    0, 11, 5,
    0, 5, 1,
    0, 1, 7,
    0, 7, 10,
    0, 10, 11,
    1, 5, 9,
    5, 11, 4,
    11, 10, 2,
    10, 7, 6,
    7, 1, 8,
    3, 9, 4,
    3, 4, 2,
    3, 2, 6,
    3, 6, 8,
    3, 8, 9,
    4, 9, 5,
    2, 4, 11,
    6, 2, 10,
    8, 6, 7,
    9, 8, 1,
  ]

  let index = 0
  while index < faces.length {
    addTriangle(geometry, midpointCache, faces[index], faces[index + 1], faces[index + 2])
    index += 3
  }
}

function createAsteroidGeometry(): AsteroidGeometry {
  geometry := AsteroidGeometry {}
  midpointCache: Map<long, int> := {}
  addIcosahedronVertices(geometry)
  addIcosahedronFaces(geometry, midpointCache)
  return geometry
}

function asteroidVertexBytes(geometry: AsteroidGeometry): readonly byte[] {
  builder := BlobBuilder {}
  for vertex of geometry.vertices {
    writeAsteroidVertex(builder, vertex)
  }
  return builder.build()
}

function asteroidIndexBytes(geometry: AsteroidGeometry): readonly byte[] {
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
  resources := try! resourcesDirectory()
  return try! readText(join([resources, ASTEROID_SHADER_PATH]))
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
