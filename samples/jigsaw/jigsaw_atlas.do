import { exists, metadata, readBlob, readText, writeBlob, writeText } from "std/fs"
import { GameApp, Texture } from "std/game"
import { Image, PixelAlphaMode, PixelBytes } from "std/image"
import { join } from "std/path"

import function composeJigsawAtlas(
  photo: readonly byte[],
  photoWidth: int,
  photoHeight: int,
  mask: readonly byte[],
  maskWidth: int,
  maskHeight: int,
  columns: int,
  rows: int,
): Result<readonly byte[], string> from "native_jigsaw_atlas.hpp" as doof_game_jigsaw::composeJigsawAtlas

function imageErrorMessage(operation: string, message: string): string {
  return "${operation}: ${message}"
}

const JIGSAW_ATLAS_CACHE_VERSION = 2

export function jigsawAtlasCachePath(
  cacheRoot: string,
  photoPath: string,
  maskAtlasPath: string,
  columns: int,
  rows: int,
): Result<string, string> {
  photoInfo := metadata(photoPath) else error {
    return Failure { error: "Could not inspect source photo for atlas cache: ${error.name}" }
  }
  maskInfo := metadata(maskAtlasPath) else error {
    return Failure { error: "Could not inspect mask atlas for cache: ${error.name}" }
  }
  filename := "jigsaw-atlas-v${JIGSAW_ATLAS_CACHE_VERSION}-${columns}x${rows}" +
    "-p${photoInfo.size}-${photoInfo.modifiedAt.toEpochNanos()}" +
    "-m${maskInfo.size}-${maskInfo.modifiedAt.toEpochNanos()}.rgba"
  return Success { value: join([cacheRoot, filename]) }
}

export function cacheJigsawAtlas(pixels: PixelBytes, cachePath: string): Result<void, string> {
  writeBlob(cachePath, pixels.bytes) else error {
    return Failure { error: "Could not write cached jigsaw atlas pixels: ${error.name}" }
  }
  writeText("${cachePath}.dimensions", "${pixels.width}x${pixels.height}") else error {
    return Failure { error: "Could not write cached jigsaw atlas dimensions: ${error.name}" }
  }
  return Success {}
}

export function loadCachedJigsawAtlas(cachePath: string): PixelBytes | null {
  dimensionsPath := "${cachePath}.dimensions"
  if !exists(cachePath) || !exists(dimensionsPath) {
    return null
  }
  dimensionsText := readText(dimensionsPath) else { return null }
  dimensions := dimensionsText.split("x")
  if dimensions.length != 2 {
    return null
  }
  width := int.parse(dimensions[0]) else { return null }
  height := int.parse(dimensions[1]) else { return null }
  if width <= 0 || height <= 0 {
    return null
  }
  bytes := readBlob(cachePath) else { return null }
  if long(bytes.length) != long(width) * long(height) * 4L {
    return null
  }
  return PixelBytes(width, height, bytes, PixelAlphaMode.Straight)
}

export function loadJigsawAtlasTexture(
  app: GameApp,
  photoPath: string,
  maskAtlasPath: string,
  cachePath: string | null,
  columns: int,
  rows: int,
): Result<Texture, string> {
  if cachePath != null {
    cachedPixels := loadCachedJigsawAtlas(cachePath!)
    if cachedPixels != null {
      cachedTexture := app.createTextureFromPixels(cachedPixels!) else error {
        return Failure { error: error }
      }
      return Success { value: cachedTexture }
    }
  }

  pixels := loadJigsawAtlasPixels(photoPath, maskAtlasPath, columns, rows) else error {
    return Failure { error: error }
  }
  texture := app.createTextureFromPixels(pixels) else error {
    return Failure { error: error }
  }

  if cachePath != null {
    cacheJigsawAtlas(pixels, cachePath!) else error {
      println(error)
    }
  }
  return Success { value: texture }
}

export function buildJigsawAtlas(
  photo: Image,
  maskAtlas: Image,
  columns: int,
  rows: int,
): Result<Image, string> {
  pixels := buildJigsawAtlasPixels(photo, maskAtlas, columns, rows) else error {
    return Failure { error: error }
  }
  atlas := Image.fromPixelBytes(pixels) else error {
    return Failure { error: imageErrorMessage("Could not create jigsaw atlas", error.message) }
  }
  return Success { value: atlas }
}

export function buildJigsawAtlasPixels(
  photo: Image,
  maskAtlas: Image,
  columns: int,
  rows: int,
): Result<PixelBytes, string> {
  if columns <= 0 || rows <= 0 {
    return Failure { error: "Jigsaw atlas dimensions must be positive" }
  }

  maskWidth := maskAtlas.width()
  maskHeight := maskAtlas.height()
  if maskWidth % columns != 0 || maskHeight % rows != 0 {
    return Failure { error: "Mask atlas size is not divisible by requested grid" }
  }

  cellWidth := maskWidth \ columns
  cellHeight := maskHeight \ rows
  if cellWidth <= 0 || cellHeight <= 0 {
    return Failure { error: "Mask atlas cells are empty" }
  }

  photoPixels := photo.pixelBytes() else error {
    return Failure { error: imageErrorMessage("Could not read source photo pixels", error.message) }
  }
  maskPixels := maskAtlas.pixelBytes() else error {
    return Failure { error: imageErrorMessage("Could not read mask atlas pixels", error.message) }
  }

  output := composeJigsawAtlas(
    photoPixels.bytes,
    photoPixels.width,
    photoPixels.height,
    maskPixels.bytes,
    maskPixels.width,
    maskPixels.height,
    columns,
    rows,
  ) else error { return Failure { error: error } }

  return Success {
    value: PixelBytes(maskWidth, maskHeight, output, PixelAlphaMode.Straight),
  }
}

export function loadJigsawAtlasPixels(
  photoPath: string,
  maskAtlasPath: string,
  columns: int,
  rows: int,
): Result<PixelBytes, string> {
  photo := Image.loadFile(photoPath) else error {
    return Failure { error: imageErrorMessage("Could not load source photo", error.message) }
  }
  maskAtlas := Image.loadFile(maskAtlasPath) else error {
    return Failure { error: imageErrorMessage("Could not load mask atlas", error.message) }
  }
  return buildJigsawAtlasPixels(photo, maskAtlas, columns, rows)
}
