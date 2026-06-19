import { BlobReader } from "std/blob"
import { gunzip } from "std/gzip"

import { intrinsicFontAlpha4Gzip, intrinsicFontGzip, NativeTexture } from "./native"
import { createTexture } from "./render"
import { GameSurface } from "./surface"
import { BitmapFont, BitmapFontData, parseBitmapFontData } from "./text"

const INTRINSIC_FONT_SOURCE = "<intrinsic-font>"

export function intrinsicBitmapFontData(): Result<BitmapFontData, string> {
  compressed := intrinsicFontGzip()
  bytes := gunzip(compressed) else error {
    return Failure {
      error: `${INTRINSIC_FONT_SOURCE}: failed to decompress metrics: ${error}`
    }
  }

  text := BlobReader(bytes).readString(long(bytes.length))
  return parseBitmapFontData(text, INTRINSIC_FONT_SOURCE)
}

export function loadIntrinsicBitmapFontForSurface(surface: GameSurface): Result<BitmapFont, string> {
  data := intrinsicBitmapFontData() else error {
    return Failure(error)
  }
  alpha4 := gunzip(intrinsicFontAlpha4Gzip()) else error {
    return Failure {
      error: `${INTRINSIC_FONT_SOURCE}: failed to decompress texture: ${error}`
    }
  }
  nativeTexture := NativeTexture.createAlpha4(
    alpha4,
    data.scaleWidth,
    data.scaleHeight,
    surface.metalDeviceHandle(),
  ) else error {
    return Failure {
      error: `${INTRINSIC_FONT_SOURCE}: failed to create texture: ${error}`
    }
  }

  return Success {
    value: BitmapFont {
      lineHeight: data.lineHeight,
      base: data.base,
      scaleWidth: data.scaleWidth,
      scaleHeight: data.scaleHeight,
      texture: createTexture(nativeTexture),
      glyphs: data.glyphs,
      kernings: data.kernings,
    }
  }
}
