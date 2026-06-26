import { BlobBuilder } from "std/blob"
import { writeBlob } from "std/fs"
import { join, tempDirectory } from "std/path"
import { Assert } from "std/assert"

import { Color, glbAssetToSimpleMeshSpecs, loadGlb, parseGlb } from "../index"

const GLB_MAGIC = 1179937895
const GLB_JSON = 1313821514
const GLB_BIN = 5130562

function isFailure<T, E>(result: Result<T, E>): bool {
  return case result {
    _: Success -> false,
    _: Failure -> true,
  }
}

function paddedText(text: string): readonly byte[] {
  builder := BlobBuilder()
  try! builder.writeText(text)
  while builder.length() % 4L != 0L {
    builder.writeByte(32)
  }
  return builder.build()
}

function paddedBin(data: readonly byte[]): readonly byte[] {
  builder := BlobBuilder()
  builder.writeBytes(data)
  while builder.length() % 4L != 0L {
    builder.writeByte(0)
  }
  return builder.build()
}

function buildGlb(json: string, bin: readonly byte[] = []): readonly byte[] {
  jsonBytes := paddedText(json)
  binBytes := paddedBin(bin)
  hasBin := bin.length > 0
  length := 12 + 8 + jsonBytes.length + if hasBin then 8 + binBytes.length else 0

  builder := BlobBuilder()
  builder.writeInt(GLB_MAGIC)
  builder.writeInt(2)
  builder.writeInt(length)
  builder.writeInt(jsonBytes.length)
  builder.writeInt(GLB_JSON)
  builder.writeBytes(jsonBytes)
  if hasBin {
    builder.writeInt(binBytes.length)
    builder.writeInt(GLB_BIN)
    builder.writeBytes(binBytes)
  }
  return builder.build()
}

function trianglePositionBin(): readonly byte[] {
  builder := BlobBuilder()
  builder.writeFloat(0.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(1.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(1.0f)
  builder.writeFloat(0.0f)
  return builder.build()
}

function minimalTriangleJson(bufferLength: int): string {
  return "{" +
    "\"asset\":{\"version\":\"2.0\"}," +
    "\"buffers\":[{\"byteLength\":" + string(bufferLength) + "}]," +
    "\"bufferViews\":[{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36}]," +
    "\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}]," +
    "\"meshes\":[{\"name\":\"Triangle\",\"primitives\":[{\"attributes\":{\"POSITION\":0}}]}]" +
    "}"
}

function richTriangleBin(): readonly byte[] {
  builder := BlobBuilder()
  // POSITION
  builder.writeFloat(0.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(1.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(1.0f)
  builder.writeFloat(0.0f)
  // NORMAL
  for normalIndex of 0..<3 {
    normalIndex
    builder.writeFloat(0.0f)
    builder.writeFloat(0.0f)
    builder.writeFloat(-2.0f)
  }
  // TEXCOORD_0
  builder.writeFloat(0.25f)
  builder.writeFloat(0.5f)
  builder.writeFloat(0.75f)
  builder.writeFloat(0.5f)
  builder.writeFloat(0.25f)
  builder.writeFloat(1.0f)
  // COLOR_0
  builder.writeFloat(1.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(0.5f)
  builder.writeFloat(0.0f)
  builder.writeFloat(1.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(0.6f)
  builder.writeFloat(0.0f)
  builder.writeFloat(0.0f)
  builder.writeFloat(1.0f)
  builder.writeFloat(0.7f)
  // indices
  builder.writeUnsignedShort(0)
  builder.writeUnsignedShort(1)
  builder.writeUnsignedShort(2)
  return builder.build()
}

function richTriangleJson(bufferLength: int): string {
  return "{" +
    "\"asset\":{\"version\":\"2.0\"}," +
    "\"buffers\":[{\"byteLength\":" + string(bufferLength) + "}]," +
    "\"bufferViews\":[" +
      "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36}," +
      "{\"buffer\":0,\"byteOffset\":36,\"byteLength\":36}," +
      "{\"buffer\":0,\"byteOffset\":72,\"byteLength\":24}," +
      "{\"buffer\":0,\"byteOffset\":96,\"byteLength\":48}," +
      "{\"buffer\":0,\"byteOffset\":144,\"byteLength\":6}" +
    "]," +
    "\"accessors\":[" +
      "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}," +
      "{\"bufferView\":1,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}," +
      "{\"bufferView\":2,\"componentType\":5126,\"count\":3,\"type\":\"VEC2\"}," +
      "{\"bufferView\":3,\"componentType\":5126,\"count\":3,\"type\":\"VEC4\"}," +
      "{\"bufferView\":4,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}" +
    "]," +
    "\"meshes\":[{\"name\":\"Rich\",\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":1,\"TEXCOORD_0\":2,\"COLOR_0\":3},\"indices\":4}]}]" +
    "}"
}

export function testParseGlbConvertsMinimalTriangleAndComputesNormals(): void {
  bin := trianglePositionBin()
  asset := try! parseGlb(buildGlb(minimalTriangleJson(bin.length), bin), "triangle.glb")
  specs := try! glbAssetToSimpleMeshSpecs(asset, Color.red)
  spec := specs[0].spec

  Assert.equal(asset.meshes.length, 1)
  Assert.equal(specs[0].name!, "Triangle")
  Assert.equal(spec.vertexCount(), 3)
  Assert.equal(spec.indexCount(), 3)
  Assert.equal(spec.colors[0].r, 1.0)
  Assert.equal(spec.uvs[0].x, 0.0)
  Assert.equal(spec.normals[0].x, 0.0)
  Assert.equal(spec.normals[0].y, 0.0)
  Assert.equal(spec.normals[0].z, 1.0)
}

export function testParseGlbConvertsIndexedAttributes(): void {
  bin := richTriangleBin()
  asset := try! parseGlb(buildGlb(richTriangleJson(bin.length), bin), "rich.glb")
  specs := try! glbAssetToSimpleMeshSpecs(asset)
  spec := specs[0].spec

  Assert.equal(spec.vertexCount(), 3)
  Assert.equal(spec.positions[1].x, 1.0)
  Assert.equal(spec.uvs[0].x, 0.25)
  Assert.equal(spec.uvs[2].y, 1.0)
  Assert.equal(spec.colors[0].r, 1.0)
  Assert.equal(spec.colors[0].a, 0.5)
  Assert.equal(spec.colors[1].g, 1.0)
  Assert.equal(spec.normals[0].z, -1.0)
}

export function testParseGlbWarningsStillAllowStaticConversion(): void {
  bin := trianglePositionBin()
  json := "{" +
    "\"asset\":{\"version\":\"2.0\"}," +
    "\"buffers\":[{\"byteLength\":" + string(bin.length) + ",\"uri\":\"external.bin\"}]," +
    "\"bufferViews\":[{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36}]," +
    "\"accessors\":[" +
      "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}," +
      "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\",\"sparse\":{\"count\":0}}" +
    "]," +
    "\"samplers\":[{\"name\":\"Nearest\",\"magFilter\":9728,\"minFilter\":9728,\"wrapS\":33071,\"wrapT\":33071}]," +
    "\"images\":[{\"name\":\"Atlas\",\"bufferView\":0,\"mimeType\":\"image/png\"}]," +
    "\"textures\":[{\"name\":\"Diffuse\",\"sampler\":0,\"source\":0}]," +
    "\"materials\":[{\"name\":\"Body\",\"pbrMetallicRoughness\":{\"baseColorFactor\":[0.5,0.25,1.0,0.75],\"baseColorTexture\":{\"index\":0,\"texCoord\":1},\"metallicFactor\":0.1,\"roughnessFactor\":0.9},\"doubleSided\":true,\"alphaMode\":\"BLEND\"}]," +
    "\"animations\":[{\"name\":\"Wave\",\"samplers\":[{\"input\":0,\"output\":1,\"interpolation\":\"STEP\"}],\"channels\":[{\"sampler\":0,\"target\":{\"node\":0,\"path\":\"rotation\"}}]}]," +
    "\"skins\":[{}]," +
    "\"meshes\":[{\"primitives\":[" +
      "{\"attributes\":{\"POSITION\":0}}," +
      "{\"mode\":1,\"attributes\":{\"POSITION\":0},\"material\":0,\"targets\":[{}]}" +
    "]}]" +
    "}"

  asset := try! parseGlb(buildGlb(json, bin), "warnings.glb")
  specs := try! glbAssetToSimpleMeshSpecs(asset)

  Assert.equal(specs.length, 1)
  Assert.equal(asset.samplers.length, 1)
  Assert.equal(asset.samplers[0].wrapS, 33071)
  Assert.equal(asset.images.length, 1)
  Assert.equal(asset.images[0].mimeType!, "image/png")
  Assert.equal(asset.textures.length, 1)
  Assert.equal(asset.textures[0].source, 0)
  Assert.equal(asset.materials.length, 1)
  Assert.equal(asset.materials[0].name!, "Body")
  Assert.equal(asset.materials[0].baseColorFactor.r, 0.5)
  Assert.equal(asset.materials[0].baseColorFactor.a, 0.75)
  Assert.equal(asset.materials[0].baseColorTexture!.index, 0)
  Assert.equal(asset.materials[0].baseColorTexture!.texCoord, 1)
  Assert.equal(asset.materials[0].metallicFactor, 0.1)
  Assert.equal(asset.materials[0].roughnessFactor, 0.9)
  Assert.isTrue(asset.materials[0].doubleSided, "expected material double-sided flag to parse")
  Assert.equal(asset.materials[0].alphaMode, "BLEND")
  Assert.equal(asset.animations.length, 1)
  Assert.equal(asset.animations[0].name!, "Wave")
  Assert.equal(asset.animations[0].samplers[0].input, 0)
  Assert.equal(asset.animations[0].samplers[0].output, 1)
  Assert.equal(asset.animations[0].samplers[0].interpolation, "STEP")
  Assert.equal(asset.animations[0].channels[0].sampler, 0)
  Assert.equal(asset.animations[0].channels[0].target.node, 0)
  Assert.equal(asset.animations[0].channels[0].target.path, "rotation")
  Assert.isTrue(asset.warnings.length >= 5, "expected unsupported features to be reported as warnings")
}

export function testLoadGlbReadsFile(): void {
  bin := trianglePositionBin()
  path := join([tempDirectory(), "doof-game-gltf-test.glb"])
  try! writeBlob(path, buildGlb(minimalTriangleJson(bin.length), bin))

  asset := try! loadGlb(path)
  specs := try! glbAssetToSimpleMeshSpecs(asset)

  Assert.equal(specs.length, 1)
  Assert.equal(specs[0].spec.vertexCount(), 3)
}

export function testParseGlbRejectsMalformedContainers(): void {
  badMagicBuilder := BlobBuilder()
  badMagicBuilder.writeInt(0)
  badMagicBuilder.writeInt(2)
  badMagicBuilder.writeInt(12)
  Assert.isTrue(isFailure(parseGlb(badMagicBuilder.build(), "bad.glb")), "expected bad magic to fail")

  missingJsonBuilder := BlobBuilder()
  missingJsonBuilder.writeInt(GLB_MAGIC)
  missingJsonBuilder.writeInt(2)
  missingJsonBuilder.writeInt(12)
  Assert.isTrue(isFailure(parseGlb(missingJsonBuilder.build(), "missing-json.glb")), "expected missing JSON to fail")

  invalidJson := buildGlb("{", [])
  Assert.isTrue(isFailure(parseGlb(invalidJson, "invalid-json.glb")), "expected invalid JSON to fail")
}

export function testGlbConversionRejectsInvalidAccessorsAndBufferOverruns(): void {
  noSupported := try! parseGlb(buildGlb("{\"asset\":{\"version\":\"2.0\"},\"meshes\":[{\"primitives\":[{\"mode\":1}]}]}"))
  Assert.isTrue(isFailure(glbAssetToSimpleMeshSpecs(noSupported)), "expected no supported primitives to fail")

  bin := trianglePositionBin()
  overrunJson := "{" +
    "\"asset\":{\"version\":\"2.0\"}," +
    "\"buffers\":[{\"byteLength\":" + string(bin.length) + "}]," +
    "\"bufferViews\":[{\"buffer\":0,\"byteOffset\":24,\"byteLength\":36}]," +
    "\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}]," +
    "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0}}]}]" +
    "}"
  overrun := try! parseGlb(buildGlb(overrunJson, bin), "overrun.glb")
  Assert.isTrue(isFailure(glbAssetToSimpleMeshSpecs(overrun)), "expected buffer overrun to fail")
}
