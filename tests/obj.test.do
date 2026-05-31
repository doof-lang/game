import { Assert } from "std/assert"

import { Color, parseObjMeshSpec } from "../index"

export function testParseObjMeshSpecTriangulatesQuad(): void {
  parsed := parseObjMeshSpec(
    "v 0 0 0\n" +
    "v 1 0 0\n" +
    "v 1 1 0\n" +
    "v 0 1 0\n" +
    "f 1 2 3 4\n",
    "quad.obj",
    Color.red,
  )

  spec := try! parsed

  Assert.equal(spec.vertexCount(), 6)
  Assert.equal(spec.indexCount(), 6)
  Assert.equal(spec.indices[0], 0)
  Assert.equal(spec.indices[5], 5)
  Assert.equal(spec.colors[0].r, 1.0)
  Assert.equal(spec.colors[0].g, 0.0)
  Assert.equal(spec.uvs[0].x, 0.0)
  Assert.equal(spec.uvs[0].y, 0.0)
  Assert.equal(spec.normals[0].x, 0.0)
  Assert.equal(spec.normals[0].y, 0.0)
  Assert.equal(spec.normals[0].z, 1.0)
  Assert.equal(spec.positions[3].x, 0.0)
  Assert.equal(spec.positions[4].x, 1.0)
  Assert.equal(spec.positions[5].x, 0.0)
}

export function testParseObjMeshSpecReadsTexCoordsNormalsAndRelativeIndices(): void {
  parsed := parseObjMeshSpec(
    "v 0 0 0\n" +
    "v 1 0 0\n" +
    "v 0 1 0\n" +
    "vt 0.25 0.5\n" +
    "vt 0.75 0.5\n" +
    "vt 0.25 1.0\n" +
    "vn 0 0 -2\n" +
    "f -3/1/1 -2/2/1 -1/3/1\n",
    "relative.obj",
  )

  spec := try! parsed

  Assert.equal(spec.vertexCount(), 3)
  Assert.equal(spec.indexCount(), 3)
  Assert.equal(spec.uvs[0].x, 0.25)
  Assert.equal(spec.uvs[1].x, 0.75)
  Assert.equal(spec.uvs[2].y, 1.0)
  Assert.equal(spec.normals[0].x, 0.0)
  Assert.equal(spec.normals[0].y, 0.0)
  Assert.equal(spec.normals[0].z, -1.0)
}
