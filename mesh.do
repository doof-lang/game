import {
  NativeColorMesh,
  NativeColorMeshBuilder,
  drawNativeColorMesh,
} from "./native"
import { GameSurface } from "./surface"
import { Color, Mat4, Point3, RenderPass } from "./render"

export class ColorMesh {
  private readonly native: NativeColorMesh

  vertexCount(): int => native.vertexCount()
  indexCount(): int => native.indexCount()
}

export class ColorMeshBuilder {
  private readonly native: NativeColorMeshBuilder

  static create(): ColorMeshBuilder {
    return ColorMeshBuilder { native: NativeColorMeshBuilder.create() }
  }

  addVertex(position: Point3, color: Color): int {
    return native.addVertex(
      position.x,
      position.y,
      position.z,
      color.r,
      color.g,
      color.b,
      color.a,
    )
  }

  addIndexedTriangle(a: int, b: int, c: int): ColorMeshBuilder {
    native.addTriangle(a, b, c)
    return this
  }

  addTriangle(a: Point3, b: Point3, c: Point3, color: Color): ColorMeshBuilder {
    ai := addVertex(a, color)
    bi := addVertex(b, color)
    ci := addVertex(c, color)
    return addIndexedTriangle(ai, bi, ci)
  }

  addQuad(a: Point3, b: Point3, c: Point3, d: Point3, color: Color): ColorMeshBuilder {
    ai := addVertex(a, color)
    bi := addVertex(b, color)
    ci := addVertex(c, color)
    di := addVertex(d, color)
    addIndexedTriangle(ai, bi, ci)
    return addIndexedTriangle(ai, ci, di)
  }

  build(surface: GameSurface): Result<ColorMesh, string> {
    return case native.build(surface.metalDeviceHandle()) {
      s: Success -> Success {
        value: ColorMesh { native: s.value }
      },
      f: Failure -> Failure {
        error: f.error
      }
    }
  }
}

export function drawColorMesh(
  pass: RenderPass,
  mesh: ColorMesh,
  model: Mat4 = Mat4 {
    m00: 1.0, m01: 0.0, m02: 0.0, m03: 0.0,
    m10: 0.0, m11: 1.0, m12: 0.0, m13: 0.0,
    m20: 0.0, m21: 0.0, m22: 1.0, m23: 0.0,
    m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
  },
): void {
  mvp := pass.camera().matrix(pass.surface()).multiply(model)
  drawNativeColorMesh(
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
