import { PI, TAU, acos, atan2, sqrt } from "std/math"

import { SimpleMeshSpec } from "./mesh"
import { Color, Point, Point3 } from "./render"

const PHI = 1.618033988749895
const EDGE_KEY_STRIDE = 4_294_967_296L

class IcosphereGeometry {
  positions: Point3[] = []
  indices: int[] = []
  colors: Color[] = []
  uvs: Point[] = []
  normals: Point3[] = []
}

function normalizePoint(point: Point3): Point3 {
  length := sqrt(point.x * point.x + point.y * point.y + point.z * point.z)
  if length <= 0.0 {
    return Point3(0.0, 1.0, 0.0)
  }

  return Point3(point.x / length, point.y / length, point.z / length)
}

function sphericalUv(normal: Point3): Point {
  let phi = atan2(normal.x, -normal.z)
  if phi < 0.0 {
    phi += TAU
  }

  return Point(1.0 - phi / TAU, acos(normal.y) / PI)
}

function addIcosphereVertex(geometry: IcosphereGeometry, point: Point3, radius: double, color: Color): int {
  normal := normalizePoint(point)
  geometry.positions.push(Point3(normal.x * radius, normal.y * radius, normal.z * radius))
  geometry.colors.push(color)
  geometry.uvs.push(sphericalUv(normal))
  geometry.normals.push(normal)
  return geometry.positions.length - 1
}

function midpoint(a: Point3, b: Point3): Point3 {
  return Point3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5)
}

function edgeKey(a: int, b: int): long {
  let low = a
  let high = b
  if low > high {
    low = b
    high = a
  }
  return long(low) * EDGE_KEY_STRIDE + long(high)
}

function midpointIndex(
  geometry: IcosphereGeometry,
  midpointCache: Map<long, int>,
  a: int,
  b: int,
  radius: double,
  color: Color,
): int {
  key := edgeKey(a, b)
  cached := midpointCache.get(key) else {
    index := addIcosphereVertex(geometry, midpoint(geometry.normals[a], geometry.normals[b]), radius, color)
    midpointCache.set(key, index)
    return index
  }
  return cached
}

function addRawTriangle(geometry: IcosphereGeometry, a: int, b: int, c: int): void {
  geometry.indices.push(a)
  geometry.indices.push(b)
  geometry.indices.push(c)
}

function addSubdividedTriangle(
  geometry: IcosphereGeometry,
  midpointCache: Map<long, int>,
  a: int,
  b: int,
  c: int,
  depth: int,
  radius: double,
  color: Color,
): void {
  if depth <= 0 {
    addRawTriangle(geometry, a, b, c)
    return
  }

  ab := midpointIndex(geometry, midpointCache, a, b, radius, color)
  bc := midpointIndex(geometry, midpointCache, b, c, radius, color)
  ca := midpointIndex(geometry, midpointCache, c, a, radius, color)
  next := depth - 1
  addSubdividedTriangle(geometry, midpointCache, a, ab, ca, next, radius, color)
  addSubdividedTriangle(geometry, midpointCache, ab, b, bc, next, radius, color)
  addSubdividedTriangle(geometry, midpointCache, ca, bc, c, next, radius, color)
  addSubdividedTriangle(geometry, midpointCache, ab, bc, ca, next, radius, color)
}

function addIcosahedronVertices(geometry: IcosphereGeometry, radius: double, color: Color): void {
  vertices := [
    Point3(-1.0, PHI, 0.0),
    Point3(1.0, PHI, 0.0),
    Point3(-1.0, -PHI, 0.0),
    Point3(1.0, -PHI, 0.0),
    Point3(0.0, -1.0, PHI),
    Point3(0.0, 1.0, PHI),
    Point3(0.0, -1.0, -PHI),
    Point3(0.0, 1.0, -PHI),
    Point3(PHI, 0.0, -1.0),
    Point3(PHI, 0.0, 1.0),
    Point3(-PHI, 0.0, -1.0),
    Point3(-PHI, 0.0, 1.0),
  ]

  for vertex of vertices {
    addIcosphereVertex(geometry, vertex, radius, color)
  }
}

function addIcosahedronFaces(
  geometry: IcosphereGeometry,
  midpointCache: Map<long, int>,
  subdivisions: int,
  radius: double,
  color: Color,
): void {
  faces := [
    0, 11, 5,
    0, 5, 1,
    0, 1, 7,
    0, 7, 10,
    0, 10, 11,
    1, 5, 9,
    5, 11, 4,
    11, 10, 2,
    10, 7, 6,
    7, 1, 8,
    3, 9, 4,
    3, 4, 2,
    3, 2, 6,
    3, 6, 8,
    3, 8, 9,
    4, 9, 5,
    2, 4, 11,
    6, 2, 10,
    8, 6, 7,
    9, 8, 1,
  ]

  let index = 0
  while index < faces.length {
    addSubdividedTriangle(
      geometry,
      midpointCache,
      faces[index],
      faces[index + 1],
      faces[index + 2],
      subdivisions,
      radius,
      color,
    )
    index += 3
  }
}

export function createIcosphereMeshSpec(
  radius: double = 1.0,
  subdivisions: int = 2,
  color: Color = Color(1.0, 1.0, 1.0),
): SimpleMeshSpec {
  if radius <= 0.0 {
    panic("Icosphere radius must be greater than zero")
  }

  if subdivisions < 0 {
    panic("Icosphere subdivisions must be zero or greater")
  }

  geometry := IcosphereGeometry {}
  midpointCache: Map<long, int> := {}
  addIcosahedronVertices(geometry, radius, color)
  addIcosahedronFaces(geometry, midpointCache, subdivisions, radius, color)

  return SimpleMeshSpec {
    positions: geometry.positions,
    indices: geometry.indices,
    colors: geometry.colors,
    uvs: geometry.uvs,
    normals: geometry.normals,
  }
}
