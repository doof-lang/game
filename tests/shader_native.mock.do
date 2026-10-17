// Records what std/game's shader module hands to the native layer.
export class DrawCapture {
  let calls: int = 0
  let vertexBufferIndices: int[] = []
  let uniformSlots: int[] = []
  let uniformBufferHandles: long[] = []
  let uniformOffsets: int[] = []
  let uniformLengths: int[] = []
  let uniformBytes: readonly byte[] = []
  let textureSlots: int[] = []
  let textureHandles: long[] = []
  let lastUpdateOffset: int = -1
}

capture := DrawCapture {}
export { capture }

export class NativeShaderBuffer {
  private size: int

  static create(metalDeviceHandle: long, data: readonly byte[]): Result<NativeShaderBuffer, string> {
    return Success(NativeShaderBuffer { size: data.length })
  }

  byteLength(): int => size
  metalBufferHandle(): long => 1000L + long(size)

  update(data: readonly byte[], offset: int): Result<none, string> {
    capture.lastUpdateOffset = offset
    return Success()
  }
}

export class NativeShaderPipeline {
  static create(
    metalDeviceHandle: long,
    vertexSource: string,
    fragmentSource: string,
    vertexFunction: string,
    fragmentFunction: string,
    attributeIndices: int[],
    attributeBuffers: int[],
    attributeOffsets: int[],
    attributeFormats: int[],
    layoutBuffers: int[],
    layoutStrides: int[],
    layoutStepFunctions: int[],
    layoutStepRates: int[],
    uniformNames: string[],
    uniformIndices: int[],
    uniformStages: int[],
    textureNames: string[],
    textureIndices: int[],
    textureStages: int[],
  ): Result<NativeShaderPipeline, string> {
    return Success(NativeShaderPipeline {})
  }
}

export function drawNativeShader(
  pipeline: NativeShaderPipeline,
  vertexBufferIndices: int[],
  vertexBufferHandles: long[],
  vertexBufferOffsets: int[],
  uniformSlots: int[],
  uniformBufferHandles: long[],
  uniformOffsets: int[],
  uniformLengths: int[],
  uniformBytes: readonly byte[],
  textureSlots: int[],
  textureHandles: long[],
  indexBufferHandle: long,
  indexCount: int,
  vertexCount: int,
  instanceCount: int,
  metalRenderCommandEncoderHandle: long,
  blendMode: int,
  hasColorAttachment: bool,
  hasDepthAttachment: bool,
): Result<none, string> {
  capture.calls += 1
  capture.vertexBufferIndices = vertexBufferIndices
  capture.uniformSlots = uniformSlots
  capture.uniformBufferHandles = uniformBufferHandles
  capture.uniformOffsets = uniformOffsets
  capture.uniformLengths = uniformLengths
  capture.uniformBytes = uniformBytes
  capture.textureSlots = textureSlots
  capture.textureHandles = textureHandles
  return Success()
}
