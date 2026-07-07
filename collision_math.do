import { clamp } from "std/math"

import { CollisionAabb } from "./collision_types"
import { Point3 } from "./render"
import { Vec3 } from "./transform"

readonly EPSILON = 0.000001

function pointToVec(point: Point3): Vec3 {
  return Vec3.xyz(point.x, point.y, point.z)
}

export function collisionDistanceSquared(a: Point3, b: Point3): double {
  dx := a.x - b.x
  dy := a.y - b.y
  dz := a.z - b.z
  return dx * dx + dy * dy + dz * dz
}

export function collisionClosestPointOnSegment(point: Point3, a: Point3, b: Point3): Point3 {
  ab := pointToVec(b).minus(pointToVec(a))
  lengthSquared := ab.lengthSquared()
  if lengthSquared <= EPSILON {
    return a
  }

  ap := pointToVec(point).minus(pointToVec(a))
  t := clamp(ap.dot(ab) / lengthSquared, 0.0, 1.0)
  return Point3(a.x + ab.x * t, a.y + ab.y * t, a.z + ab.z * t)
}

function closestPointInAabb(point: Point3, box: CollisionAabb): Point3 {
  return Point3(
    clamp(point.x, box.min.x, box.max.x),
    clamp(point.y, box.min.y, box.max.y),
    clamp(point.z, box.min.z, box.max.z),
  )
}

export function collisionDistanceSquaredPointAabb(point: Point3, box: CollisionAabb): double {
  closest := closestPointInAabb(point, box)
  return collisionDistanceSquared(point, closest)
}
