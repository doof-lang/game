import {
  NativeSimpleMesh,
  NativeSimpleMeshBuilder,
  drawNativeSimpleMesh,
  drawNativeTexturedSimpleMesh,
} from "./native"
import { GameSurface } from "./surface"
import { Color, Mat4, Point, Point3, RenderPass, Texture } from "./render"
import { Vec3 } from "./transform"

export struct Vec2 {
  readonly x: double
  readonly y: double

  static readonly zero = Vec2 { x: 0.0, y: 0.0 }
  static readonly one = Vec2 { x: 1.0, y: 1.0 }

  static xy(x: double, y: double): Vec2 {
    return Vec2 { x: x, y: y }
  }
}

export class MeshUv {
  readonly a: Point
  readonly b: Point
  readonly c: Point
  readonly d: Point

  static zero(): MeshUv {
    return MeshUv {
      a: Point(0.0, 0.0),
      b: Point(0.0, 0.0),
      c: Point(0.0, 0.0),
      d: Point(0.0, 0.0),
    }
  }

  static unit(): MeshUv {
    return MeshUv.rect(0.0, 0.0, 1.0, 1.0)
  }

  static rect(u0: double, v0: double, u1: double, v1: double): MeshUv {
    return MeshUv {
      a: Point(u0, v0),
      b: Point(u1, v0),
      c: Point(u1, v1),
      d: Point(u0, v1),
    }
  }
}

export class SimpleMeshSpec {
  positions: Point3[]
  indices: int[]
  colors: Color[]
  uvs: Point[]
  normals: Point3[]

  vertexCount(): int => positions.length
  indexCount(): int => indices.length
}

export class SimpleMeshLighting {
  ambient: double = 0.25
  directional: double = 0.75
  direction: Point3 = Point3(0.35, 0.60, 0.72)
}

export class SimpleMaterial {
  tint: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }
  whiteBlend: double = 0.0
  uvOffset: Vec2 = Vec2 { x: 0.0, y: 0.0 }
  uvScale: Vec2 = Vec2 { x: 1.0, y: 1.0 }
  specular: double = 0.0
  shininess: double = 32.0
  fresnel: double = 0.0
  fresnelPower: double = 5.0
}

export class SimpleMesh {
  private readonly native: NativeSimpleMesh

  static constructor(surface: GameSurface, spec: SimpleMeshSpec): SimpleMesh {
    if spec.positions.length == 0 {
      panic("Simple mesh has no vertices")
    }

    if spec.indices.length == 0 {
      panic("Simple mesh has no triangles")
    }

    if spec.indices.length % 3 != 0 {
      panic("Simple mesh index count must be divisible by 3")
    }

    if spec.colors.length != spec.positions.length {
      panic("Simple mesh colors length must match positions length")
    }

    if spec.uvs.length != spec.positions.length {
      panic("Simple mesh uvs length must match positions length")
    }

    if spec.normals.length != spec.positions.length {
      panic("Simple mesh normals length must match positions length")
    }

    nativeBuilder := NativeSimpleMeshBuilder.create()
    for index of 0..<spec.positions.length {
      position := spec.positions[index]
      color := spec.colors[index]
      uv := spec.uvs[index]
      normal := spec.normals[index]
      nativeBuilder.addVertex(
        position.x,
        position.y,
        position.z,
        color.r,
        color.g,
        color.b,
        color.a,
        uv.x,
        uv.y,
        normal.x,
        normal.y,
        normal.z,
      )
    }

    let index = 0
    while index < spec.indices.length {
      nativeBuilder.addTriangle(
        spec.indices[index],
        spec.indices[index + 1],
        spec.indices[index + 2],
      )
      index += 3
    }

    native := try! nativeBuilder.build(surface.metalDeviceHandle())
    return SimpleMesh { native: native }
  }

  vertexCount(): int => native.vertexCount()
  indexCount(): int => native.indexCount()
  nativeSimpleMesh(): NativeSimpleMesh => native
}

export class SimpleMeshBuilder {
  private positions: Point3[] = []
  private indices: int[] = []
  private colors: Color[] = []
  private uvs: Point[] = []
  private normals: Point3[] = []

  vertex(
    position: Point3,
    color: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
    uv: Point = Point { x: 0.0, y: 0.0 },
    normal: Point3 = Point3 { x: 0.0, y: 0.0, z: 1.0 },
  ): int {
    positions.push(position)
    colors.push(color)
    uvs.push(uv)
    normals.push(normal)
    return positions.length - 1
  }

  triangle(a: int, b: int, c: int): SimpleMeshBuilder {
    indices.push(a)
    indices.push(b)
    indices.push(c)
    return this
  }

  quad(
    a: Point3,
    b: Point3,
    c: Point3,
    d: Point3,
    color: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
    normal: Point3 = Point3 { x: 0.0, y: 0.0, z: 1.0 },
    uvA: Point = Point { x: 0.0, y: 0.0 },
    uvB: Point = Point { x: 0.0, y: 0.0 },
    uvC: Point = Point { x: 0.0, y: 0.0 },
    uvD: Point = Point { x: 0.0, y: 0.0 },
  ): SimpleMeshBuilder {
    ai := vertex{ position: a, color: color, uv: uvA, normal: normal }
    bi := vertex{ position: b, color: color, uv: uvB, normal: normal }
    ci := vertex{ position: c, color: color, uv: uvC, normal: normal }
    di := vertex{ position: d, color: color, uv: uvD, normal: normal }
    triangle(ai, bi, ci)
    return triangle(ai, ci, di)
  }

  quadUv(
    a: Point3,
    b: Point3,
    c: Point3,
    d: Point3,
    color: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
    normal: Point3 = Point3 { x: 0.0, y: 0.0, z: 1.0 },
    uv: MeshUv = MeshUv.unit(),
  ): SimpleMeshBuilder {
    return quad{
      a,
      b,
      c,
      d,
      color,
      normal,
      uvA: uv.a,
      uvB: uv.b,
      uvC: uv.c,
      uvD: uv.d,
    }
  }

  box(
    center: Point3,
    size: Vec3,
    color: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
    uv: MeshUv = MeshUv.unit(),
  ): SimpleMeshBuilder {
    halfX := size.x * 0.5
    halfY := size.y * 0.5
    halfZ := size.z * 0.5
    return boxFromBounds{
      min: Point3(center.x - halfX, center.y - halfY, center.z - halfZ),
      max: Point3(center.x + halfX, center.y + halfY, center.z + halfZ),
      color,
      uv,
    }
  }

  boxFromBounds(
    min: Point3,
    max: Point3,
    color: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
    uv: MeshUv = MeshUv.unit(),
  ): SimpleMeshBuilder {
    p000 := Point3(min.x, min.y, min.z)
    p001 := Point3(min.x, min.y, max.z)
    p010 := Point3(min.x, max.y, min.z)
    p011 := Point3(min.x, max.y, max.z)
    p100 := Point3(max.x, min.y, min.z)
    p101 := Point3(max.x, min.y, max.z)
    p110 := Point3(max.x, max.y, min.z)
    p111 := Point3(max.x, max.y, max.z)

    quadUv(p001, p101, p111, p011, color, Point3(0.0, 0.0, 1.0), uv)
    quadUv(p100, p000, p010, p110, color, Point3(0.0, 0.0, -1.0), uv)
    quadUv(p000, p001, p011, p010, color, Point3(-1.0, 0.0, 0.0), uv)
    quadUv(p101, p100, p110, p111, color, Point3(1.0, 0.0, 0.0), uv)
    quadUv(p010, p011, p111, p110, color, Point3(0.0, 1.0, 0.0), uv)
    return quadUv(p000, p100, p101, p001, color, Point3(0.0, -1.0, 0.0), uv)
  }

  append(spec: SimpleMeshSpec): SimpleMeshBuilder {
    return appendTranslated(spec, Point3(0.0, 0.0, 0.0))
  }

  appendTranslated(spec: SimpleMeshSpec, offset: Point3): SimpleMeshBuilder {
    base := positions.length
    for index of 0..<spec.positions.length {
      position := spec.positions[index]
      vertex{
        position: Point3(position.x + offset.x, position.y + offset.y, position.z + offset.z),
        color: spec.colors[index],
        uv: spec.uvs[index],
        normal: spec.normals[index],
      }
    }

    let index = 0
    while index < spec.indices.length {
      triangle(
        spec.indices[index] + base,
        spec.indices[index + 1] + base,
        spec.indices[index + 2] + base,
      )
      index += 3
    }

    return this
  }

  buildSpec(): SimpleMeshSpec {
    return {
      positions: positions.slice(0, positions.length),
      indices: indices.slice(0, indices.length),
      colors: colors.slice(0, colors.length),
      uvs: uvs.slice(0, uvs.length),
      normals: normals.slice(0, normals.length),
    }
  }

  build(surface: GameSurface): SimpleMesh {
    return SimpleMesh(surface, buildSpec())
  }
}

export function drawSimpleMesh(
  pass: RenderPass,
  mesh: SimpleMesh,
  model: Mat4 = Mat4 {
    m00: 1.0, m01: 0.0, m02: 0.0, m03: 0.0,
    m10: 0.0, m11: 1.0, m12: 0.0, m13: 0.0,
    m20: 0.0, m21: 0.0, m22: 1.0, m23: 0.0,
    m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
  },
  material: SimpleMaterial = SimpleMaterial {},
  lighting: SimpleMeshLighting = SimpleMeshLighting {},
): none {
  viewProjection := pass.camera().matrix(pass.surface())
  normal := model.toNormalMat3()
  eye := pass.camera().transform.position
  drawNativeSimpleMesh(
    mesh.native,
    pass.metalRenderCommandEncoderHandle(),
    pass.metalDeviceHandle(),
    pass.nativeBlendModeCode(),
    pass.hasColorAttachment(),
    pass.hasDepthAttachment(),
    viewProjection.m00,
    viewProjection.m01,
    viewProjection.m02,
    viewProjection.m03,
    viewProjection.m10,
    viewProjection.m11,
    viewProjection.m12,
    viewProjection.m13,
    viewProjection.m20,
    viewProjection.m21,
    viewProjection.m22,
    viewProjection.m23,
    viewProjection.m30,
    viewProjection.m31,
    viewProjection.m32,
    viewProjection.m33,
    model.m00,
    model.m01,
    model.m02,
    model.m03,
    model.m10,
    model.m11,
    model.m12,
    model.m13,
    model.m20,
    model.m21,
    model.m22,
    model.m23,
    model.m30,
    model.m31,
    model.m32,
    model.m33,
    normal.m00,
    normal.m01,
    normal.m02,
    normal.m10,
    normal.m11,
    normal.m12,
    normal.m20,
    normal.m21,
    normal.m22,
    lighting.ambient,
    lighting.directional,
    lighting.direction.x,
    lighting.direction.y,
    lighting.direction.z,
    eye.x,
    eye.y,
    eye.z,
    material.tint.r,
    material.tint.g,
    material.tint.b,
    material.tint.a,
    material.whiteBlend,
    material.uvOffset.x,
    material.uvOffset.y,
    material.uvScale.x,
    material.uvScale.y,
    material.specular,
    material.shininess,
    material.fresnel,
    material.fresnelPower,
  )
}

export function drawTexturedSimpleMesh(
  pass: RenderPass,
  mesh: SimpleMesh,
  texture: Texture,
  model: Mat4 = Mat4 {
    m00: 1.0, m01: 0.0, m02: 0.0, m03: 0.0,
    m10: 0.0, m11: 1.0, m12: 0.0, m13: 0.0,
    m20: 0.0, m21: 0.0, m22: 1.0, m23: 0.0,
    m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
  },
  material: SimpleMaterial = SimpleMaterial {},
  lighting: SimpleMeshLighting = SimpleMeshLighting {},
): none {
  viewProjection := pass.camera().matrix(pass.surface())
  normal := model.toNormalMat3()
  eye := pass.camera().transform.position
  drawNativeTexturedSimpleMesh(
    mesh.native,
    texture.metalTextureHandle(),
    pass.metalRenderCommandEncoderHandle(),
    pass.metalDeviceHandle(),
    pass.nativeBlendModeCode(),
    pass.hasColorAttachment(),
    pass.hasDepthAttachment(),
    viewProjection.m00,
    viewProjection.m01,
    viewProjection.m02,
    viewProjection.m03,
    viewProjection.m10,
    viewProjection.m11,
    viewProjection.m12,
    viewProjection.m13,
    viewProjection.m20,
    viewProjection.m21,
    viewProjection.m22,
    viewProjection.m23,
    viewProjection.m30,
    viewProjection.m31,
    viewProjection.m32,
    viewProjection.m33,
    model.m00,
    model.m01,
    model.m02,
    model.m03,
    model.m10,
    model.m11,
    model.m12,
    model.m13,
    model.m20,
    model.m21,
    model.m22,
    model.m23,
    model.m30,
    model.m31,
    model.m32,
    model.m33,
    normal.m00,
    normal.m01,
    normal.m02,
    normal.m10,
    normal.m11,
    normal.m12,
    normal.m20,
    normal.m21,
    normal.m22,
    lighting.ambient,
    lighting.directional,
    lighting.direction.x,
    lighting.direction.y,
    lighting.direction.z,
    eye.x,
    eye.y,
    eye.z,
    material.tint.r,
    material.tint.g,
    material.tint.b,
    material.tint.a,
    material.whiteBlend,
    material.uvOffset.x,
    material.uvOffset.y,
    material.uvScale.x,
    material.uvScale.y,
    material.specular,
    material.shininess,
    material.fresnel,
    material.fresnelPower,
  )
}
