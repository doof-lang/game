import { BlobReader, Endian } from "std/blob"
import { readBlob } from "std/fs"
import { parseJsonValue } from "std/json"
import { sqrt } from "std/math"

import { SimpleMeshSpec } from "./mesh"
import { Color, Point, Point3 } from "./render"

const GLB_MAGIC = 1179937895
const GLB_VERSION = 2
const GLB_CHUNK_JSON = 1313821514
const GLB_CHUNK_BIN = 5130562
const GLTF_MODE_TRIANGLES = 4
const GLTF_COMPONENT_UNSIGNED_BYTE = 5121
const GLTF_COMPONENT_UNSIGNED_SHORT = 5123
const GLTF_COMPONENT_UNSIGNED_INT = 5125
const GLTF_COMPONENT_FLOAT = 5126
const EPSILON = 0.000001

export class GltfError {
  stage: string = ""
  path: string = ""
  message: string = ""
}

export class GltfWarning {
  stage: string = ""
  path: string = ""
  message: string = ""
}

export class GltfBuffer {
  byteLength: int = 0
  uri: string | null = null
}

export class GltfBufferView {
  buffer: int = 0
  byteOffset: int = 0
  byteLength: int = 0
  byteStride: int = 0
}

export class GltfAccessor {
  bufferView: int = -1
  byteOffset: int = 0
  componentType: int = 0
  count: int = 0
  typeName: string = ""
  normalized: bool = false
  sparse: bool = false
}

export class GltfPrimitive {
  attributes: Map<string, int> = {}
  indices: int = -1
  mode: int = 4
  material: int = -1
  hasTargets: bool = false
}

export class GltfMesh {
  name: string | null = null
  primitives: GltfPrimitive[] = []
}

export class GltfNode {
  name: string | null = null
  mesh: int = -1
  children: int[] = []
}

export class GltfScene {
  name: string | null = null
  nodes: int[] = []
}

export class GltfSampler {
  name: string | null = null
  magFilter: int = -1
  minFilter: int = -1
  wrapS: int = 10497
  wrapT: int = 10497
}

export class GltfImage {
  name: string | null = null
  uri: string | null = null
  mimeType: string | null = null
  bufferView: int = -1
}

export class GltfTexture {
  name: string | null = null
  sampler: int = -1
  source: int = -1
}

export class GltfTextureInfo {
  index: int = -1
  texCoord: int = 0
  scale: double = 1.0
  strength: double = 1.0
}

export class GltfMaterial {
  name: string | null = null
  baseColorFactor: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }
  baseColorTexture: GltfTextureInfo | null = null
  metallicFactor: double = 1.0
  roughnessFactor: double = 1.0
  metallicRoughnessTexture: GltfTextureInfo | null = null
  normalTexture: GltfTextureInfo | null = null
  occlusionTexture: GltfTextureInfo | null = null
  emissiveTexture: GltfTextureInfo | null = null
  emissiveFactor: Color = Color { r: 0.0, g: 0.0, b: 0.0, a: 1.0 }
  alphaMode: string = "OPAQUE"
  alphaCutoff: double = 0.5
  doubleSided: bool = false
}

export class GltfAnimationSampler {
  input: int = -1
  output: int = -1
  interpolation: string = "LINEAR"
}

export class GltfAnimationTarget {
  node: int = -1
  path: string = ""
}

export class GltfAnimationChannel {
  sampler: int = -1
  target: GltfAnimationTarget = GltfAnimationTarget {}
}

export class GltfAnimation {
  name: string | null = null
  samplers: GltfAnimationSampler[] = []
  channels: GltfAnimationChannel[] = []
}

export class GltfAsset {
  source: string = "input"
  json: JsonObject = {}
  binChunk: readonly byte[] = []
  buffers: GltfBuffer[] = []
  bufferViews: GltfBufferView[] = []
  accessors: GltfAccessor[] = []
  meshes: GltfMesh[] = []
  nodes: GltfNode[] = []
  scenes: GltfScene[] = []
  samplers: GltfSampler[] = []
  images: GltfImage[] = []
  textures: GltfTexture[] = []
  materials: GltfMaterial[] = []
  animations: GltfAnimation[] = []
  animationsCount: int = 0
  skinsCount: int = 0
  warnings: GltfWarning[] = []
}

export class GltfSimpleMeshSpec {
  meshIndex: int = 0
  primitiveIndex: int = 0
  name: string | null = null
  spec: SimpleMeshSpec
}

function gltfError(stage: string, path: string, message: string): GltfError {
  return GltfError { stage, path, message }
}

function gltfWarning(stage: string, path: string, message: string): GltfWarning {
  return GltfWarning { stage, path, message }
}

function jsonField(object: JsonObject, name: string): JsonValue | null {
  return case object.get(name) {
    s: Success -> s.value,
    _: Failure -> null,
  }
}

function jsonArrayField(object: JsonObject, name: string, path: string): Result<JsonValue[] | null, GltfError> {
  value := jsonField(object, name)
  if value == null {
    return Success(null)
  }

  array := value! as JsonValue[] else {
    return Failure(gltfError("json", path + "." + name, "Expected JSON array"))
  }
  return Success(array)
}

function jsonObjectField(object: JsonObject, name: string, path: string): Result<JsonObject | null, GltfError> {
  value := jsonField(object, name)
  if value == null {
    return Success(null)
  }

  child := value! as JsonObject else {
    return Failure(gltfError("json", path + "." + name, "Expected JSON object"))
  }
  return Success(child)
}

function jsonStringField(object: JsonObject, name: string, path: string): Result<string | null, GltfError> {
  value := jsonField(object, name)
  if value == null {
    return Success(null)
  }

  text := value! as string else {
    return Failure(gltfError("json", path + "." + name, "Expected string"))
  }
  return Success(text)
}

function jsonBoolField(object: JsonObject, name: string, defaultValue: bool, path: string): Result<bool, GltfError> {
  value := jsonField(object, name)
  if value == null {
    return Success(defaultValue)
  }

  flag := value! as bool else {
    return Failure(gltfError("json", path + "." + name, "Expected boolean"))
  }
  return Success(flag)
}

function jsonIntValue(value: JsonValue, path: string): Result<int, GltfError> {
  narrowed := value as int else {
    return Failure(gltfError("json", path, "Expected integer"))
  }
  return Success(narrowed)
}

function jsonIntField(object: JsonObject, name: string, defaultValue: int, path: string): Result<int, GltfError> {
  value := jsonField(object, name)
  if value == null {
    return Success(defaultValue)
  }

  return jsonIntValue(value!, path + "." + name)
}

function jsonDoubleValue(value: JsonValue, path: string): Result<double, GltfError> {
  narrowed := value as double else {
    return Failure(gltfError("json", path, "Expected number"))
  }
  return Success(narrowed)
}

function jsonDoubleField(object: JsonObject, name: string, defaultValue: double, path: string): Result<double, GltfError> {
  value := jsonField(object, name)
  if value == null {
    return Success(defaultValue)
  }

  return jsonDoubleValue(value!, path + "." + name)
}

function jsonIntArrayField(object: JsonObject, name: string, path: string): Result<int[], GltfError> {
  result: int[] := []
  try maybeArray := jsonArrayField(object, name, path)
  if maybeArray == null {
    return Success(result)
  }

  array := maybeArray!
  for index of 0..<array.length {
    try value := jsonIntValue(array[index], `${path}.${name}[${index}]`)
    result.push(value)
  }
  return Success(result)
}

function jsonDoubleArrayField(object: JsonObject, name: string, path: string): Result<double[], GltfError> {
  result: double[] := []
  try maybeArray := jsonArrayField(object, name, path)
  if maybeArray == null {
    return Success(result)
  }

  array := maybeArray!
  for index of 0..<array.length {
    try value := jsonDoubleValue(array[index], `${path}.${name}[${index}]`)
    result.push(value)
  }
  return Success(result)
}

function parseBuffers(root: JsonObject, warnings: GltfWarning[]): Result<GltfBuffer[], GltfError> {
  result: GltfBuffer[] := []
  try maybeBuffers := jsonArrayField(root, "buffers", "$")
  if maybeBuffers == null {
    return Success(result)
  }

  buffers := maybeBuffers!
  for index of 0..<buffers.length {
    path := `$.buffers[${index}]`
    object := buffers[index] as JsonObject else {
      return Failure(gltfError("json", path, "Expected buffer object"))
    }
    try uri := jsonStringField(object, "uri", path)
    if uri != null {
      warnings.push(gltfWarning("json", path + ".uri", "External glTF buffers are not loaded by GLB v1"))
    }
    try byteLength := jsonIntField(object, "byteLength", 0, path)
    result.push(GltfBuffer {
      byteLength,
      uri,
    })
  }
  return Success(result)
}

function parseBufferViews(root: JsonObject): Result<GltfBufferView[], GltfError> {
  result: GltfBufferView[] := []
  try maybeViews := jsonArrayField(root, "bufferViews", "$")
  if maybeViews == null {
    return Success(result)
  }

  views := maybeViews!
  for index of 0..<views.length {
    path := `$.bufferViews[${index}]`
    object := views[index] as JsonObject else {
      return Failure(gltfError("json", path, "Expected bufferView object"))
    }
    try buffer := jsonIntField(object, "buffer", 0, path)
    try byteOffset := jsonIntField(object, "byteOffset", 0, path)
    try byteLength := jsonIntField(object, "byteLength", 0, path)
    try byteStride := jsonIntField(object, "byteStride", 0, path)
    result.push(GltfBufferView { buffer, byteOffset, byteLength, byteStride })
  }
  return Success(result)
}

function parseAccessors(root: JsonObject, warnings: GltfWarning[]): Result<GltfAccessor[], GltfError> {
  result: GltfAccessor[] := []
  try maybeAccessors := jsonArrayField(root, "accessors", "$")
  if maybeAccessors == null {
    return Success(result)
  }

  accessors := maybeAccessors!
  for index of 0..<accessors.length {
    path := `$.accessors[${index}]`
    object := accessors[index] as JsonObject else {
      return Failure(gltfError("json", path, "Expected accessor object"))
    }
    sparse := jsonField(object, "sparse") != null
    if sparse {
      warnings.push(gltfWarning("json", path + ".sparse", "Sparse accessors are preserved as metadata but are not converted to SimpleMeshSpec"))
    }
    try bufferView := jsonIntField(object, "bufferView", -1, path)
    try byteOffset := jsonIntField(object, "byteOffset", 0, path)
    try componentType := jsonIntField(object, "componentType", 0, path)
    try count := jsonIntField(object, "count", 0, path)
    try maybeTypeName := jsonStringField(object, "type", path)
    typeName := maybeTypeName ?? ""
    try normalized := jsonBoolField(object, "normalized", false, path)
    result.push(GltfAccessor {
      bufferView,
      byteOffset,
      componentType,
      count,
      typeName,
      normalized,
      sparse,
    })
  }
  return Success(result)
}

function parsePrimitive(object: JsonObject, path: string, warnings: GltfWarning[]): Result<GltfPrimitive, GltfError> {
  try attributesObject := jsonObjectField(object, "attributes", path)
  attributes: Map<string, int> := {}
  if attributesObject != null {
    for key, value of attributesObject! {
      try attributeIndex := jsonIntValue(value, path + ".attributes." + key)
      attributes.set(key, attributeIndex)
    }
  }

  try mode := jsonIntField(object, "mode", GLTF_MODE_TRIANGLES, path)
  if mode != GLTF_MODE_TRIANGLES {
    warnings.push(gltfWarning("convert", path + ".mode", "Only triangle primitives are converted to SimpleMeshSpec"))
  }

  if jsonField(object, "targets") != null {
    warnings.push(gltfWarning("convert", path + ".targets", "Morph targets are preserved as metadata but are not converted to SimpleMeshSpec"))
  }

  if jsonField(object, "material") != null {
    warnings.push(gltfWarning("convert", path + ".material", "Materials are preserved as metadata but are not applied to SimpleMeshSpec"))
  }

  try indices := jsonIntField(object, "indices", -1, path)
  try material := jsonIntField(object, "material", -1, path)
  return Success(GltfPrimitive {
    attributes,
    indices,
    mode,
    material,
    hasTargets: jsonField(object, "targets") != null,
  })
}

function parseMeshes(root: JsonObject, warnings: GltfWarning[]): Result<GltfMesh[], GltfError> {
  result: GltfMesh[] := []
  try maybeMeshes := jsonArrayField(root, "meshes", "$")
  if maybeMeshes == null {
    return Success(result)
  }

  meshes := maybeMeshes!
  for meshIndex of 0..<meshes.length {
    path := `$.meshes[${meshIndex}]`
    object := meshes[meshIndex] as JsonObject else {
      return Failure(gltfError("json", path, "Expected mesh object"))
    }
    primitives: GltfPrimitive[] := []
    try maybePrimitives := jsonArrayField(object, "primitives", path)
    if maybePrimitives != null {
      values := maybePrimitives!
      for primitiveIndex of 0..<values.length {
        primitivePath := `${path}.primitives[${primitiveIndex}]`
        primitiveObject := values[primitiveIndex] as JsonObject else {
          return Failure(gltfError("json", primitivePath, "Expected primitive object"))
        }
        try primitive := parsePrimitive(primitiveObject, primitivePath, warnings)
        primitives.push(primitive)
      }
    }
    try name := jsonStringField(object, "name", path)
    result.push(GltfMesh { name, primitives })
  }
  return Success(result)
}

function parseNodes(root: JsonObject): Result<GltfNode[], GltfError> {
  result: GltfNode[] := []
  try maybeNodes := jsonArrayField(root, "nodes", "$")
  if maybeNodes == null {
    return Success(result)
  }

  nodes := maybeNodes!
  for index of 0..<nodes.length {
    path := `$.nodes[${index}]`
    object := nodes[index] as JsonObject else {
      return Failure(gltfError("json", path, "Expected node object"))
    }
    try name := jsonStringField(object, "name", path)
    try mesh := jsonIntField(object, "mesh", -1, path)
    try children := jsonIntArrayField(object, "children", path)
    result.push(GltfNode { name, mesh, children })
  }
  return Success(result)
}

function parseScenes(root: JsonObject): Result<GltfScene[], GltfError> {
  result: GltfScene[] := []
  try maybeScenes := jsonArrayField(root, "scenes", "$")
  if maybeScenes == null {
    return Success(result)
  }

  scenes := maybeScenes!
  for index of 0..<scenes.length {
    path := `$.scenes[${index}]`
    object := scenes[index] as JsonObject else {
      return Failure(gltfError("json", path, "Expected scene object"))
    }
    try name := jsonStringField(object, "name", path)
    try nodes := jsonIntArrayField(object, "nodes", path)
    result.push(GltfScene { name, nodes })
  }
  return Success(result)
}

function parseSamplers(root: JsonObject): Result<GltfSampler[], GltfError> {
  result: GltfSampler[] := []
  try maybeSamplers := jsonArrayField(root, "samplers", "$")
  if maybeSamplers == null {
    return Success(result)
  }

  samplers := maybeSamplers!
  for index of 0..<samplers.length {
    path := `$.samplers[${index}]`
    object := samplers[index] as JsonObject else {
      return Failure(gltfError("json", path, "Expected sampler object"))
    }
    try name := jsonStringField(object, "name", path)
    try magFilter := jsonIntField(object, "magFilter", -1, path)
    try minFilter := jsonIntField(object, "minFilter", -1, path)
    try wrapS := jsonIntField(object, "wrapS", 10497, path)
    try wrapT := jsonIntField(object, "wrapT", 10497, path)
    result.push(GltfSampler { name, magFilter, minFilter, wrapS, wrapT })
  }
  return Success(result)
}

function parseImages(root: JsonObject, warnings: GltfWarning[]): Result<GltfImage[], GltfError> {
  result: GltfImage[] := []
  try maybeImages := jsonArrayField(root, "images", "$")
  if maybeImages == null {
    return Success(result)
  }

  images := maybeImages!
  for index of 0..<images.length {
    path := `$.images[${index}]`
    object := images[index] as JsonObject else {
      return Failure(gltfError("json", path, "Expected image object"))
    }
    try name := jsonStringField(object, "name", path)
    try uri := jsonStringField(object, "uri", path)
    try mimeType := jsonStringField(object, "mimeType", path)
    try bufferView := jsonIntField(object, "bufferView", -1, path)
    if uri != null {
      warnings.push(gltfWarning("json", path + ".uri", "External glTF images are recorded but not decoded by GLB v1"))
    }
    result.push(GltfImage { name, uri, mimeType, bufferView })
  }
  return Success(result)
}

function parseTextures(root: JsonObject): Result<GltfTexture[], GltfError> {
  result: GltfTexture[] := []
  try maybeTextures := jsonArrayField(root, "textures", "$")
  if maybeTextures == null {
    return Success(result)
  }

  textures := maybeTextures!
  for index of 0..<textures.length {
    path := `$.textures[${index}]`
    object := textures[index] as JsonObject else {
      return Failure(gltfError("json", path, "Expected texture object"))
    }
    try name := jsonStringField(object, "name", path)
    try sampler := jsonIntField(object, "sampler", -1, path)
    try source := jsonIntField(object, "source", -1, path)
    result.push(GltfTexture { name, sampler, source })
  }
  return Success(result)
}

function parseTextureInfo(object: JsonObject, name: string, path: string): Result<GltfTextureInfo | null, GltfError> {
  try maybeInfo := jsonObjectField(object, name, path)
  if maybeInfo == null {
    return Success(null)
  }

  info := maybeInfo!
  infoPath := path + "." + name
  try index := jsonIntField(info, "index", -1, infoPath)
  try texCoord := jsonIntField(info, "texCoord", 0, infoPath)
  try scale := jsonDoubleField(info, "scale", 1.0, infoPath)
  try strength := jsonDoubleField(info, "strength", 1.0, infoPath)
  return Success(GltfTextureInfo { index, texCoord, scale, strength })
}

function parseFactorColor(object: JsonObject, name: string, defaultColor: Color, path: string): Result<Color, GltfError> {
  try values := jsonDoubleArrayField(object, name, path)
  if values.length == 0 {
    return Success(defaultColor)
  }
  if values.length < 3 {
    return Failure(gltfError("json", path + "." + name, "Expected at least three color components"))
  }
  alpha := if values.length >= 4 then values[3] else defaultColor.a
  return Success(Color(values[0], values[1], values[2], alpha))
}

function parseMaterials(root: JsonObject): Result<GltfMaterial[], GltfError> {
  result: GltfMaterial[] := []
  try maybeMaterials := jsonArrayField(root, "materials", "$")
  if maybeMaterials == null {
    return Success(result)
  }

  materials := maybeMaterials!
  for index of 0..<materials.length {
    path := `$.materials[${index}]`
    object := materials[index] as JsonObject else {
      return Failure(gltfError("json", path, "Expected material object"))
    }

    try pbr := jsonObjectField(object, "pbrMetallicRoughness", path)
    emptyPbr: JsonObject := {}
    pbrObject := pbr ?? emptyPbr
    try name := jsonStringField(object, "name", path)
    try baseColorFactor := parseFactorColor(pbrObject, "baseColorFactor", Color.white, path + ".pbrMetallicRoughness")
    try baseColorTexture := parseTextureInfo(pbrObject, "baseColorTexture", path + ".pbrMetallicRoughness")
    try metallicFactor := jsonDoubleField(pbrObject, "metallicFactor", 1.0, path + ".pbrMetallicRoughness")
    try roughnessFactor := jsonDoubleField(pbrObject, "roughnessFactor", 1.0, path + ".pbrMetallicRoughness")
    try metallicRoughnessTexture := parseTextureInfo(pbrObject, "metallicRoughnessTexture", path + ".pbrMetallicRoughness")
    try normalTexture := parseTextureInfo(object, "normalTexture", path)
    try occlusionTexture := parseTextureInfo(object, "occlusionTexture", path)
    try emissiveTexture := parseTextureInfo(object, "emissiveTexture", path)
    try emissiveFactor := parseFactorColor(object, "emissiveFactor", Color.black, path)
    try maybeAlphaMode := jsonStringField(object, "alphaMode", path)
    alphaMode := maybeAlphaMode ?? "OPAQUE"
    try alphaCutoff := jsonDoubleField(object, "alphaCutoff", 0.5, path)
    try doubleSided := jsonBoolField(object, "doubleSided", false, path)
    result.push(GltfMaterial {
      name,
      baseColorFactor,
      baseColorTexture,
      metallicFactor,
      roughnessFactor,
      metallicRoughnessTexture,
      normalTexture,
      occlusionTexture,
      emissiveTexture,
      emissiveFactor,
      alphaMode,
      alphaCutoff,
      doubleSided,
    })
  }
  return Success(result)
}

function parseAnimationTarget(object: JsonObject, path: string): Result<GltfAnimationTarget, GltfError> {
  try maybeTarget := jsonObjectField(object, "target", path)
  target := maybeTarget else {
    return Failure(gltfError("json", path + ".target", "Animation channel target is required"))
  }
  try node := jsonIntField(target, "node", -1, path + ".target")
  try maybeTargetPath := jsonStringField(target, "path", path + ".target")
  targetPath := maybeTargetPath ?? ""
  return Success(GltfAnimationTarget { node, path: targetPath })
}

function parseAnimations(root: JsonObject): Result<GltfAnimation[], GltfError> {
  result: GltfAnimation[] := []
  try maybeAnimations := jsonArrayField(root, "animations", "$")
  if maybeAnimations == null {
    return Success(result)
  }

  animations := maybeAnimations!
  for animationIndex of 0..<animations.length {
    path := `$.animations[${animationIndex}]`
    object := animations[animationIndex] as JsonObject else {
      return Failure(gltfError("json", path, "Expected animation object"))
    }
    try name := jsonStringField(object, "name", path)
    animationSamplers: GltfAnimationSampler[] := []
    try maybeSamplers := jsonArrayField(object, "samplers", path)
    if maybeSamplers != null {
      samplers := maybeSamplers!
      for samplerIndex of 0..<samplers.length {
        samplerPath := `${path}.samplers[${samplerIndex}]`
        samplerObject := samplers[samplerIndex] as JsonObject else {
          return Failure(gltfError("json", samplerPath, "Expected animation sampler object"))
        }
        try input := jsonIntField(samplerObject, "input", -1, samplerPath)
        try output := jsonIntField(samplerObject, "output", -1, samplerPath)
        try maybeInterpolation := jsonStringField(samplerObject, "interpolation", samplerPath)
        interpolation := maybeInterpolation ?? "LINEAR"
        animationSamplers.push(GltfAnimationSampler { input, output, interpolation })
      }
    }

    channels: GltfAnimationChannel[] := []
    try maybeChannels := jsonArrayField(object, "channels", path)
    if maybeChannels != null {
      channelValues := maybeChannels!
      for channelIndex of 0..<channelValues.length {
        channelPath := `${path}.channels[${channelIndex}]`
        channelObject := channelValues[channelIndex] as JsonObject else {
          return Failure(gltfError("json", channelPath, "Expected animation channel object"))
        }
        try sampler := jsonIntField(channelObject, "sampler", -1, channelPath)
        try target := parseAnimationTarget(channelObject, channelPath)
        channels.push(GltfAnimationChannel { sampler, target })
      }
    }
    result.push(GltfAnimation { name, samplers: animationSamplers, channels })
  }
  return Success(result)
}

function arrayLength(root: JsonObject, name: string): Result<int, GltfError> {
  try maybeArray := jsonArrayField(root, name, "$")
  if maybeArray == null {
    return Success(0)
  }
  array := maybeArray!
  return Success(array.length)
}

function validateRead(offset: int, length: int, totalLength: int, path: string): Result<void, GltfError> {
  if offset < 0 || length < 0 || offset > totalLength || offset + length > totalLength {
    return Failure(gltfError("binary", path, `Read of ${length} bytes at offset ${offset} exceeds ${totalLength} bytes`))
  }
  return Success()
}

function readFloatAt(data: readonly byte[], offset: int, path: string): Result<double, GltfError> {
  try validateRead(offset, 4, data.length, path)
  reader := BlobReader { data, endianness: Endian.LittleEndian }
  reader.setPosition(long(offset))
  return Success(double(reader.readFloat()))
}

function readIndexAt(data: readonly byte[], componentType: int, offset: int, path: string): Result<int, GltfError> {
  reader := BlobReader { data, endianness: Endian.LittleEndian }
  reader.setPosition(long(offset))
  if componentType == GLTF_COMPONENT_UNSIGNED_BYTE {
    try validateRead(offset, 1, data.length, path)
    return Success(int(reader.readByte()))
  }
  if componentType == GLTF_COMPONENT_UNSIGNED_SHORT {
    try validateRead(offset, 2, data.length, path)
    return Success(reader.readUnsignedShort())
  }
  if componentType == GLTF_COMPONENT_UNSIGNED_INT {
    try validateRead(offset, 4, data.length, path)
    value := reader.readUnsignedInt()
    if value > 2147483647L {
      return Failure(gltfError("convert", path, "Index value exceeds Doof int range"))
    }
    return Success(int(value))
  }
  return Failure(gltfError("convert", path, "Unsupported index component type"))
}

function componentCount(typeName: string): int {
  if typeName == "SCALAR" {
    return 1
  }
  if typeName == "VEC2" {
    return 2
  }
  if typeName == "VEC3" {
    return 3
  }
  if typeName == "VEC4" {
    return 4
  }
  if typeName == "MAT2" {
    return 4
  }
  if typeName == "MAT3" {
    return 9
  }
  if typeName == "MAT4" {
    return 16
  }
  return 0
}

function componentByteSize(componentType: int): int {
  if componentType == GLTF_COMPONENT_UNSIGNED_BYTE {
    return 1
  }
  if componentType == GLTF_COMPONENT_UNSIGNED_SHORT {
    return 2
  }
  if componentType == GLTF_COMPONENT_UNSIGNED_INT || componentType == GLTF_COMPONENT_FLOAT {
    return 4
  }
  return 0
}

function accessorStride(accessor: GltfAccessor, view: GltfBufferView): int {
  if view.byteStride > 0 {
    return view.byteStride
  }
  return componentCount(accessor.typeName) * componentByteSize(accessor.componentType)
}

function accessorByteOffset(asset: GltfAsset, accessorIndex: int, path: string): Result<int, GltfError> {
  if accessorIndex < 0 || accessorIndex >= asset.accessors.length {
    return Failure(gltfError("convert", path, "Accessor index is out of range"))
  }
  accessor := asset.accessors[accessorIndex]
  if accessor.bufferView < 0 || accessor.bufferView >= asset.bufferViews.length {
    return Failure(gltfError("convert", path, "Accessor bufferView is missing or out of range"))
  }
  view := asset.bufferViews[accessor.bufferView]
  if view.buffer != 0 {
    return Failure(gltfError("convert", path, "Only the embedded GLB BIN buffer is supported"))
  }
  return Success(view.byteOffset + accessor.byteOffset)
}

function usableFloatAccessor(asset: GltfAsset, accessorIndex: int, expectedType: string, path: string): Result<bool, GltfError> {
  if accessorIndex < 0 || accessorIndex >= asset.accessors.length {
    return Failure(gltfError("convert", path, "Accessor index is out of range"))
  }
  accessor := asset.accessors[accessorIndex]
  if accessor.componentType != GLTF_COMPONENT_FLOAT || accessor.typeName != expectedType {
    asset.warnings.push(gltfWarning("convert", path, `Unsupported accessor format; expected ${expectedType} float data`))
    return Success(false)
  }
  if accessor.sparse {
    asset.warnings.push(gltfWarning("convert", path, "Sparse accessor ignored during SimpleMeshSpec conversion"))
    return Success(false)
  }
  return Success(true)
}

function usableColorAccessor(asset: GltfAsset, accessorIndex: int, path: string): Result<bool, GltfError> {
  if accessorIndex < 0 || accessorIndex >= asset.accessors.length {
    return Failure(gltfError("convert", path, "Accessor index is out of range"))
  }
  accessor := asset.accessors[accessorIndex]
  if accessor.componentType != GLTF_COMPONENT_FLOAT || (accessor.typeName != "VEC3" && accessor.typeName != "VEC4") {
    asset.warnings.push(gltfWarning("convert", path, "Unsupported color accessor format; expected VEC3 or VEC4 float data"))
    return Success(false)
  }
  if accessor.sparse {
    asset.warnings.push(gltfWarning("convert", path, "Sparse color accessor ignored during SimpleMeshSpec conversion"))
    return Success(false)
  }
  return Success(true)
}

function usableIndexAccessor(asset: GltfAsset, accessorIndex: int, path: string): Result<bool, GltfError> {
  if accessorIndex < 0 || accessorIndex >= asset.accessors.length {
    return Failure(gltfError("convert", path, "Index accessor is out of range"))
  }
  accessor := asset.accessors[accessorIndex]
  if accessor.typeName != "SCALAR" || accessor.sparse {
    asset.warnings.push(gltfWarning("convert", path, "Unsupported index accessor; expected non-sparse scalar indices"))
    return Success(false)
  }
  if accessor.componentType != GLTF_COMPONENT_UNSIGNED_BYTE &&
     accessor.componentType != GLTF_COMPONENT_UNSIGNED_SHORT &&
     accessor.componentType != GLTF_COMPONENT_UNSIGNED_INT {
    asset.warnings.push(gltfWarning("convert", path, "Unsupported index component type"))
    return Success(false)
  }
  return Success(true)
}

function readFloatComponent(asset: GltfAsset, accessorIndex: int, elementIndex: int, componentIndex: int, path: string): Result<double, GltfError> {
  accessor := asset.accessors[accessorIndex]
  view := asset.bufferViews[accessor.bufferView]
  stride := accessorStride(accessor, view)
  if stride <= 0 {
    return Failure(gltfError("convert", path, "Accessor stride is invalid"))
  }
  try base := accessorByteOffset(asset, accessorIndex, path)
  offset := base + elementIndex * stride + componentIndex * 4
  return readFloatAt(asset.binChunk, offset, path)
}

function readPoint3(asset: GltfAsset, accessorIndex: int, elementIndex: int, path: string): Result<Point3, GltfError> {
  try x := readFloatComponent(asset, accessorIndex, elementIndex, 0, path)
  try y := readFloatComponent(asset, accessorIndex, elementIndex, 1, path)
  try z := readFloatComponent(asset, accessorIndex, elementIndex, 2, path)
  return Success(Point3(x, y, z))
}

function readPoint(asset: GltfAsset, accessorIndex: int, elementIndex: int, path: string): Result<Point, GltfError> {
  try x := readFloatComponent(asset, accessorIndex, elementIndex, 0, path)
  try y := readFloatComponent(asset, accessorIndex, elementIndex, 1, path)
  return Success(Point(x, y))
}

function readColor(asset: GltfAsset, accessorIndex: int, elementIndex: int, fallbackAlpha: double, path: string): Result<Color, GltfError> {
  accessor := asset.accessors[accessorIndex]
  try r := readFloatComponent(asset, accessorIndex, elementIndex, 0, path)
  try g := readFloatComponent(asset, accessorIndex, elementIndex, 1, path)
  try b := readFloatComponent(asset, accessorIndex, elementIndex, 2, path)
  if accessor.typeName == "VEC4" {
    try a := readFloatComponent(asset, accessorIndex, elementIndex, 3, path)
    return Success(Color(r, g, b, a))
  }
  return Success(Color(r, g, b, fallbackAlpha))
}

function readIndex(asset: GltfAsset, accessorIndex: int, elementIndex: int, path: string): Result<int, GltfError> {
  accessor := asset.accessors[accessorIndex]
  view := asset.bufferViews[accessor.bufferView]
  stride := accessorStride(accessor, view)
  if stride <= 0 {
    return Failure(gltfError("convert", path, "Index accessor stride is invalid"))
  }
  try base := accessorByteOffset(asset, accessorIndex, path)
  return readIndexAt(asset.binChunk, accessor.componentType, base + elementIndex * stride, path)
}

function point3Minus(a: Point3, b: Point3): Point3 {
  return Point3(a.x - b.x, a.y - b.y, a.z - b.z)
}

function cross(a: Point3, b: Point3): Point3 {
  return Point3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x,
  )
}

function normalizePoint3(value: Point3): Point3 {
  length := sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
  if length <= EPSILON {
    return Point3(0.0, 0.0, 1.0)
  }
  return Point3(value.x / length, value.y / length, value.z / length)
}

function triangleNormal(a: Point3, b: Point3, c: Point3): Point3 {
  return normalizePoint3(cross(point3Minus(b, a), point3Minus(c, a)))
}

function primitiveAttribute(primitive: GltfPrimitive, name: string): int {
  return case primitive.attributes.get(name) {
    s: Success -> s.value,
    _: Failure -> -1,
  }
}

function primitiveVertexSourceIndex(asset: GltfAsset, primitive: GltfPrimitive, positionAccessor: int, outputIndex: int, path: string): Result<int, GltfError> {
  if primitive.indices >= 0 {
    return readIndex(asset, primitive.indices, outputIndex, path + ".indices")
  }
  if outputIndex < 0 || outputIndex >= asset.accessors[positionAccessor].count {
    return Failure(gltfError("convert", path, "Generated vertex index is out of range"))
  }
  return Success(outputIndex)
}

function convertPrimitive(asset: GltfAsset, meshIndex: int, primitiveIndex: int, color: Color): Result<GltfSimpleMeshSpec | null, GltfError> {
  mesh := asset.meshes[meshIndex]
  primitive := mesh.primitives[primitiveIndex]
  path := `$.meshes[${meshIndex}].primitives[${primitiveIndex}]`
  if primitive.mode != GLTF_MODE_TRIANGLES {
    return Success(null)
  }

  positionAccessor := primitiveAttribute(primitive, "POSITION")
  if positionAccessor < 0 {
    return Success(null)
  }
  try positionUsable := usableFloatAccessor(asset, positionAccessor, "VEC3", path + ".attributes.POSITION")
  if !positionUsable {
    return Success(null)
  }

  let normalAccessor = primitiveAttribute(primitive, "NORMAL")
  if normalAccessor >= 0 {
    try normalUsable := usableFloatAccessor(asset, normalAccessor, "VEC3", path + ".attributes.NORMAL")
    if !normalUsable {
      normalAccessor = -1
    }
  }

  let uvAccessor = primitiveAttribute(primitive, "TEXCOORD_0")
  if uvAccessor >= 0 {
    try uvUsable := usableFloatAccessor(asset, uvAccessor, "VEC2", path + ".attributes.TEXCOORD_0")
    if !uvUsable {
      uvAccessor = -1
    }
  }

  let colorAccessor = primitiveAttribute(primitive, "COLOR_0")
  if colorAccessor >= 0 {
    try colorUsable := usableColorAccessor(asset, colorAccessor, path + ".attributes.COLOR_0")
    if !colorUsable {
      colorAccessor = -1
    }
  }

  if primitive.indices >= 0 {
    try indicesUsable := usableIndexAccessor(asset, primitive.indices, path + ".indices")
    if !indicesUsable {
      return Success(null)
    }
  }

  vertexSourceCount := if primitive.indices >= 0 then asset.accessors[primitive.indices].count else asset.accessors[positionAccessor].count
  if vertexSourceCount == 0 || vertexSourceCount % 3 != 0 {
    return Failure(gltfError("convert", path, "Triangle primitive vertex count must be a non-zero multiple of 3"))
  }

  positions: Point3[] := []
  indices: int[] := []
  colors: Color[] := []
  uvs: Point[] := []
  normals: Point3[] := []

  let outIndex = 0
  while outIndex < vertexSourceCount {
    try i0 := primitiveVertexSourceIndex(asset, primitive, positionAccessor, outIndex, path)
    try i1 := primitiveVertexSourceIndex(asset, primitive, positionAccessor, outIndex + 1, path)
    try i2 := primitiveVertexSourceIndex(asset, primitive, positionAccessor, outIndex + 2, path)
    try p0 := readPoint3(asset, positionAccessor, i0, path + ".POSITION")
    try p1 := readPoint3(asset, positionAccessor, i1, path + ".POSITION")
    try p2 := readPoint3(asset, positionAccessor, i2, path + ".POSITION")
    fallbackNormal := triangleNormal(p0, p1, p2)

    sourceIndices: int[] := [i0, i1, i2]
    trianglePositions: Point3[] := [p0, p1, p2]
    for localIndex of 0..<3 {
      sourceIndex := sourceIndices[localIndex]
      positions.push(trianglePositions[localIndex])
      indices.push(positions.length - 1)

      if colorAccessor >= 0 {
        try vertexColor := readColor(asset, colorAccessor, sourceIndex, color.a, path + ".COLOR_0")
        colors.push(vertexColor)
      } else {
        colors.push(color)
      }

      if uvAccessor >= 0 {
        try uv := readPoint(asset, uvAccessor, sourceIndex, path + ".TEXCOORD_0")
        uvs.push(uv)
      } else {
        uvs.push(Point(0.0, 0.0))
      }

      if normalAccessor >= 0 {
        try normal := readPoint3(asset, normalAccessor, sourceIndex, path + ".NORMAL")
        normals.push(normalizePoint3(normal))
      } else {
        normals.push(fallbackNormal)
      }
    }

    outIndex += 3
  }

  return Success(GltfSimpleMeshSpec {
    meshIndex,
    primitiveIndex,
    name: mesh.name,
    spec: SimpleMeshSpec { positions, indices, colors, uvs, normals },
  })
}

function buildAsset(source: string, root: JsonObject, binChunk: readonly byte[], warnings: GltfWarning[]): Result<GltfAsset, GltfError> {
  try buffers := parseBuffers(root, warnings)
  try bufferViews := parseBufferViews(root)
  try accessors := parseAccessors(root, warnings)
  try meshes := parseMeshes(root, warnings)
  try nodes := parseNodes(root)
  try scenes := parseScenes(root)
  try samplers := parseSamplers(root)
  try images := parseImages(root, warnings)
  try textures := parseTextures(root)
  try materials := parseMaterials(root)
  try animations := parseAnimations(root)
  try animationsCount := arrayLength(root, "animations")
  try skinsCount := arrayLength(root, "skins")

  if animationsCount > 0 {
    warnings.push(gltfWarning("json", "$.animations", "Animations are preserved as metadata but are not evaluated by GLB v1"))
  }
  if skinsCount > 0 {
    warnings.push(gltfWarning("json", "$.skins", "Skins are preserved as metadata but are not converted to SimpleMeshSpec"))
  }

  if buffers.length > 0 && buffers[0].byteLength > binChunk.length {
    return Failure(gltfError("binary", "$.buffers[0].byteLength", "GLB BIN chunk is shorter than the declared buffer"))
  }

  return Success(GltfAsset {
    source,
    json: root,
    binChunk,
    buffers,
    bufferViews,
    accessors,
    meshes,
    nodes,
    scenes,
    samplers,
    images,
    textures,
    materials,
    animations,
    animationsCount,
    skinsCount,
    warnings,
  })
}

export function parseGlb(data: readonly byte[], source: string = "input"): Result<GltfAsset, GltfError> {
  if data.length < 12 {
    return Failure(gltfError("binary", source, "GLB data is shorter than the 12-byte header"))
  }

  reader := BlobReader { data, endianness: Endian.LittleEndian }
  magic := reader.readInt()
  if magic != GLB_MAGIC {
    return Failure(gltfError("binary", source, "GLB magic must be glTF"))
  }
  version := reader.readInt()
  if version != GLB_VERSION {
    return Failure(gltfError("binary", source, `Unsupported GLB version ${version}; expected 2`))
  }
  declaredLength := reader.readInt()
  if declaredLength != data.length {
    return Failure(gltfError("binary", source, `GLB declared length ${declaredLength} does not match ${data.length} bytes`))
  }

  warnings: GltfWarning[] := []
  let jsonText: string | null = null
  let binChunk: readonly byte[] = []
  let chunkIndex = 0
  while reader.getPosition() < reader.length() {
    if reader.remaining() < 8L {
      return Failure(gltfError("binary", `${source}.chunks[${chunkIndex}]`, "Chunk header is truncated"))
    }
    chunkLength := reader.readInt()
    chunkType := reader.readInt()
    if chunkLength < 0 {
      return Failure(gltfError("binary", `${source}.chunks[${chunkIndex}]`, "Chunk length is negative"))
    }
    if reader.remaining() < long(chunkLength) {
      return Failure(gltfError("binary", `${source}.chunks[${chunkIndex}]`, "Chunk data is truncated"))
    }

    if chunkType == GLB_CHUNK_JSON {
      if jsonText != null {
        warnings.push(gltfWarning("binary", `${source}.chunks[${chunkIndex}]`, "Duplicate JSON chunk ignored"))
        reader.skip(long(chunkLength))
      } else {
        case reader.readText(long(chunkLength), .Utf8) {
          s: Success -> {
            jsonText = s.value
          }
          _: Failure -> return Failure(gltfError("binary", `${source}.chunks[${chunkIndex}]`, "JSON chunk is not valid UTF-8"))
        }
      }
    } else if chunkType == GLB_CHUNK_BIN {
      if binChunk.length > 0 {
        warnings.push(gltfWarning("binary", `${source}.chunks[${chunkIndex}]`, "Duplicate BIN chunk ignored"))
        reader.skip(long(chunkLength))
      } else {
        binChunk = reader.readBytes(long(chunkLength))
      }
    } else {
      warnings.push(gltfWarning("binary", `${source}.chunks[${chunkIndex}]`, `Unknown GLB chunk type ${chunkType} ignored`))
      reader.skip(long(chunkLength))
    }

    if chunkLength % 4 != 0 {
      warnings.push(gltfWarning("binary", `${source}.chunks[${chunkIndex}]`, "Chunk length is not 4-byte aligned"))
    }
    chunkIndex += 1
  }

  if jsonText == null {
    return Failure(gltfError("binary", source, "GLB is missing the required JSON chunk"))
  }

  json := parseJsonValue(jsonText!) else error {
    return Failure(gltfError("json", source, "Invalid GLB JSON: " + error))
  }
  root := json as JsonObject else {
    return Failure(gltfError("json", source, "GLB JSON root must be an object"))
  }

  return buildAsset(source, root, binChunk, warnings)
}

export function loadGlb(path: string): Result<GltfAsset, GltfError> {
  data := readBlob(path) else error {
    return Failure(gltfError("read", path, `${path}: failed to read GLB file: ${error}`))
  }
  return parseGlb(data, path)
}

export function glbAssetToSimpleMeshSpecs(
  asset: GltfAsset,
  color: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
): Result<GltfSimpleMeshSpec[], GltfError> {
  specs: GltfSimpleMeshSpec[] := []
  for meshIndex of 0..<asset.meshes.length {
    mesh := asset.meshes[meshIndex]
    for primitiveIndex of 0..<mesh.primitives.length {
      try converted := convertPrimitive(asset, meshIndex, primitiveIndex, color)
      if converted != null {
        specs.push(converted!)
      }
    }
  }

  if specs.length == 0 {
    return Failure(gltfError("convert", asset.source, "No supported static triangle mesh primitives were found"))
  }

  return Success(specs)
}
