import { Assert } from "std/assert"
import { remove, writeBlob } from "std/fs"
import { Image, PixelAlphaMode, PixelBytes } from "std/image"
import { join, tempDirectory } from "std/path"

import {
  buildJigsawAtlas,
  cacheJigsawAtlas,
  jigsawAtlasCachePath,
  loadCachedJigsawAtlas,
} from "./jigsaw_atlas"

function image(width: int, height: int, bytes: readonly byte[]): Image {
  return try! Image.fromPixelBytes(PixelBytes(width, height, bytes, PixelAlphaMode.Straight))
}

function assertBytes(actual: readonly byte[], expected: readonly byte[]): void {
  Assert.equal(actual.length, expected.length)
  for index of 0..<actual.length {
    assert(
      actual[index] == expected[index],
      "pixel byte mismatch at index ${index}: got ${actual[index]}, expected ${expected[index]}",
    )
  }
}

function failureMessage(result: Result<Image, string>): string {
  _ := result else error { return error }
  Assert.fail("expected atlas generation to fail")
  return ""
}

export function testAtlasUsesCenteredSquarePhotoCropAndMaskRgbMaximum(): void {
  photo := image(4, 2, [
    9, 9, 9, 255, 255, 0, 0, 255, 0, 255, 0, 255, 9, 9, 9, 255,
    8, 8, 8, 255, 0, 0, 255, 255, 255, 255, 255, 255, 8, 8, 8, 255,
  ])
  mask := image(2, 2, [
    10, 20, 30, 255, 40, 10, 20, 255,
    10, 50, 20, 255, 60, 10, 20, 255,
  ])

  atlas := try! buildJigsawAtlas(photo, mask, 1, 1)
  pixels := try! atlas.pixelBytes(PixelAlphaMode.Straight)
  assertBytes(pixels.bytes, [
    255, 0, 0, 30, 0, 255, 0, 40,
    0, 0, 255, 50, 255, 255, 255, 60,
  ])
}

export function testAtlasMapsEachGridCellIntoPhotoCoordinates(): void {
  photo := image(4, 4, [
    1, 0, 0, 255, 2, 0, 0, 255, 3, 0, 0, 255, 4, 0, 0, 255,
    5, 0, 0, 255, 6, 0, 0, 255, 7, 0, 0, 255, 8, 0, 0, 255,
    9, 0, 0, 255, 10, 0, 0, 255, 11, 0, 0, 255, 12, 0, 0, 255,
    13, 0, 0, 255, 14, 0, 0, 255, 15, 0, 0, 255, 16, 0, 0, 255,
  ])
  mask := image(4, 2, [
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
  ])

  atlas := try! buildJigsawAtlas(photo, mask, 2, 1)
  pixels := try! atlas.pixelBytes(PixelAlphaMode.Straight)
  assertBytes(pixels.bytes, [
    1, 0, 0, 255, 2, 0, 0, 255, 2, 0, 0, 255, 4, 0, 0, 255,
    9, 0, 0, 255, 10, 0, 0, 255, 10, 0, 0, 255, 12, 0, 0, 255,
  ])
}

export function testAtlasRejectsInvalidGridDimensions(): void {
  photo := image(1, 1, [255, 255, 255, 255])
  mask := image(2, 2, [
    255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255,
  ])

  Assert.equal(failureMessage(buildJigsawAtlas(photo, mask, 0, 1)), "Jigsaw atlas dimensions must be positive")
  Assert.equal(
    failureMessage(buildJigsawAtlas(photo, mask, 3, 1)),
    "Mask atlas size is not divisible by requested grid",
  )
}

export function testAtlasCachePathTracksAssetsAndGrid(): void {
  photoPath := join([tempDirectory(), "jigsaw-atlas-cache-key-photo.bin"])
  maskPath := join([tempDirectory(), "jigsaw-atlas-cache-key-mask.bin"])
  try! writeBlob(photoPath, [1, 2, 3])
  try! writeBlob(maskPath, [4, 5])

  first := try! jigsawAtlasCachePath(tempDirectory(), photoPath, maskPath, 32, 32)
  same := try! jigsawAtlasCachePath(tempDirectory(), photoPath, maskPath, 32, 32)
  differentGrid := try! jigsawAtlasCachePath(tempDirectory(), photoPath, maskPath, 16, 32)
  try! writeBlob(photoPath, [1, 2, 3, 4])
  differentPhoto := try! jigsawAtlasCachePath(tempDirectory(), photoPath, maskPath, 32, 32)

  Assert.equal(first, same)
  Assert.notEqual(first, differentGrid)
  Assert.notEqual(first, differentPhoto)
  try! remove(photoPath)
  try! remove(maskPath)
}

export function testAtlasCacheRoundTripsPixelsAndRejectsTruncation(): void {
  cachePath := join([tempDirectory(), "jigsaw-atlas-cache-roundtrip.rgba"])
  pixels := PixelBytes(2, 1, [255, 0, 0, 255, 0, 255, 0, 128], PixelAlphaMode.Straight)
  try! cacheJigsawAtlas(pixels, cachePath)

  cached := loadCachedJigsawAtlas(cachePath) else {
    Assert.fail("expected cached atlas pixels")
    return
  }
  Assert.equal(cached.width, 2)
  Assert.equal(cached.height, 1)
  assertBytes(cached.bytes, pixels.bytes)

  try! writeBlob(cachePath, [1, 2, 3])
  Assert.isTrue(loadCachedJigsawAtlas(cachePath) == null)
  try! remove(cachePath)
  try! remove("${cachePath}.dimensions")
}
