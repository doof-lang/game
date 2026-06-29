import {
  NativeShaderBuffer,
  NativeShaderPipeline,
  drawNativeShader,
} from "./native"
import { GameSurface } from "./surface"
import { RenderPass, Texture } from "./render"

export enum ShaderVertexFormat {
  Float,
  Float2,
  Float3,
  Float4,
  UInt,
  UChar4Normalized,
}

export enum ShaderVertexStepFunction {
  PerVertex,
  PerInstance,
}

readonly SHADER_VERTEX_FORMAT_FLOAT = 1
readonly SHADER_VERTEX_FORMAT_FLOAT2 = 2
readonly SHADER_VERTEX_FORMAT_FLOAT3 = 3
readonly SHADER_VERTEX_FORMAT_FLOAT4 = 4
readonly SHADER_VERTEX_FORMAT_UINT = 5
readonly SHADER_VERTEX_FORMAT_UCHAR4_NORMALIZED = 6
readonly SHADER_VERTEX_STEP_FUNCTION_PER_VERTEX = 1
readonly SHADER_VERTEX_STEP_FUNCTION_PER_INSTANCE = 2

function shaderVertexFormatCode(format: ShaderVertexFormat): int {
  return case format {
    ShaderVertexFormat.Float -> SHADER_VERTEX_FORMAT_FLOAT,
    ShaderVertexFormat.Float2 -> SHADER_VERTEX_FORMAT_FLOAT2,
    ShaderVertexFormat.Float3 -> SHADER_VERTEX_FORMAT_FLOAT3,
    ShaderVertexFormat.Float4 -> SHADER_VERTEX_FORMAT_FLOAT4,
    ShaderVertexFormat.UInt -> SHADER_VERTEX_FORMAT_UINT,
    ShaderVertexFormat.UChar4Normalized -> SHADER_VERTEX_FORMAT_UCHAR4_NORMALIZED,
  }
}

function shaderVertexStepFunctionCode(stepFunction: ShaderVertexStepFunction): int {
  return case stepFunction {
    ShaderVertexStepFunction.PerVertex -> SHADER_VERTEX_STEP_FUNCTION_PER_VERTEX,
    ShaderVertexStepFunction.PerInstance -> SHADER_VERTEX_STEP_FUNCTION_PER_INSTANCE,
  }
}

export class ShaderVertexAttribute {
  readonly attribute: int
  readonly buffer: int = 0
  readonly offset: int
  readonly format: ShaderVertexFormat
}

export class ShaderVertexLayout {
  readonly buffer: int = 0
  readonly stride: int
  readonly stepFunction: ShaderVertexStepFunction = ShaderVertexStepFunction.PerVertex
  readonly stepRate: int = 1
}

export class ShaderPipelineDescriptor {
  readonly source: string
  readonly vertexFunction: string
  readonly fragmentFunction: string
  readonly attributes: ShaderVertexAttribute[]
  readonly layouts: ShaderVertexLayout[]
}

export class ShaderBuffer {
  private readonly native: NativeShaderBuffer

  static create(surface: GameSurface, data: readonly byte[]): Result<ShaderBuffer, string> {
    if data.length == 0 {
      return Failure("Shader buffer data must not be empty")
    }
    native := NativeShaderBuffer.create(surface.metalDeviceHandle(), data) else error {
      return Failure(error)
    }
    return Success(ShaderBuffer { native })
  }

  byteLength(): int => native.byteLength()
  metalBufferHandle(): long => native.metalBufferHandle()
}

export class ShaderPipeline {
  private readonly native: NativeShaderPipeline

  static create(surface: GameSurface, desc: ShaderPipelineDescriptor): Result<ShaderPipeline, string> {
    if desc.source.length == 0 {
      return Failure("Shader source must not be empty")
    }
    if desc.vertexFunction.length == 0 {
      return Failure("Shader vertex function name must not be empty")
    }
    if desc.fragmentFunction.length == 0 {
      return Failure("Shader fragment function name must not be empty")
    }
    if desc.layouts.length == 0 {
      return Failure("Shader pipeline must include at least one vertex layout")
    }

    let attributeIndices: int[] = []
    let attributeBuffers: int[] = []
    let attributeOffsets: int[] = []
    let attributeFormats: int[] = []
    for attribute of desc.attributes {
      if attribute.attribute < 0 || attribute.buffer < 0 || attribute.offset < 0 {
        return Failure("Shader vertex attribute index, buffer, and offset must be non-negative")
      }
      attributeIndices.push(attribute.attribute)
      attributeBuffers.push(attribute.buffer)
      attributeOffsets.push(attribute.offset)
      attributeFormats.push(shaderVertexFormatCode(attribute.format))
    }

    let layoutBuffers: int[] = []
    let layoutStrides: int[] = []
    let layoutStepFunctions: int[] = []
    let layoutStepRates: int[] = []
    for layout of desc.layouts {
      if layout.buffer < 0 {
        return Failure("Shader vertex layout buffer index must be non-negative")
      }
      if layout.stride <= 0 {
        return Failure("Shader vertex layout stride must be positive")
      }
      if layout.stepRate <= 0 {
        return Failure("Shader vertex layout step rate must be positive")
      }
      layoutBuffers.push(layout.buffer)
      layoutStrides.push(layout.stride)
      layoutStepFunctions.push(shaderVertexStepFunctionCode(layout.stepFunction))
      layoutStepRates.push(layout.stepRate)
    }

    native := NativeShaderPipeline.create(
      surface.metalDeviceHandle(),
      desc.source,
      desc.vertexFunction,
      desc.fragmentFunction,
      attributeIndices,
      attributeBuffers,
      attributeOffsets,
      attributeFormats,
      layoutBuffers,
      layoutStrides,
      layoutStepFunctions,
      layoutStepRates,
    ) else error {
      return Failure(error)
    }
    return Success(ShaderPipeline { native })
  }

  nativeShaderPipeline(): NativeShaderPipeline => native
}

export class ShaderBufferBinding {
  readonly index: int
  readonly buffer: ShaderBuffer
  readonly offset: int = 0
}

export class ShaderBytesBinding {
  readonly index: int
  readonly buffer: ShaderBuffer
  readonly offset: int = 0

  static create(surface: GameSurface, index: int, bytes: readonly byte[]): Result<ShaderBytesBinding, string> {
    if index < 0 {
      return Failure("Shader bytes binding index must be non-negative")
    }
    buffer := ShaderBuffer.create(surface, bytes) else error {
      return Failure(error)
    }
    return Success(ShaderBytesBinding { index, buffer })
  }
}

export class ShaderTextureBinding {
  readonly index: int
  readonly texture: Texture
}

export class ShaderDraw {
  readonly pipeline: ShaderPipeline
  readonly vertexBuffers: ShaderBufferBinding[]
  readonly vertexCount: int = 0
  readonly instanceCount: int = 1
  readonly indexBuffer: ShaderBuffer | null = null
  readonly indexCount: int = 0
  readonly vertexBytes: ShaderBytesBinding[] = []
  readonly fragmentBytes: ShaderBytesBinding[] = []
  readonly fragmentTextures: ShaderTextureBinding[] = []
}

function collectBufferBindingIndices(bindings: readonly ShaderBufferBinding[]): int[] {
  let indices: int[] = []
  for binding of bindings {
    indices.push(binding.index)
  }
  return indices
}

function collectBufferBindingHandles(bindings: readonly ShaderBufferBinding[]): long[] {
  let handles: long[] = []
  for binding of bindings {
    handles.push(binding.buffer.metalBufferHandle())
  }
  return handles
}

function collectBufferBindingOffsets(bindings: readonly ShaderBufferBinding[]): int[] {
  let offsets: int[] = []
  for binding of bindings {
    offsets.push(binding.offset)
  }
  return offsets
}

function collectBytesBindingIndices(bindings: readonly ShaderBytesBinding[]): int[] {
  let indices: int[] = []
  for binding of bindings {
    indices.push(binding.index)
  }
  return indices
}

function collectBytesBindingHandles(bindings: readonly ShaderBytesBinding[]): long[] {
  let handles: long[] = []
  for binding of bindings {
    handles.push(binding.buffer.metalBufferHandle())
  }
  return handles
}

function collectBytesBindingOffsets(bindings: readonly ShaderBytesBinding[]): int[] {
  let offsets: int[] = []
  for binding of bindings {
    offsets.push(binding.offset)
  }
  return offsets
}

function collectTextureBindingIndices(bindings: readonly ShaderTextureBinding[]): int[] {
  let indices: int[] = []
  for binding of bindings {
    indices.push(binding.index)
  }
  return indices
}

function collectTextureBindingHandles(bindings: readonly ShaderTextureBinding[]): long[] {
  let handles: long[] = []
  for binding of bindings {
    handles.push(binding.texture.metalTextureHandle())
  }
  return handles
}

function validateBufferBindings(bindings: readonly ShaderBufferBinding[], label: string): Result<void, string> {
  for binding of bindings {
    if binding.index < 0 {
      return Failure(label + " binding index must be non-negative")
    }
    if binding.offset < 0 {
      return Failure(label + " binding offset must be non-negative")
    }
    if binding.offset >= binding.buffer.byteLength() {
      return Failure(label + " binding offset must be smaller than its buffer")
    }
  }
  return Success()
}

function validateBytesBindings(bindings: readonly ShaderBytesBinding[], label: string): Result<void, string> {
  for binding of bindings {
    if binding.index < 0 {
      return Failure(label + " binding index must be non-negative")
    }
    if binding.offset < 0 {
      return Failure(label + " binding offset must be non-negative")
    }
    if binding.offset >= binding.buffer.byteLength() {
      return Failure(label + " binding offset must be smaller than its buffer")
    }
  }
  return Success()
}

function validateTextureBindings(bindings: readonly ShaderTextureBinding[]): Result<void, string> {
  for binding of bindings {
    if binding.index < 0 {
      return Failure("Shader texture binding index must be non-negative")
    }
  }
  return Success()
}

export function drawShader(pass: RenderPass, draw: ShaderDraw): Result<void, string> {
  if draw.vertexBuffers.length == 0 {
    return Failure("Shader draw must include at least one vertex buffer")
  }
  try validateBufferBindings(draw.vertexBuffers, "Shader vertex buffer")
  try validateBytesBindings(draw.vertexBytes, "Shader vertex bytes")
  try validateBytesBindings(draw.fragmentBytes, "Shader fragment bytes")
  try validateTextureBindings(draw.fragmentTextures)
  if draw.instanceCount <= 0 {
    return Failure("Shader draw instance count must be positive")
  }

  let indexBufferHandle = 0L
  if draw.indexBuffer != null {
    if draw.indexCount <= 0 {
      return Failure("Shader indexed draw must include a positive index count")
    }
    if draw.indexBuffer!.byteLength() % 4 != 0 {
      return Failure("Shader index buffer byte length must be divisible by 4")
    }
    if draw.indexCount * 4 > draw.indexBuffer!.byteLength() {
      return Failure("Shader index count exceeds index buffer length")
    }
    indexBufferHandle = draw.indexBuffer!.metalBufferHandle()
  } else if draw.vertexCount <= 0 {
    return Failure("Shader non-indexed draw must include a positive vertex count")
  }

  return drawNativeShader(
    draw.pipeline.nativeShaderPipeline(),
    collectBufferBindingIndices(draw.vertexBuffers),
    collectBufferBindingHandles(draw.vertexBuffers),
    collectBufferBindingOffsets(draw.vertexBuffers),
    collectBytesBindingIndices(draw.vertexBytes),
    collectBytesBindingHandles(draw.vertexBytes),
    collectBytesBindingOffsets(draw.vertexBytes),
    collectBytesBindingIndices(draw.fragmentBytes),
    collectBytesBindingHandles(draw.fragmentBytes),
    collectBytesBindingOffsets(draw.fragmentBytes),
    collectTextureBindingIndices(draw.fragmentTextures),
    collectTextureBindingHandles(draw.fragmentTextures),
    indexBufferHandle,
    draw.indexCount,
    draw.vertexCount,
    draw.instanceCount,
    pass.metalRenderCommandEncoderHandle(),
    pass.nativeBlendModeCode(),
    pass.hasDepthAttachment(),
  )
}
