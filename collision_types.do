import { clamp } from "std/math"

import { Point3 } from "./render"
import { Vec3 } from "./transform"

readonly EPSILON = 0.000001

function pointToVec(point: Point3): Vec3 {
  return Vec3.xyz(point.x, point.y, point.z)
}

function distanceSquared(a: Point3, b: Point3): double {
  dx := a.x - b.x
  dy := a.y - b.y
  dz := a.z - b.z
  return dx * dx + dy * dy + dz * dz
}

function closestPointOnSegment(point: Point3, a: Point3, b: Point3): Point3 {
  ab := pointToVec(b).minus(pointToVec(a))
  lengthSquared := ab.lengthSquared()
  if lengthSquared <= EPSILON {
    return a
  }

  ap := pointToVec(point).minus(pointToVec(a))
  t := clamp(ap.dot(ab) / lengthSquared, 0.0, 1.0)
  return Point3(a.x + ab.x * t, a.y + ab.y * t, a.z + ab.z * t)
}

export struct CollisionSphere {
  readonly center: Point3
  readonly radius: double

  static constructor(center: Point3, radius: double): CollisionSphere {
    if radius < 0.0 {
      panic("CollisionSphere radius must be zero or greater")
    }
    return CollisionSphere { center, radius }
  }

  containsPoint(point: Point3): bool {
    return distanceSquared(center, point) <= radius * radius
  }
}

export struct CollisionCapsule {
  readonly a: Point3
  readonly b: Point3
  readonly radius: double

  static constructor(a: Point3, b: Point3, radius: double): CollisionCapsule {
    if radius < 0.0 {
      panic("CollisionCapsule radius must be zero or greater")
    }
    return CollisionCapsule { a, b, radius }
  }

  containsPoint(point: Point3): bool {
    closest := closestPointOnSegment(point, a, b)
    return distanceSquared(point, closest) <= radius * radius
  }
}

export struct CollisionAabb {
  readonly min: Point3
  readonly max: Point3

  static constructor(min: Point3, max: Point3): CollisionAabb {
    if min.x > max.x || min.y > max.y || min.z > max.z {
      panic("CollisionAabb min must be less than or equal to max on each axis")
    }
    return CollisionAabb { min, max }
  }

  static fromCenterHalfExtents(center: Point3, halfExtents: Vec3): CollisionAabb {
    if halfExtents.x < 0.0 || halfExtents.y < 0.0 || halfExtents.z < 0.0 {
      panic("CollisionAabb half extents must be zero or greater")
    }
    return CollisionAabb {
      min: Point3(center.x - halfExtents.x, center.y - halfExtents.y, center.z - halfExtents.z),
      max: Point3(center.x + halfExtents.x, center.y + halfExtents.y, center.z + halfExtents.z),
    }
  }

  static fromCenterSize(center: Point3, size: Vec3): CollisionAabb {
    if size.x < 0.0 || size.y < 0.0 || size.z < 0.0 {
      panic("CollisionAabb size must be zero or greater")
    }
    return CollisionAabb.fromCenterHalfExtents(center, size.times(0.5))
  }

  containsPoint(point: Point3): bool {
    return point.x >= min.x && point.x <= max.x
      && point.y >= min.y && point.y <= max.y
      && point.z >= min.z && point.z <= max.z
  }
}
