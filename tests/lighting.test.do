mock import for "../mesh" {
  "./native" => "./lighting_native.mock",
  "./surface" => "./lighting_surface.mock",
  "./render" => "./lighting_render.mock"
}

mock import for "../model_batch" {
  "./native" => "./lighting_native.mock",
  "./surface" => "./lighting_surface.mock",
  "./render" => "./lighting_render.mock"
}

import { Assert } from "std/assert"

import { SimpleMaterial, SimpleMesh, SimpleMeshLighting, SimpleMeshSpec, Vec2, drawSimpleMesh, drawTexturedSimpleMesh } from "../mesh"
import { SimpleModelBatch, drawSimpleModelBatch } from "../model_batch"
import { capture } from "./lighting_native.mock"
import { GameSurface } from "./lighting_surface.mock"
import { Color, Mat4, Point, Point3, RenderPass, Texture } from "./lighting_render.mock"
import { Transform } from "../transform"

function triangle(): SimpleMesh {
  return SimpleMesh(GameSurface {}, SimpleMeshSpec {
    positions: [Point3(0.0, 0.0, 0.0), Point3(1.0, 0.0, 0.0), Point3(0.0, 1.0, 0.0)],
    colors: [Color(1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0)],
    uvs: [Point(0.0, 0.0), Point(0.0, 0.0), Point(0.0, 0.0)],
    normals: [Point3(0.0, 0.0, 1.0), Point3(0.0, 0.0, 1.0), Point3(0.0, 0.0, 1.0)],
    indices: [0, 1, 2],
  })
}

// Every field gets a distinct value so a swapped argument shows up.
function tintedLighting(): SimpleMeshLighting {
  return SimpleMeshLighting {
    ambient: 0.11,
    directional: 0.22,
    lightColor: Color(0.31, 0.32, 0.33),
    ambientColor: Color(0.41, 0.42, 0.43),
  }
}

function distinctMaterial(): SimpleMaterial {
  return SimpleMaterial {
    tint: Color { r: 0.51, g: 0.52, b: 0.53, a: 0.54 },
    whiteBlend: 0.61,
    uvOffset: Vec2.xy(0.62, 0.63),
    uvScale: Vec2.xy(0.64, 0.65),
    specular: 0.71,
    shininess: 72.0,
    fresnel: 0.73,
    fresnelPower: 7.4,
    alphaCutoff: 0.5,
  }
}

export function testLightingAndMaterialDefaultsPreserveTheUntintedLook(): none {
  lighting := SimpleMeshLighting {}
  Assert.equal(lighting.lightColor.r, 1.0)
  Assert.equal(lighting.lightColor.g, 1.0)
  Assert.equal(lighting.lightColor.b, 1.0)
  Assert.equal(lighting.ambientColor.r, 1.0)
  Assert.equal(lighting.ambientColor.g, 1.0)
  Assert.equal(lighting.ambientColor.b, 1.0)
  Assert.equal(SimpleMaterial {}.alphaCutoff, 0.005)
}

export function testDrawSimpleMeshForwardsLightingAndMaterial(): none {
  before := capture.meshCalls
  drawSimpleMesh(RenderPass {}, triangle(), Mat4.identity, distinctMaterial(), tintedLighting())

  Assert.equal(capture.meshCalls, before + 1)
  Assert.equal(capture.meshAmbientLight, 0.11)
  Assert.equal(capture.meshDirectionalLight, 0.22)
  Assert.equal(capture.meshEyeX, 7.0)
  Assert.equal(capture.meshEyeY, 8.0)
  Assert.equal(capture.meshEyeZ, 9.0)
  Assert.equal(capture.meshLightRed, 0.31)
  Assert.equal(capture.meshLightGreen, 0.32)
  Assert.equal(capture.meshLightBlue, 0.33)
  Assert.equal(capture.meshAmbientRed, 0.41)
  Assert.equal(capture.meshAmbientGreen, 0.42)
  Assert.equal(capture.meshAmbientBlue, 0.43)
  Assert.equal(capture.meshRed, 0.51)
  Assert.equal(capture.meshAlpha, 0.54)
  Assert.equal(capture.meshWhiteBlend, 0.61)
  Assert.equal(capture.meshUvOffsetX, 0.62)
  Assert.equal(capture.meshUvScaleY, 0.65)
  Assert.equal(capture.meshSpecular, 0.71)
  Assert.equal(capture.meshShininess, 72.0)
  Assert.equal(capture.meshFresnel, 0.73)
  Assert.equal(capture.meshFresnelPower, 7.4)
  Assert.equal(capture.meshAlphaCutoff, 0.5)
}

export function testDrawTexturedSimpleMeshForwardsLightingAndMaterial(): none {
  before := capture.texturedMeshCalls
  drawTexturedSimpleMesh(RenderPass {}, triangle(), Texture {}, Mat4.identity, distinctMaterial(), tintedLighting())

  Assert.equal(capture.texturedMeshCalls, before + 1)
  Assert.equal(capture.meshLightBlue, 0.33)
  Assert.equal(capture.meshAmbientRed, 0.41)
  Assert.equal(capture.meshFresnelPower, 7.4)
  Assert.equal(capture.meshAlphaCutoff, 0.5)
}

export function testDrawSimpleModelBatchForwardsLightingAndInstanceMaterial(): none {
  batch := SimpleModelBatch { surface: GameSurface {}, mesh: triangle(), capacity: 2 }
  batch.add(Transform.identity(), distinctMaterial())
  instancesBefore := capture.instanceCalls
  batchesBefore := capture.batchCalls

  drawSimpleModelBatch(RenderPass {}, batch, tintedLighting())

  Assert.equal(capture.instanceCalls, instancesBefore + 1)
  Assert.equal(capture.instanceRed, 0.51)
  Assert.equal(capture.instanceAlpha, 0.54)
  Assert.equal(capture.instanceWhiteBlend, 0.61)
  Assert.equal(capture.instanceUvOffsetX, 0.62)
  Assert.equal(capture.instanceUvScaleY, 0.65)
  Assert.equal(capture.instanceSpecular, 0.71)
  Assert.equal(capture.instanceShininess, 72.0)
  Assert.equal(capture.instanceFresnel, 0.73)
  Assert.equal(capture.instanceFresnelPower, 7.4)
  Assert.equal(capture.instanceAlphaCutoff, 0.5)

  Assert.equal(capture.batchCalls, batchesBefore + 1)
  Assert.equal(capture.batchAmbientLight, 0.11)
  Assert.equal(capture.batchDirectionalLight, 0.22)
  Assert.equal(capture.batchEyeZ, 9.0)
  Assert.equal(capture.batchLightRed, 0.31)
  Assert.equal(capture.batchLightGreen, 0.32)
  Assert.equal(capture.batchLightBlue, 0.33)
  Assert.equal(capture.batchAmbientRed, 0.41)
  Assert.equal(capture.batchAmbientGreen, 0.42)
  Assert.equal(capture.batchAmbientBlue, 0.43)
}
