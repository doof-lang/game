import {
  NativeTextureQuadBatch,
  NativeTextureQuadBatchBuilder,
  drawNativeTextureQuadBatch,
} from "./native"
import { GameSurface } from "./surface"
import { Atlas, Color, Mat4, Rect, RenderPass, Texture } from "./render"

export class TextureQuadBatch {
  readonly texture: Texture
  private readonly native: NativeTextureQuadBatch

  quadCount(): int => native.quadCount()
}

export class TextureQuadBatchBuilder {
  private readonly texture: Texture
  private readonly native: NativeTextureQuadBatchBuilder

  static create(texture: Texture): TextureQuadBatchBuilder {
    return TextureQuadBatchBuilder {
      texture: texture,
      native: NativeTextureQuadBatchBuilder.create(),
    }
  }

  static forAtlas(atlas: Atlas): TextureQuadBatchBuilder {
    return TextureQuadBatchBuilder.create(atlas.texture)
  }

  addQuad(
    dest: Rect,
    source: Rect,
    tint: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
  ): TextureQuadBatchBuilder {
    textureWidth := double(texture.pixelWidth())
    textureHeight := double(texture.pixelHeight())
    native.addQuad(
      dest.x,
      dest.y,
      dest.width,
      dest.height,
      source.x / textureWidth,
      source.y / textureHeight,
      (source.x + source.width) / textureWidth,
      (source.y + source.height) / textureHeight,
      tint.r,
      tint.g,
      tint.b,
      tint.a,
    )
    return this
  }

  addAtlasCell(
    atlas: Atlas,
    column: int,
    row: int,
    dest: Rect,
    tint: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
  ): TextureQuadBatchBuilder {
    return addQuad(dest, atlas.cellRect(column, row), tint)
  }

  build(surface: GameSurface): Result<TextureQuadBatch, string> {
    return case native.build(surface.metalDeviceHandle()) {
      s: Success -> Success {
        value: TextureQuadBatch {
          texture: texture,
          native: s.value,
        }
      },
      f: Failure -> Failure {
        error: f.error
      }
    }
  }
}

export function drawTextureQuadBatch(
  pass: RenderPass,
  batch: TextureQuadBatch,
  model: Mat4 = Mat4 {
    m00: 1.0, m01: 0.0, m02: 0.0, m03: 0.0,
    m10: 0.0, m11: 1.0, m12: 0.0, m13: 0.0,
    m20: 0.0, m21: 0.0, m22: 1.0, m23: 0.0,
    m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
  },
): void {
  mvp := pass.camera().matrix(pass.surface()).multiply(model)
  drawNativeTextureQuadBatch(
    batch.native,
    batch.texture.metalTextureHandle(),
    pass.metalRenderCommandEncoderHandle(),
    pass.metalDeviceHandle(),
    pass.nativeBlendModeCode(),
    pass.hasDepthAttachment(),
    mvp.m00,
    mvp.m01,
    mvp.m02,
    mvp.m03,
    mvp.m10,
    mvp.m11,
    mvp.m12,
    mvp.m13,
    mvp.m20,
    mvp.m21,
    mvp.m22,
    mvp.m23,
    mvp.m30,
    mvp.m31,
    mvp.m32,
    mvp.m33,
  )
}
