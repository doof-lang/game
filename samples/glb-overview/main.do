import {
  GltfAnimation,
  GltfAsset,
  GltfMaterial,
  GltfPrimitive,
  glbAssetToSimpleMeshSpecs,
  loadGlb,
} from "std/game"

function nameOr(value: string | none, fallback: string): string {
  return value ?? fallback
}

function textureIndexText(index: int): string {
  return if index >= 0 then string(index) else "none"
}

function primitiveSummary(primitive: GltfPrimitive): string {
  position := if index := primitive.attributes.get("POSITION") then "${index}" else "missing"
  normal := if index := primitive.attributes.get("NORMAL") then "${index}" else "none"
  uv := if index := primitive.attributes.get("TEXCOORD_0") then "${index}" else "none"
  color := if index := primitive.attributes.get("COLOR_0") then "${index}" else "none"
  material := textureIndexText(primitive.material)
  indices := textureIndexText(primitive.indices)
  return "mode=${primitive.mode} material=${material} indices=${indices} " +
    "POSITION=${position} NORMAL=${normal} TEXCOORD_0=${uv} COLOR_0=${color}"
}

function printMaterials(asset: GltfAsset): none {
  println("Materials: ${asset.materials.length}")
  for index of 0..<asset.materials.length {
    material := asset.materials[index]
    baseTexture := textureIndexText(material.baseColorTexture?.index ?? -1)
    normalTexture := textureIndexText(material.normalTexture?.index ?? -1)
    color := material.baseColorFactor
    println("  [${index}] ${nameOr(material.name, "unnamed")}" +
      " baseColor=(${color.r}, ${color.g}, ${color.b}, ${color.a})" +
      " baseTexture=${baseTexture} normalTexture=${normalTexture}" +
      " metallic=${material.metallicFactor} roughness=${material.roughnessFactor}" +
      " alpha=${material.alphaMode} doubleSided=${material.doubleSided}")
  }
}

function printImagesAndTextures(asset: GltfAsset): none {
  println("Textures: ${asset.textures.length}")
  for index of 0..<asset.textures.length {
    texture := asset.textures[index]
    println("  [${index}] ${nameOr(texture.name, "unnamed")}" +
      " source=${textureIndexText(texture.source)} sampler=${textureIndexText(texture.sampler)}")
  }

  println("Images: ${asset.images.length}")
  for index of 0..<asset.images.length {
    image := asset.images[index]
    source := image.uri ?? "bufferView ${textureIndexText(image.bufferView)}"
    mimeType := image.mimeType ?? "unknown mime"
    println("  [${index}] ${nameOr(image.name, "unnamed")} ${mimeType} ${source}")
  }
}

function printMeshes(asset: GltfAsset): none {
  println("Meshes: ${asset.meshes.length}")
  for meshIndex of 0..<asset.meshes.length {
    mesh := asset.meshes[meshIndex]
    println("  [${meshIndex}] ${nameOr(mesh.name, "unnamed")} primitives=${mesh.primitives.length}")
    for primitiveIndex of 0..<mesh.primitives.length {
      println("    primitive [${primitiveIndex}] ${primitiveSummary(mesh.primitives[primitiveIndex])}")
    }
  }
}

function printAnimation(animation: GltfAnimation, index: int): none {
  println("  [${index}] ${nameOr(animation.name, "unnamed")} duration=${animation.duration}" +
    " samplers=${animation.samplers.length} channels=${animation.channels.length}")
  for channelIndex of 0..<animation.channels.length {
    channel := animation.channels[channelIndex]
    println("    channel [${channelIndex}] sampler=${channel.sampler}" +
      " node=${textureIndexText(channel.target.node)} path=${channel.target.path}")
  }
}

function printAnimations(asset: GltfAsset): none {
  println("Animations: ${asset.animations.length}")
  for index of 0..<asset.animations.length {
    printAnimation(asset.animations[index], index)
  }
}

function printWarnings(asset: GltfAsset): none {
  if asset.warnings.length == 0 {
    return
  }

  println("Warnings: ${asset.warnings.length}")
  for warning of asset.warnings {
    println("  ${warning.stage} ${warning.path}: ${warning.message}")
  }
}

function printOverview(path: string, asset: GltfAsset): none {
  println("== ${path} ==")
  specs := glbAssetToSimpleMeshSpecs(asset)
  case specs {
    s: Success -> println("Static mesh specs: ${s.value.length}")
    f: Failure -> println("Static mesh specs: 0 (${f.error.message})")
  }
  println("Buffers: ${asset.buffers.length} bufferViews: ${asset.bufferViews.length}" +
    " accessors: ${asset.accessors.length}")
  println("Nodes: ${asset.nodes.length} scenes: ${asset.scenes.length} skins: ${asset.skinsCount}")
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
      println("== ${path} ==")
      println("Failed to load: ${error.message}")
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
