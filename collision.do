import { CollisionAabb, CollisionCapsule, CollisionSphere } from "./collision_types"
import {
  collisionClosestPointOnSegment,
  collisionDistanceSquared,
  collisionDistanceSquaredPointAabb,
} from "./collision_math"
import {
  collisionDistanceSquaredSegmentAabb,
  collisionDistanceSquaredSegments,
} from "./collision_segments"

readonly EPSILON = 0.000001

export { CollisionAabb, CollisionCapsule, CollisionSphere } from "./collision_types"

export function sphereIntersectsSphere(a: CollisionSphere, b: CollisionSphere): bool {
  radius := a.radius + b.radius
  return collisionDistanceSquared(a.center, b.center) <= radius * radius
}

export function sphereIntersectsAabb(sphere: CollisionSphere, box: CollisionAabb): bool {
  return collisionDistanceSquaredPointAabb(sphere.center, box) <= sphere.radius * sphere.radius
}

export function aabbIntersectsAabb(a: CollisionAabb, b: CollisionAabb): bool {
  return a.min.x <= b.max.x && a.max.x >= b.min.x
    && a.min.y <= b.max.y && a.max.y >= b.min.y
    && a.min.z <= b.max.z && a.max.z >= b.min.z
}

export function capsuleIntersectsSphere(capsule: CollisionCapsule, sphere: CollisionSphere): bool {
  closest := collisionClosestPointOnSegment(sphere.center, capsule.a, capsule.b)
  radius := capsule.radius + sphere.radius
  return collisionDistanceSquared(closest, sphere.center) <= radius * radius
}

export function capsuleIntersectsCapsule(a: CollisionCapsule, b: CollisionCapsule): bool {
  radius := a.radius + b.radius
  return collisionDistanceSquaredSegments(a.a, a.b, b.a, b.b) <= radius * radius
}

export function capsuleIntersectsAabb(capsule: CollisionCapsule, box: CollisionAabb): bool {
  return collisionDistanceSquaredSegmentAabb(capsule.a, capsule.b, box) <= capsule.radius * capsule.radius + EPSILON
}
