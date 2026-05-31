import { floor, sin } from "std/math"
import { NativeSpaceDust, NativeSpaceDustBuilder, drawNativeSpaceDust } from "./native"
import { GameSurface } from "./surface"
import { Color, RenderPass } from "./render"

export class SpaceDustConfig {
  particleCount: int = 2200
  seed: double = 17.0
  fieldSize: double = 38.0
  particleSize: double = 2.0
  fadeStart: double = 6.0
  fadeEnd: double = 18.0
  opacity: double = 0.58
  color: Color = Color(0.72, 0.83, 1.0)
}

export class SpaceDust {
  private readonly native: NativeSpaceDust
  config: SpaceDustConfig

  static constructor(surface: GameSurface, config: SpaceDustConfig = SpaceDustConfig {}): SpaceDust {
    if config.particleCount <= 0 {
      panic("Space dust particle count must be positive")
    }
    if config.fieldSize <= 0.0 {
      panic("Space dust field size must be positive")
    }

    builder := NativeSpaceDustBuilder.create()
    halfField := config.fieldSize * 0.5
    for index of 0..<config.particleCount {
      x := randomSigned(index, config.seed, 0.13) * halfField
      y := randomSigned(index, config.seed, 3.71) * halfField
      z := randomSigned(index, config.seed, 8.29) * halfField
      brightness := 0.45 + randomUnit(index, config.seed, 13.97) * 0.55
      builder.addParticle(x, y, z, brightness)
    }

    native := try! builder.build(surface.metalDeviceHandle())
    return SpaceDust { native: native, config: config }
  }

  particleCount(): int => native.particleCount()
}

function randomUnit(index: int, seed: double, salt: double): double {
  value := sin((double(index) + 1.0) * 12.9898 + seed * 78.233 + salt * 37.719) * 43758.5453123
  return value - floor(value)
}

function randomSigned(index: int, seed: double, salt: double): double {
  return randomUnit(index, seed, salt) * 2.0 - 1.0
}

export function drawSpaceDust(pass: RenderPass, dust: SpaceDust): void {
  matrix := pass.camera().matrix(pass.surface())
  cameraPosition := pass.camera().transform.position
  drawNativeSpaceDust(
    dust.native,
    pass.metalRenderCommandEncoderHandle(),
    pass.metalDeviceHandle(),
    pass.hasDepthAttachment(),
    pass.surface().pixelWidth(),
    pass.surface().pixelHeight(),
    cameraPosition.x,
    cameraPosition.y,
    cameraPosition.z,
    dust.config.fieldSize,
    dust.config.particleSize,
    dust.config.fadeStart,
    dust.config.fadeEnd,
    dust.config.opacity,
    dust.config.color.r,
    dust.config.color.g,
    dust.config.color.b,
    matrix.m00,
    matrix.m01,
    matrix.m02,
    matrix.m03,
    matrix.m10,
    matrix.m11,
    matrix.m12,
    matrix.m13,
    matrix.m20,
    matrix.m21,
    matrix.m22,
    matrix.m23,
    matrix.m30,
    matrix.m31,
    matrix.m32,
    matrix.m33,
  )
}
