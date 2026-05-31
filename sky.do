import { drawNativeEquirectangularSkyMap } from "./native"
import { RenderPass, Texture } from "./render"

export class SkyMap {
  readonly texture: Texture

  pixelWidth(): int => texture.pixelWidth()
  pixelHeight(): int => texture.pixelHeight()
}

export function drawEquirectangularSkyMap(
  pass: RenderPass,
  skyMap: SkyMap,
  yawRadians: double = 0.0,
  pitchRadians: double = 0.0,
  fovYRadians: double = 1.0471975512,
  exposure: double = 1.0,
): void {
  drawNativeEquirectangularSkyMap(
    skyMap.texture.metalTextureHandle(),
    pass.metalRenderCommandEncoderHandle(),
    pass.metalDeviceHandle(),
    pass.hasDepthAttachment(),
    pass.surface().pixelWidth(),
    pass.surface().pixelHeight(),
    yawRadians,
    pitchRadians,
    fovYRadians,
    exposure,
  )
}
