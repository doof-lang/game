import { clamp, max, min } from "std/math"

import { collisionDistanceSquared, collisionDistanceSquaredPointAabb } from "./collision_math"
import { CollisionAabb } from "./collision_types"
import { Point3 } from "./render"
import { Vec3 } from "./transform"

readonly EPSILON = 0.000001

function pointToVec(point: Point3): Vec3 {
  return Vec3.xyz(point.x, point.y, point.z)
}

function pointOnSegment(a: Point3, b: Point3, t: double): Point3 {
  return Point3(
    a.x + (b.x - a.x) * t,
    a.y + (b.y - a.y) * t,
    a.z + (b.z - a.z) * t,
  )
}

function collisionSegmentIntersectsAabb(a: Point3, b: Point3, box: CollisionAabb): bool {
  dx := b.x - a.x
  dy := b.y - a.y
  dz := b.z - a.z
  let tMin = 0.0
  let tMax = 1.0

  if dx > -EPSILON && dx < EPSILON {
    if a.x < box.min.x || a.x > box.max.x { return false }
  } else {
    inv := 1.0 / dx
    let near = (box.min.x - a.x) * inv
    let far = (box.max.x - a.x) * inv
    if near > far {
      temp := near
      near = far
      far = temp
    }
    tMin = max(tMin, near)
    tMax = min(tMax, far)
    if tMin > tMax { return false }
  }

  if dy > -EPSILON && dy < EPSILON {
    if a.y < box.min.y || a.y > box.max.y { return false }
  } else {
    inv := 1.0 / dy
    let near = (box.min.y - a.y) * inv
    let far = (box.max.y - a.y) * inv
    if near > far {
      temp := near
      near = far
      far = temp
    }
    tMin = max(tMin, near)
    tMax = min(tMax, far)
    if tMin > tMax { return false }
  }

  if dz > -EPSILON && dz < EPSILON {
    if a.z < box.min.z || a.z > box.max.z { return false }
  } else {
    inv := 1.0 / dz
    let near = (box.min.z - a.z) * inv
    let far = (box.max.z - a.z) * inv
    if near > far {
      temp := near
      near = far
      far = temp
    }
    tMin = max(tMin, near)
    tMax = min(tMax, far)
    if tMin > tMax { return false }
  }

  return true
}

export function collisionDistanceSquaredSegmentAabb(a: Point3, b: Point3, box: CollisionAabb): double {
  if collisionSegmentIntersectsAabb(a, b, box) {
    return 0.0
  }

  let lo = 0.0
  let hi = 1.0
  let iteration = 0
  while iteration < 48 {
    third := (hi - lo) / 3.0
    left := lo + third
    right := hi - third
    leftDistance := collisionDistanceSquaredPointAabb(pointOnSegment(a, b, left), box)
    rightDistance := collisionDistanceSquaredPointAabb(pointOnSegment(a, b, right), box)
    if leftDistance < rightDistance {
      hi = right
    } else {
      lo = left
    }
    iteration += 1
  }

  mid := (lo + hi) * 0.5
  return collisionDistanceSquaredPointAabb(pointOnSegment(a, b, mid), box)
}

export function collisionDistanceSquaredSegments(a0: Point3, a1: Point3, b0: Point3, b1: Point3): double {
  u := pointToVec(a1).minus(pointToVec(a0))
  v := pointToVec(b1).minus(pointToVec(b0))
  w := pointToVec(a0).minus(pointToVec(b0))
  a := u.dot(u)
  b := u.dot(v)
  c := v.dot(v)
  d := u.dot(w)
  e := v.dot(w)
  denominator := a * c - b * b
  let sN = 0.0
  let sD = denominator
  let tN = 0.0
  let tD = denominator

  if a <= EPSILON && c <= EPSILON {
    return collisionDistanceSquared(a0, b0)
  }
  if a <= EPSILON {
    t := clamp(e / c, 0.0, 1.0)
    closest := Point3(b0.x + v.x * t, b0.y + v.y * t, b0.z + v.z * t)
    return collisionDistanceSquared(a0, closest)
  }
  if c <= EPSILON {
    s := clamp(-d / a, 0.0, 1.0)
    closest := Point3(a0.x + u.x * s, a0.y + u.y * s, a0.z + u.z * s)
    return collisionDistanceSquared(closest, b0)
  }

  if denominator < EPSILON {
    sN = 0.0
    sD = 1.0
    tN = e
    tD = c
  } else {
    sN = b * e - c * d
    tN = a * e - b * d
    if sN < 0.0 {
      sN = 0.0
      tN = e
      tD = c
    } else if sN > sD {
      sN = sD
      tN = e + b
      tD = c
    }
  }

  if tN < 0.0 {
    tN = 0.0
    if -d < 0.0 {
      sN = 0.0
    } else if -d > a {
      sN = sD
    } else {
      sN = -d
      sD = a
    }
  } else if tN > tD {
    tN = tD
    if -d + b < 0.0 {
      sN = 0.0
    } else if -d + b > a {
      sN = sD
    } else {
      sN = -d + b
      sD = a
    }
  }

  sc := if sN > -EPSILON && sN < EPSILON then 0.0 else sN / sD
  tc := if tN > -EPSILON && tN < EPSILON then 0.0 else tN / tD
  dx := w.x + u.x * sc - v.x * tc
  dy := w.y + u.y * sc - v.y * tc
  dz := w.z + u.z * sc - v.z * tc
  return dx * dx + dy * dy + dz * dz
}
