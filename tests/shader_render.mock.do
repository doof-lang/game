export class RenderPass {
  nativeCommandEncoderHandle(): long => 2L
  nativeBlendModeCode(): int => 0
  hasColorAttachment(): bool => true
  hasDepthAttachment(): bool => false
}

export class Texture {
  nativeTextureHandle(): long => 77L
}

export class DepthTexture {
  nativeTextureHandle(): long => 88L
}
