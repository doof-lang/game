import { Mat4, Point3 } from "../render"
import { Transform } from "../transform"
import { GameSurface } from "./lighting_surface.mock"

export { Color, Mat4, Point, Point3 } from "../render"

export class Camera {
  transform: Transform = Transform.identity().withPosition(Point3(7.0, 8.0, 9.0))

  matrix(surface: GameSurface): Mat4 => Mat4.identity
}

export class RenderPass {
  passCamera: Camera = Camera {}
  passSurface: GameSurface = GameSurface {}

  camera(): Camera => passCamera
  surface(): GameSurface => passSurface
  metalRenderCommandEncoderHandle(): long => 2L
  metalDeviceHandle(): long => 1L
  nativeBlendModeCode(): int => 0
  hasColorAttachment(): bool => true
  hasDepthAttachment(): bool => true
}

export class Texture {
  metalTextureHandle(): long => 77L
}
