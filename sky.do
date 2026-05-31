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
  fovYRadians: double = 1.0471975512,
  exposure: double = 1.0,
): void {
  cameraRotation := pass.camera().transform.rotation.toMat3()
  drawNativeEquirectangularSkyMap(
    skyMap.texture.metalTextureHandle(),
    pass.metalRenderCommandEncoderHandle(),
    pass.metalDeviceHandle(),
    pass.hasDepthAttachment(),
    pass.surface().pixelWidth(),
    pass.surface().pixelHeight(),
    fovYRadians,
    exposure,
    cameraRotation.m00,
    cameraRotation.m01,
    cameraRotation.m02,
    cameraRotation.m10,
    cameraRotation.m11,
    cameraRotation.m12,
    cameraRotation.m20,
    cameraRotation.m21,
    cameraRotation.m22,
  )
}
