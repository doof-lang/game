import {
  NativeSimpleMesh,
  NativeSimpleMeshBuilder,
  drawNativeSimpleMesh,
  drawNativeTexturedSimpleMesh,
} from "./native"
import { GameSurface } from "./surface"
import { Color, Mat4, Point, Point3, RenderPass, Texture } from "./render"

export class SimpleMeshSpec {
  positions: Point3[]
  indices: int[]
  colors: Color[]
  uvs: Point[]
  normals: Point3[]

  vertexCount(): int => positions.length
  indexCount(): int => indices.length
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

  static create(): SimpleMeshBuilder {
    return SimpleMeshBuilder {}
  }

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
    ai := this.vertex{ position: a, color: color, uv: uvA, normal: normal }
    bi := this.vertex{ position: b, color: color, uv: uvB, normal: normal }
    ci := this.vertex{ position: c, color: color, uv: uvC, normal: normal }
    di := this.vertex{ position: d, color: color, uv: uvD, normal: normal }
    triangle(ai, bi, ci)
    return triangle(ai, ci, di)
  }

  buildSpec(): SimpleMeshSpec {
    return SimpleMeshSpec {
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
): void {
  mvp := pass.camera().matrix(pass.surface()).multiply(model)
  drawNativeSimpleMesh(
    mesh.native,
    pass.metalRenderCommandEncoderHandle(),
    pass.metalDeviceHandle(),
    pass.nativeBlendModeCode(),
    pass.hasDepthAttachment(),
    mvp.m00,
    mvp.m01,
    mvp.m02,
    mvp.m03,
    mvp.m10,
    mvp.m11,
    mvp.m12,
    mvp.m13,
    mvp.m20,
    mvp.m21,
    mvp.m22,
    mvp.m23,
    mvp.m30,
    mvp.m31,
    mvp.m32,
    mvp.m33,
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
): void {
  mvp := pass.camera().matrix(pass.surface()).multiply(model)
  drawNativeTexturedSimpleMesh(
    mesh.native,
    texture.metalTextureHandle(),
    pass.metalRenderCommandEncoderHandle(),
    pass.metalDeviceHandle(),
    pass.nativeBlendModeCode(),
    pass.hasDepthAttachment(),
    mvp.m00,
    mvp.m01,
    mvp.m02,
    mvp.m03,
    mvp.m10,
    mvp.m11,
    mvp.m12,
    mvp.m13,
    mvp.m20,
    mvp.m21,
    mvp.m22,
    mvp.m23,
    mvp.m30,
    mvp.m31,
    mvp.m32,
    mvp.m33,
  )
}
