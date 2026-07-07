import { Assert } from "std/assert"

import {
  CollisionAabb,
  CollisionCapsule,
  CollisionSphere,
  Point3,
  Vec3,
  aabbIntersectsAabb,
  capsuleIntersectsAabb,
  capsuleIntersectsCapsule,
  capsuleIntersectsSphere,
  sphereIntersectsAabb,
  sphereIntersectsSphere,
} from "../index"

function unitBox(): CollisionAabb {
  return CollisionAabb {
    min: Point3(-1.0, -1.0, -1.0),
    max: Point3(1.0, 1.0, 1.0),
  }
}

export function testSphereIntersections(): void {
  center := CollisionSphere(Point3(0.0, 0.0, 0.0), 1.0)
  overlap := CollisionSphere(Point3(1.5, 0.0, 0.0), 1.0)
  touching := CollisionSphere(Point3(2.0, 0.0, 0.0), 1.0)
  separated := CollisionSphere(Point3(2.1, 0.0, 0.0), 1.0)

  Assert.isTrue(sphereIntersectsSphere(center, overlap))
  Assert.isTrue(sphereIntersectsSphere(center, touching))
  Assert.isFalse(sphereIntersectsSphere(center, separated))
  Assert.isTrue(center.containsPoint(Point3(1.0, 0.0, 0.0)))
  Assert.isFalse(center.containsPoint(Point3(1.1, 0.0, 0.0)))
}

export function testAabbIntersections(): void {
  box := unitBox()
  overlap := CollisionAabb.fromCenterHalfExtents(Point3(1.5, 0.0, 0.0), Vec3.one)
  touching := CollisionAabb.fromCenterSize(Point3(2.0, 0.0, 0.0), Vec3.xyz(2.0, 2.0, 2.0))
  separated := CollisionAabb.fromCenterHalfExtents(Point3(3.1, 0.0, 0.0), Vec3.one)
  inside := CollisionAabb.fromCenterHalfExtents(Point3(0.0, 0.0, 0.0), Vec3.xyz(0.25, 0.25, 0.25))

  Assert.isTrue(aabbIntersectsAabb(box, overlap))
  Assert.isTrue(aabbIntersectsAabb(box, touching))
  Assert.isTrue(aabbIntersectsAabb(box, inside))
  Assert.isFalse(aabbIntersectsAabb(box, separated))
  Assert.isTrue(box.containsPoint(Point3(1.0, -1.0, 0.5)))
  Assert.isFalse(box.containsPoint(Point3(1.1, 0.0, 0.0)))
}

export function testSphereAabbIntersections(): void {
  box := unitBox()
  inside := CollisionSphere(Point3(0.0, 0.0, 0.0), 0.25)
  edgeTouch := CollisionSphere(Point3(2.0, 0.0, 0.0), 1.0)
  cornerTouch := CollisionSphere(Point3(2.0, 2.0, 1.0), 1.4142135623730951)
  separated := CollisionSphere(Point3(2.1, 0.0, 0.0), 1.0)

  Assert.isTrue(sphereIntersectsAabb(inside, box))
  Assert.isTrue(sphereIntersectsAabb(edgeTouch, box))
  Assert.isTrue(sphereIntersectsAabb(cornerTouch, box))
  Assert.isFalse(sphereIntersectsAabb(separated, box))
}

export function testCapsuleContainsAndSphereIntersections(): void {
  capsule := CollisionCapsule(Point3(-1.0, 0.0, 0.0), Point3(1.0, 0.0, 0.0), 0.5)

  Assert.isTrue(capsule.containsPoint(Point3(0.0, 0.5, 0.0)))
  Assert.isTrue(capsule.containsPoint(Point3(1.5, 0.0, 0.0)))
  Assert.isFalse(capsule.containsPoint(Point3(0.0, 0.6, 0.0)))
  Assert.isTrue(capsuleIntersectsSphere(capsule, CollisionSphere(Point3(0.0, 1.0, 0.0), 0.5)))
  Assert.isTrue(capsuleIntersectsSphere(capsule, CollisionSphere(Point3(1.75, 0.0, 0.0), 0.25)))
  Assert.isFalse(capsuleIntersectsSphere(capsule, CollisionSphere(Point3(0.0, 1.1, 0.0), 0.5)))
}

export function testCapsuleCapsuleIntersections(): void {
  horizontal := CollisionCapsule(Point3(-1.0, 0.0, 0.0), Point3(1.0, 0.0, 0.0), 0.25)
  crossing := CollisionCapsule(Point3(0.0, -1.0, 0.0), Point3(0.0, 1.0, 0.0), 0.25)
  parallelSeparated := CollisionCapsule(Point3(-1.0, 1.0, 0.0), Point3(1.0, 1.0, 0.0), 0.25)
  endpointTouch := CollisionCapsule(Point3(1.5, 0.0, 0.0), Point3(2.5, 0.0, 0.0), 0.25)

  Assert.isTrue(capsuleIntersectsCapsule(horizontal, crossing))
  Assert.isTrue(capsuleIntersectsCapsule(horizontal, endpointTouch))
  Assert.isFalse(capsuleIntersectsCapsule(horizontal, parallelSeparated))
}

export function testCapsuleAabbIntersections(): void {
  box := unitBox()
  through := CollisionCapsule(Point3(-3.0, 0.0, 0.0), Point3(3.0, 0.0, 0.0), 0.25)
  radiusTouch := CollisionCapsule(Point3(-3.0, 1.5, 0.0), Point3(3.0, 1.5, 0.0), 0.5)
  separated := CollisionCapsule(Point3(-3.0, 1.6, 0.0), Point3(3.0, 1.6, 0.0), 0.5)
  cornerSeparated := CollisionCapsule(Point3(-3.0, 1.6, 1.6), Point3(3.0, 1.6, 1.6), 0.5)
  pointCapsule := CollisionCapsule(Point3(2.0, 0.0, 0.0), Point3(2.0, 0.0, 0.0), 1.0)

  Assert.isTrue(capsuleIntersectsAabb(through, box))
  Assert.isTrue(capsuleIntersectsAabb(radiusTouch, box))
  Assert.isFalse(capsuleIntersectsAabb(separated, box))
  Assert.isFalse(capsuleIntersectsAabb(cornerSeparated, box))
  Assert.isTrue(capsuleIntersectsAabb(pointCapsule, box))
}
