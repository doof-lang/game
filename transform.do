import { acos, cos, sin, sqrt, radians as toRadians } from "std/math"
import { Mat4, Point3 } from "./render"

readonly EPSILON = 0.000001

function clampUnit(value: double): double {
  if value < -1.0 {
    return -1.0
  }
  if value > 1.0 {
    return 1.0
  }
  return value
}

function safeScale(value: double, name: string): double {
  if value == 0.0 {
    panic("Transform normal matrix cannot invert zero " + name + " scale")
  }
  return value
}

export class Vec3 {
  readonly x: double
  readonly y: double
  readonly z: double

  static readonly zero = Vec3 { x: 0.0, y: 0.0, z: 0.0 }
  static readonly one = Vec3 { x: 1.0, y: 1.0, z: 1.0 }
  static readonly xAxis = Vec3 { x: 1.0, y: 0.0, z: 0.0 }
  static readonly yAxis = Vec3 { x: 0.0, y: 1.0, z: 0.0 }
  static readonly zAxis = Vec3 { x: 0.0, y: 0.0, z: 1.0 }
  static readonly forward = Vec3 { x: 0.0, y: 0.0, z: -1.0 }
  static readonly back = Vec3 { x: 0.0, y: 0.0, z: 1.0 }
  static readonly up = Vec3 { x: 0.0, y: 1.0, z: 0.0 }
  static readonly down = Vec3 { x: 0.0, y: -1.0, z: 0.0 }
  static readonly right = Vec3 { x: 1.0, y: 0.0, z: 0.0 }
  static readonly left = Vec3 { x: -1.0, y: 0.0, z: 0.0 }

  static xyz(x: double, y: double, z: double): Vec3 {
    return Vec3 { x: x, y: y, z: z }
  }

  static fromPoint(point: Point3): Vec3 {
    return Vec3.xyz(point.x, point.y, point.z)
  }

  static toNormalized(x: double, y: double, z: double): Vec3 {
    return Vec3.xyz(x, y, z).normalized()
  }

  toPoint3(): Point3 {
    return Point3(x, y, z)
  }

  plus(other: Vec3): Vec3 {
    return Vec3.xyz(x + other.x, y + other.y, z + other.z)
  }

  minus(other: Vec3): Vec3 {
    return Vec3.xyz(x - other.x, y - other.y, z - other.z)
  }

  times(factor: double): Vec3 {
    return Vec3.xyz(x * factor, y * factor, z * factor)
  }

  dividedBy(divisor: double): Vec3 {
    return Vec3.xyz(x / divisor, y / divisor, z / divisor)
  }

  dot(other: Vec3): double {
    return x * other.x + y * other.y + z * other.z
  }

  cross(other: Vec3): Vec3 {
    return Vec3.xyz(
      y * other.z - z * other.y,
      z * other.x - x * other.z,
      x * other.y - y * other.x,
    )
  }

  lengthSquared(): double {
    return dot(this)
  }

  length(): double {
    return sqrt(lengthSquared())
  }

  normalized(): Vec3 {
    len := length()
    if len <= EPSILON {
      return Vec3.zero
    }
    return dividedBy(len)
  }
}

export class Mat3 {
  readonly m00: double
  readonly m01: double
  readonly m02: double
  readonly m10: double
  readonly m11: double
  readonly m12: double
  readonly m20: double
  readonly m21: double
  readonly m22: double

  static identity(): Mat3 {
    return Mat3 {
      m00: 1.0, m01: 0.0, m02: 0.0,
      m10: 0.0, m11: 1.0, m12: 0.0,
      m20: 0.0, m21: 0.0, m22: 1.0,
    }
  }

  transformVector(vector: Vec3): Vec3 {
    return Vec3.xyz(
      m00 * vector.x + m01 * vector.y + m02 * vector.z,
      m10 * vector.x + m11 * vector.y + m12 * vector.z,
      m20 * vector.x + m21 * vector.y + m22 * vector.z,
    )
  }
}

export class Rotation {
  readonly qx: double
  readonly qy: double
  readonly qz: double
  readonly qw: double

  static readonly identity = Rotation { qx: 0.0, qy: 0.0, qz: 0.0, qw: 1.0 }

  static x(degrees: double): Rotation {
    return Rotation.axisAngle(Vec3.xAxis, degrees)
  }

  static y(degrees: double): Rotation {
    return Rotation.axisAngle(Vec3.yAxis, degrees)
  }

  static z(degrees: double): Rotation {
    return Rotation.axisAngle(Vec3.zAxis, degrees)
  }

  static axisAngle(axis: Vec3, degrees: double): Rotation {
    unit := axis.normalized()
    half := toRadians(degrees) * 0.5
    s := sin(half)
    return Rotation { qx: unit.x * s, qy: unit.y * s, qz: unit.z * s, qw: cos(half) }.normalized()
  }

  static euler(yaw: double = 0.0, pitch: double = 0.0, roll: double = 0.0): Rotation {
    return Rotation.y(yaw).andThen(Rotation.x(pitch)).andThen(Rotation.z(roll))
  }

  static lookAt(direction: Vec3, up: Vec3): Rotation {
    forward := direction.normalized()
    if forward.lengthSquared() <= EPSILON {
      return Rotation.identity
    }

    let right = forward.cross(up).normalized()
    if right.lengthSquared() <= EPSILON {
      right = forward.cross(Vec3.right).normalized()
    }
    if right.lengthSquared() <= EPSILON {
      right = forward.cross(Vec3.forward).normalized()
    }

    trueUp := right.cross(forward).normalized()
    return Rotation.fromBasis(right, trueUp, forward.times(-1.0))
  }

  static slerp(a: Rotation, b: Rotation, t: double): Rotation {
    let bx = b.qx
    let by = b.qy
    let bz = b.qz
    let bw = b.qw
    let dot = a.qx * bx + a.qy * by + a.qz * bz + a.qw * bw

    if dot < 0.0 {
      dot = -dot
      bx = -bx
      by = -by
      bz = -bz
      bw = -bw
    }

    if dot > 0.9995 {
      return Rotation {
        qx: a.qx + (bx - a.qx) * t,
        qy: a.qy + (by - a.qy) * t,
        qz: a.qz + (bz - a.qz) * t,
        qw: a.qw + (bw - a.qw) * t,
      }.normalized()
    }

    theta0 := acos(clampUnit(dot))
    theta := theta0 * t
    sinTheta := sin(theta)
    sinTheta0 := sin(theta0)
    s0 := cos(theta) - dot * sinTheta / sinTheta0
    s1 := sinTheta / sinTheta0

    return Rotation {
      qx: a.qx * s0 + bx * s1,
      qy: a.qy * s0 + by * s1,
      qz: a.qz * s0 + bz * s1,
      qw: a.qw * s0 + bw * s1,
    }.normalized()
  }

  private static fromBasis(right: Vec3, up: Vec3, back: Vec3): Rotation {
    trace := right.x + up.y + back.z
    if trace > 0.0 {
      s := sqrt(trace + 1.0) * 2.0
      return Rotation {
        qx: (up.z - back.y) / s,
        qy: (back.x - right.z) / s,
        qz: (right.y - up.x) / s,
        qw: 0.25 * s,
      }.normalized()
    }

    if right.x > up.y && right.x > back.z {
      s := sqrt(1.0 + right.x - up.y - back.z) * 2.0
      return Rotation {
        qx: 0.25 * s,
        qy: (up.x + right.y) / s,
        qz: (back.x + right.z) / s,
        qw: (up.z - back.y) / s,
      }.normalized()
    }

    if up.y > back.z {
      s := sqrt(1.0 + up.y - right.x - back.z) * 2.0
      return Rotation {
        qx: (up.x + right.y) / s,
        qy: 0.25 * s,
        qz: (back.y + up.z) / s,
        qw: (back.x - right.z) / s,
      }.normalized()
    }

    s := sqrt(1.0 + back.z - right.x - up.y) * 2.0
    return Rotation {
      qx: (back.x + right.z) / s,
      qy: (back.y + up.z) / s,
      qz: 0.25 * s,
      qw: (right.y - up.x) / s,
    }.normalized()
  }

  normalized(): Rotation {
    len := sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
    if len <= EPSILON {
      return Rotation.identity
    }
    return Rotation { qx: qx / len, qy: qy / len, qz: qz / len, qw: qw / len }
  }

  multiply(other: Rotation): Rotation {
    return Rotation {
      qx: qw * other.qx + qx * other.qw + qy * other.qz - qz * other.qy,
      qy: qw * other.qy - qx * other.qz + qy * other.qw + qz * other.qx,
      qz: qw * other.qz + qx * other.qy - qy * other.qx + qz * other.qw,
      qw: qw * other.qw - qx * other.qx - qy * other.qy - qz * other.qz,
    }.normalized()
  }

  andThen(next: Rotation): Rotation {
    return next.multiply(this)
  }

  inverse(): Rotation {
    norm := qx * qx + qy * qy + qz * qz + qw * qw
    if norm <= EPSILON {
      return Rotation.identity
    }
    return Rotation { qx: -qx / norm, qy: -qy / norm, qz: -qz / norm, qw: qw / norm }
  }

  apply(vector: Vec3): Vec3 {
    qv := Vec3.xyz(qx, qy, qz)
    uv := qv.cross(vector)
    uuv := qv.cross(uv)
    return vector.plus(uv.times(2.0 * qw)).plus(uuv.times(2.0))
  }

  toMat3(): Mat3 {
    n := normalized()
    xx := n.qx * n.qx
    yy := n.qy * n.qy
    zz := n.qz * n.qz
    xy := n.qx * n.qy
    xz := n.qx * n.qz
    yz := n.qy * n.qz
    wx := n.qw * n.qx
    wy := n.qw * n.qy
    wz := n.qw * n.qz

    return Mat3 {
      m00: 1.0 - 2.0 * (yy + zz),
      m01: 2.0 * (xy - wz),
      m02: 2.0 * (xz + wy),
      m10: 2.0 * (xy + wz),
      m11: 1.0 - 2.0 * (xx + zz),
      m12: 2.0 * (yz - wx),
      m20: 2.0 * (xz - wy),
      m21: 2.0 * (yz + wx),
      m22: 1.0 - 2.0 * (xx + yy),
    }
  }

  toMat4(): Mat4 {
    m := toMat3()
    return Mat4 {
      m00: m.m00, m01: m.m01, m02: m.m02, m03: 0.0,
      m10: m.m10, m11: m.m11, m12: m.m12, m13: 0.0,
      m20: m.m20, m21: m.m21, m22: m.m22, m23: 0.0,
      m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
    }
  }
}

export class Transform {
  readonly position: Point3
  readonly rotation: Rotation
  readonly scale: Vec3

  static identity(): Transform {
    return Transform {
      position: Point3(0.0, 0.0, 0.0),
      rotation: Rotation.identity,
      scale: Vec3.one,
    }
  }

  withPosition(position: Point3): Transform {
    return Transform { position: position, rotation: rotation, scale: scale }
  }

  withRotation(rotation: Rotation): Transform {
    return Transform { position: position, rotation: rotation, scale: scale }
  }

  withScale(scale: Vec3): Transform {
    return Transform { position: position, rotation: rotation, scale: scale }
  }

  movedBy(delta: Vec3): Transform {
    return movedWorldBy(delta)
  }

  movedWorldBy(delta: Vec3): Transform {
    return withPosition(Point3(position.x + delta.x, position.y + delta.y, position.z + delta.z))
  }

  movedLocalBy(delta: Vec3): Transform {
    return movedWorldBy(rotation.apply(delta))
  }

  rotatedLocalBy(delta: Rotation): Transform {
    return withRotation(rotation.multiply(delta))
  }

  rotatedLocalX(degrees: double): Transform {
    return rotatedLocalBy(Rotation.x(degrees))
  }

  rotatedLocalY(degrees: double): Transform {
    return rotatedLocalBy(Rotation.y(degrees))
  }

  rotatedLocalZ(degrees: double): Transform {
    return rotatedLocalBy(Rotation.z(degrees))
  }

  rotatedWorldX(degrees: double): Transform {
    return withRotation(rotation.andThen(Rotation.x(degrees)))
  }

  rotatedWorldY(degrees: double): Transform {
    return withRotation(rotation.andThen(Rotation.y(degrees)))
  }

  rotatedWorldZ(degrees: double): Transform {
    return withRotation(rotation.andThen(Rotation.z(degrees)))
  }

  scaledBy(factor: double): Transform {
    return withScale(scale.times(factor))
  }

  scaledByVec(factor: Vec3): Transform {
    return withScale(Vec3.xyz(scale.x * factor.x, scale.y * factor.y, scale.z * factor.z))
  }

  applyPoint(point: Point3): Point3 {
    local := Vec3.xyz(point.x * scale.x, point.y * scale.y, point.z * scale.z)
    rotated := rotation.apply(local)
    return Point3(position.x + rotated.x, position.y + rotated.y, position.z + rotated.z)
  }

  applyVector(vector: Vec3): Vec3 {
    return rotation.apply(Vec3.xyz(vector.x * scale.x, vector.y * scale.y, vector.z * scale.z))
  }

  toMat4(): Mat4 {
    r := rotation.toMat3()
    return Mat4 {
      m00: r.m00 * scale.x, m01: r.m01 * scale.y, m02: r.m02 * scale.z, m03: position.x,
      m10: r.m10 * scale.x, m11: r.m11 * scale.y, m12: r.m12 * scale.z, m13: position.y,
      m20: r.m20 * scale.x, m21: r.m21 * scale.y, m22: r.m22 * scale.z, m23: position.z,
      m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
    }
  }

  toInverseMat4(): Mat4 {
    r := rotation.inverse().toMat3()
    sx := safeScale(scale.x, "x")
    sy := safeScale(scale.y, "y")
    sz := safeScale(scale.z, "z")
    tx := -position.x
    ty := -position.y
    tz := -position.z

    m00 := r.m00 / sx
    m01 := r.m01 / sx
    m02 := r.m02 / sx
    m10 := r.m10 / sy
    m11 := r.m11 / sy
    m12 := r.m12 / sy
    m20 := r.m20 / sz
    m21 := r.m21 / sz
    m22 := r.m22 / sz

    return Mat4 {
      m00: m00, m01: m01, m02: m02, m03: m00 * tx + m01 * ty + m02 * tz,
      m10: m10, m11: m11, m12: m12, m13: m10 * tx + m11 * ty + m12 * tz,
      m20: m20, m21: m21, m22: m22, m23: m20 * tx + m21 * ty + m22 * tz,
      m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
    }
  }

  toNormalMat3(): Mat3 {
    r := rotation.toMat3()
    sx := safeScale(scale.x, "x")
    sy := safeScale(scale.y, "y")
    sz := safeScale(scale.z, "z")
    return Mat3 {
      m00: r.m00 / sx, m01: r.m01 / sy, m02: r.m02 / sz,
      m10: r.m10 / sx, m11: r.m11 / sy, m12: r.m12 / sz,
      m20: r.m20 / sx, m21: r.m21 / sy, m22: r.m22 / sz,
    }
  }
}
