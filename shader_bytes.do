import { BlobBuilder } from "std/blob"

import { Vec2 } from "./mesh"
import { Color, Mat4, Point, Point3 } from "./render"
import { Vec3 } from "./transform"

export class ShaderBytesBuilder {
  private readonly builder: BlobBuilder

  static constructor(size: long = 0L): ShaderBytesBuilder {
    return ShaderBytesBuilder {
      builder: BlobBuilder(size),
    }
  }

  position(): long => builder.getPosition()
  byteLength(): long => builder.length()

  align(width: long): ShaderBytesBuilder {
    builder.align(width)
    return this
  }

  zeroes(length: long): ShaderBytesBuilder {
    builder.writeZeroes(length)
    return this
  }

  float32(value: double): ShaderBytesBuilder {
    builder.writeFloat(float(value))
    return this
  }

  rawFloat32(value: float): ShaderBytesBuilder {
    builder.writeFloat(value)
    return this
  }

  uint32(value: long): ShaderBytesBuilder {
    builder.writeUnsignedInt(value)
    return this
  }

  int32(value: int): ShaderBytesBuilder {
    builder.writeInt(value)
    return this
  }

  float2(x: double, y: double): ShaderBytesBuilder {
    builder.writeFloat(float(x))
    builder.writeFloat(float(y))
    return this
  }

  float3(x: double, y: double, z: double): ShaderBytesBuilder {
    builder.writeFloat(float(x))
    builder.writeFloat(float(y))
    builder.writeFloat(float(z))
    return this
  }

  float4(x: double, y: double, z: double, w: double): ShaderBytesBuilder {
    builder.writeFloat(float(x))
    builder.writeFloat(float(y))
    builder.writeFloat(float(z))
    builder.writeFloat(float(w))
    return this
  }

  point(value: Point): ShaderBytesBuilder {
    return float2(value.x, value.y)
  }

  point3(value: Point3): ShaderBytesBuilder {
    return float3(value.x, value.y, value.z)
  }

  vec2(value: Vec2): ShaderBytesBuilder {
    return float2(value.x, value.y)
  }

  vec3(value: Vec3): ShaderBytesBuilder {
    return float3(value.x, value.y, value.z)
  }

  color(value: Color): ShaderBytesBuilder {
    return float4(value.r, value.g, value.b, value.a)
  }

  mat4Rows(matrix: Mat4): ShaderBytesBuilder {
    float4(matrix.m00, matrix.m01, matrix.m02, matrix.m03)
    float4(matrix.m10, matrix.m11, matrix.m12, matrix.m13)
    float4(matrix.m20, matrix.m21, matrix.m22, matrix.m23)
    return float4(matrix.m30, matrix.m31, matrix.m32, matrix.m33)
  }

  paddingFloat32(count: int = 1): ShaderBytesBuilder {
    let written = 0
    while written < count {
      builder.writeFloat(0.0f)
      written += 1
    }
    return this
  }

  build(): readonly byte[] {
    return builder.build()
  }
}
