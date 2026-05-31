import { PI, cos, sin } from "std/math"

import { SimpleMeshSpec } from "./mesh"
import { Color, Point, Point3 } from "./render"

const TAU = PI * 2.0

function latitudeSegmentCount(tessellation: int): int {
  if tessellation < 2 {
    return 2
  }
  return tessellation
}

function longitudeSegmentCount(tessellation: int): int {
  segments := tessellation * 2
  if segments < 3 {
    return 3
  }
  return segments
}

export function createSphereMeshSpec(
  radius: double = 1.0,
  tessellation: int = 24,
  color: Color = Color(1.0, 1.0, 1.0),
): SimpleMeshSpec {
  if radius <= 0.0 {
    panic("Sphere radius must be greater than zero")
  }

  latitudeSegments := latitudeSegmentCount(tessellation)
  longitudeSegments := longitudeSegmentCount(tessellation)
  positions: Point3[] := []
  indices: int[] := []
  colors: Color[] := []
  uvs: Point[] := []
  normals: Point3[] := []

  for row of 0..<latitudeSegments + 1 {
    v := double(row) / double(latitudeSegments)
    theta := v * PI
    y := cos(theta)
    ringRadius := sin(theta)

    for column of 0..<longitudeSegments + 1 {
      longitudeFraction := double(column) / double(longitudeSegments)
      u := 1.0 - longitudeFraction
      phi := longitudeFraction * TAU
      x := ringRadius * sin(phi)
      z := -ringRadius * cos(phi)

      positions.push(Point3(x * radius, y * radius, z * radius))
      colors.push(color)
      uvs.push(Point(u, v))
      normals.push(Point3(x, y, z))
    }
  }

  rowStride := longitudeSegments + 1
  for row of 0..<latitudeSegments {
    for column of 0..<longitudeSegments {
      topLeft := row * rowStride + column
      topRight := topLeft + 1
      bottomLeft := topLeft + rowStride
      bottomRight := bottomLeft + 1

      indices.push(topLeft)
      indices.push(topRight)
      indices.push(bottomLeft)
      indices.push(topRight)
      indices.push(bottomRight)
      indices.push(bottomLeft)
    }
  }

  return SimpleMeshSpec {
    positions: positions,
    indices: indices,
    colors: colors,
    uvs: uvs,
    normals: normals,
  }
}
