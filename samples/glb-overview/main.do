import {
  GltfAnimation,
  GltfAsset,
  GltfMaterial,
  GltfPrimitive,
  glbAssetToSimpleMeshSpecs,
  loadGlb,
} from "std/game"

function nameOr(value: string | null, fallback: string): string {
  return value ?? fallback
}

function textureIndexText(index: int): string {
  return if index >= 0 then string(index) else "none"
}

function primitiveSummary(primitive: GltfPrimitive): string {
  position := case primitive.attributes.get("POSITION") {
    s: Success -> string(s.value),
    _: Failure -> "missing",
  }
  normal := case primitive.attributes.get("NORMAL") {
    s: Success -> string(s.value),
    _: Failure -> "none",
  }
  uv := case primitive.attributes.get("TEXCOORD_0") {
    s: Success -> string(s.value),
    _: Failure -> "none",
  }
  color := case primitive.attributes.get("COLOR_0") {
    s: Success -> string(s.value),
    _: Failure -> "none",
  }
  return "mode=" + string(primitive.mode) +
    " material=" + textureIndexText(primitive.material) +
    " indices=" + textureIndexText(primitive.indices) +
    " POSITION=" + position +
    " NORMAL=" + normal +
    " TEXCOORD_0=" + uv +
    " COLOR_0=" + color
}

function printMaterials(asset: GltfAsset): void {
  println("Materials: " + string(asset.materials.length))
  for index of 0..<asset.materials.length {
    material := asset.materials[index]
    baseTexture := if material.baseColorTexture != null then material.baseColorTexture!.index else -1
    normalTexture := if material.normalTexture != null then material.normalTexture!.index else -1
    println("  [" + string(index) + "] " + nameOr(material.name, "unnamed") +
      " baseColor=(" +
      string(material.baseColorFactor.r) + ", " +
      string(material.baseColorFactor.g) + ", " +
      string(material.baseColorFactor.b) + ", " +
      string(material.baseColorFactor.a) + ")" +
      " baseTexture=" + textureIndexText(baseTexture) +
      " normalTexture=" + textureIndexText(normalTexture) +
      " metallic=" + string(material.metallicFactor) +
      " roughness=" + string(material.roughnessFactor) +
      " alpha=" + material.alphaMode +
      " doubleSided=" + string(material.doubleSided))
  }
}

function printImagesAndTextures(asset: GltfAsset): void {
  println("Textures: " + string(asset.textures.length))
  for index of 0..<asset.textures.length {
    texture := asset.textures[index]
    println("  [" + string(index) + "] " + nameOr(texture.name, "unnamed") +
      " source=" + textureIndexText(texture.source) +
      " sampler=" + textureIndexText(texture.sampler))
  }

  println("Images: " + string(asset.images.length))
  for index of 0..<asset.images.length {
    image := asset.images[index]
    source := if image.uri != null then image.uri! else "bufferView " + textureIndexText(image.bufferView)
    println("  [" + string(index) + "] " + nameOr(image.name, "unnamed") +
      " " + (image.mimeType ?? "unknown mime") +
      " " + source)
  }
}

function printMeshes(asset: GltfAsset): void {
  println("Meshes: " + string(asset.meshes.length))
  for meshIndex of 0..<asset.meshes.length {
    mesh := asset.meshes[meshIndex]
    println("  [" + string(meshIndex) + "] " + nameOr(mesh.name, "unnamed") +
      " primitives=" + string(mesh.primitives.length))
    for primitiveIndex of 0..<mesh.primitives.length {
      println("    primitive [" + string(primitiveIndex) + "] " + primitiveSummary(mesh.primitives[primitiveIndex]))
    }
  }
}

function printAnimation(animation: GltfAnimation, index: int): void {
  println("  [" + string(index) + "] " + nameOr(animation.name, "unnamed") +
    " duration=" + string(animation.duration) +
    " samplers=" + string(animation.samplers.length) +
    " channels=" + string(animation.channels.length))
  for channelIndex of 0..<animation.channels.length {
    channel := animation.channels[channelIndex]
    println("    channel [" + string(channelIndex) + "] sampler=" + string(channel.sampler) +
      " node=" + textureIndexText(channel.target.node) +
      " path=" + channel.target.path)
  }
}

function printAnimations(asset: GltfAsset): void {
  println("Animations: " + string(asset.animations.length))
  for index of 0..<asset.animations.length {
    printAnimation(asset.animations[index], index)
  }
}

function printWarnings(asset: GltfAsset): void {
  if asset.warnings.length == 0 {
    return
  }

  println("Warnings: " + string(asset.warnings.length))
  for warning of asset.warnings {
    println("  " + warning.stage + " " + warning.path + ": " + warning.message)
  }
}

function printOverview(path: string, asset: GltfAsset): void {
  println("== " + path + " ==")
  specs := glbAssetToSimpleMeshSpecs(asset)
  case specs {
    s: Success -> println("Static mesh specs: " + string(s.value.length))
    f: Failure -> println("Static mesh specs: 0 (" + f.error.message + ")")
  }
  println("Buffers: " + string(asset.buffers.length) +
    " bufferViews: " + string(asset.bufferViews.length) +
    " accessors: " + string(asset.accessors.length))
  println("Nodes: " + string(asset.nodes.length) +
    " scenes: " + string(asset.scenes.length) +
    " skins: " + string(asset.skinsCount))
  printMeshes(asset)
  printMaterials(asset)
  printImagesAndTextures(asset)
  printAnimations(asset)
  printWarnings(asset)
}

function main(args: string[]): int {
  if args.length == 0 {
    println("Usage: doof run game/samples/glb-overview -- <file.glb> [more.glb ...]")
    return 1
  }

  let exitCode = 0
  for index of 0..<args.length {
    path := args[index]
    asset := loadGlb(path) else error {
      println("== " + path + " ==")
      println("Failed to load: " + error.message)
      exitCode = 1
      continue
    }
    printOverview(path, asset)
    if index < args.length - 1 {
      println("")
    }
  }

  return exitCode
}
