import { BlobBuilder } from "std/blob"

import {
  NativeShaderBuffer,
  NativeShaderPipeline,
  drawNativeShader,
} from "./native"
import { GameSurface } from "./surface"
import { DepthTexture, RenderPass, Texture } from "./render"
import { ShaderProgram } from "./shader_program"

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

// Shader stages that can see a uniform or texture slot.
export enum ShaderStages {
  Vertex,
  Fragment,
  VertexAndFragment,
}

readonly SHADER_VERTEX_FORMAT_FLOAT = 1
readonly SHADER_VERTEX_FORMAT_FLOAT2 = 2
readonly SHADER_VERTEX_FORMAT_FLOAT3 = 3
readonly SHADER_VERTEX_FORMAT_FLOAT4 = 4
readonly SHADER_VERTEX_FORMAT_UINT = 5
readonly SHADER_VERTEX_FORMAT_UCHAR4_NORMALIZED = 6
readonly SHADER_VERTEX_STEP_FUNCTION_PER_VERTEX = 1
readonly SHADER_VERTEX_STEP_FUNCTION_PER_INSTANCE = 2
readonly SHADER_STAGE_VERTEX = 1
readonly SHADER_STAGE_FRAGMENT = 2

// Uniform buffer offsets must satisfy the strictest backend alignment
// (Metal constant buffers on macOS and the usual WebGL 2 UBO alignment).
export readonly SHADER_UNIFORM_BUFFER_OFFSET_ALIGNMENT = 256

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

function shaderStagesCode(stages: ShaderStages): int {
  return case stages {
    ShaderStages.Vertex -> SHADER_STAGE_VERTEX,
    ShaderStages.Fragment -> SHADER_STAGE_FRAGMENT,
    ShaderStages.VertexAndFragment -> SHADER_STAGE_VERTEX + SHADER_STAGE_FRAGMENT,
  }
}

function includesVertexStage(stages: ShaderStages): bool => stages != ShaderStages.Fragment

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

// A uniform block the program reads. `name` is the GLSL uniform block name
// and the key draws bind data with; `index` is the Metal buffer index or the
// HLSL constant-buffer register.
export class ShaderUniformSlot {
  readonly name: string
  readonly index: int
  readonly stages: ShaderStages = ShaderStages.VertexAndFragment
}

// A sampled texture the program reads. `name` is the GLSL sampler uniform
// name and the key draws bind textures with; `index` is the Metal texture and
// sampler index or the HLSL texture and sampler register.
export class ShaderTextureSlot {
  readonly name: string
  readonly index: int
  readonly stages: ShaderStages = ShaderStages.Fragment
}

export class ShaderPipelineDescriptor {
  readonly program: ShaderProgram
  readonly attributes: ShaderVertexAttribute[]
  readonly layouts: ShaderVertexLayout[]
  readonly uniforms: ShaderUniformSlot[] = []
  readonly textures: ShaderTextureSlot[] = []
}

export class ShaderBuffer {
  private native: NativeShaderBuffer

  static create(surface: GameSurface, data: readonly byte[]): Result<ShaderBuffer, string> {
    if data.length == 0 {
      return Failure("Shader buffer data must not be empty")
    }
    native := NativeShaderBuffer.create(surface.nativeDeviceHandle(), data) else error {
      return Failure(error)
    }
    return Success(ShaderBuffer { native })
  }

  // Create a zero-filled buffer to fill later with `update`.
  static allocate(surface: GameSurface, byteLength: int): Result<ShaderBuffer, string> {
    if byteLength <= 0 {
      return Failure("Shader buffer byte length must be positive")
    }
    builder := BlobBuilder(long(byteLength))
    builder.writeZeroes(long(byteLength))
    return ShaderBuffer.create(surface, builder.build())
  }

  // Overwrite part of the buffer. Draws encoded after the update see the new
  // bytes; avoid rewriting a range a frame still in flight is reading.
  update(data: readonly byte[], offset: int = 0): Result<none, string> {
    if data.length == 0 {
      return Failure("Shader buffer update data must not be empty")
    }
    if offset < 0 || offset + data.length > native.byteLength() {
      return Failure("Shader buffer update range exceeds the buffer")
    }
    return native.update(data, offset)
  }

  byteLength(): int => native.byteLength()
  nativeHandle(): long => native.metalBufferHandle()
}

class ResolvedSlot {
  readonly name: string
  readonly index: int
}

function resolveSlots(names: string[], indices: int[], label: string): Result<ResolvedSlot[], string> {
  let slots: ResolvedSlot[] = []
  for i of 0..<names.length {
    name := names[i]
    index := indices[i]
    if name.length == 0 {
      return Failure("${label} slot name must not be empty")
    }
    if index < 0 {
      return Failure("${label} slot '${name}' index must be non-negative")
    }
    for existing of slots {
      if existing.name == name {
        return Failure("${label} slot name '${name}' is declared twice")
      }
      if existing.index == index {
        return Failure("${label} slots '${existing.name}' and '${name}' share index ${index}")
      }
    }
    slots.push(ResolvedSlot { name, index })
  }
  return Success(slots)
}

export class ShaderPipeline {
  private native: NativeShaderPipeline
  private uniformSlots: ResolvedSlot[]
  private textureSlots: ResolvedSlot[]

  static constructor(surface: GameSurface, desc: ShaderPipelineDescriptor): Result<ShaderPipeline, string> {
    program := desc.program
    if program.vertexSource.length == 0 {
      return Failure("Shader vertex source must not be empty")
    }
    fragmentSource := program.fragmentSource ?? program.vertexSource
    if fragmentSource.length == 0 {
      return Failure("Shader fragment source must not be empty")
    }
    if program.vertexFunction.length == 0 {
      return Failure("Shader vertex function name must not be empty")
    }
    if program.fragmentFunction.length == 0 {
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

    let uniformNames: string[] = []
    let uniformIndices: int[] = []
    let uniformStageCodes: int[] = []
    for uniform of desc.uniforms {
      // Metal shares one vertex buffer table between vertex buffers and
      // vertex-visible uniforms, so their indices must not collide.
      if includesVertexStage(uniform.stages) {
        for layout of desc.layouts {
          if layout.buffer == uniform.index {
            return Failure("Shader uniform slot '${uniform.name}' index ${uniform.index} collides with a vertex buffer index")
          }
        }
      }
      uniformNames.push(uniform.name)
      uniformIndices.push(uniform.index)
      uniformStageCodes.push(shaderStagesCode(uniform.stages))
    }
    try uniformSlots := resolveSlots(uniformNames, uniformIndices, "Shader uniform")

    let textureNames: string[] = []
    let textureIndices: int[] = []
    let textureStageCodes: int[] = []
    for texture of desc.textures {
      textureNames.push(texture.name)
      textureIndices.push(texture.index)
      textureStageCodes.push(shaderStagesCode(texture.stages))
    }
    try textureSlots := resolveSlots(textureNames, textureIndices, "Shader texture")

    native := NativeShaderPipeline.create(
      surface.nativeDeviceHandle(),
      program.vertexSource,
      fragmentSource,
      program.vertexFunction,
      program.fragmentFunction,
      attributeIndices,
      attributeBuffers,
      attributeOffsets,
      attributeFormats,
      layoutBuffers,
      layoutStrides,
      layoutStepFunctions,
      layoutStepRates,
      uniformNames,
      uniformIndices,
      uniformStageCodes,
      textureNames,
      textureIndices,
      textureStageCodes,
    ) else error {
      return Failure(error)
    }
    return Success(ShaderPipeline { native, uniformSlots, textureSlots })
  }

  nativeShaderPipeline(): NativeShaderPipeline => native

  uniformSlotOrdinal(name: string): int {
    for i of 0..<uniformSlots.length {
      if uniformSlots[i].name == name {
        return i
      }
    }
    return -1
  }

  textureSlotOrdinal(name: string): int {
    for i of 0..<textureSlots.length {
      if textureSlots[i].name == name {
        return i
      }
    }
    return -1
  }

  uniformSlotCount(): int => uniformSlots.length
  textureSlotCount(): int => textureSlots.length
  uniformSlotName(ordinal: int): string => uniformSlots[ordinal].name
  textureSlotName(ordinal: int): string => textureSlots[ordinal].name
}

// Binds a vertex buffer at a `ShaderVertexLayout` buffer index.
export class ShaderVertexBufferBinding {
  readonly index: int
  buffer: ShaderBuffer
  readonly offset: int = 0
}

// Supplies a uniform slot's data, either as `bytes` copied into this draw or
// as a range of a persistent `buffer`. Set exactly one of the two.
export class ShaderUniformBinding {
  readonly name: string
  readonly bytes: readonly byte[] | none = none
  buffer: ShaderBuffer | none = none
  readonly offset: int = 0
}

export class ShaderTextureBinding {
  readonly name: string
  texture: Texture | none = none
  depthTexture: DepthTexture | none = none

  nativeHandle(): long {
    return texture?.nativeTextureHandle() ?? depthTexture?.nativeTextureHandle() ?? 0L
  }
}

export class ShaderDraw {
  pipeline: ShaderPipeline
  vertexBuffers: readonly ShaderVertexBufferBinding[]
  readonly vertexCount: int = 0
  readonly instanceCount: int = 1
  indexBuffer: ShaderBuffer | none = none
  readonly indexCount: int = 0
  uniforms: readonly ShaderUniformBinding[] = []
  textures: readonly ShaderTextureBinding[] = []
}

class NativeVertexBuffers {
  indices: int[] = []
  handles: long[] = []
  offsets: int[] = []
}

class NativeUniforms {
  slots: int[] = []
  handles: long[] = []
  offsets: int[] = []
  lengths: int[] = []
  let bytes: readonly byte[] = []
}

class NativeTextures {
  slots: int[] = []
  handles: long[] = []
}

function collectVertexBuffers(bindings: readonly ShaderVertexBufferBinding[]): Result<NativeVertexBuffers, string> {
  result := NativeVertexBuffers {}
  for binding of bindings {
    if binding.index < 0 {
      return Failure("Shader vertex buffer binding index must be non-negative")
    }
    if binding.offset < 0 {
      return Failure("Shader vertex buffer binding offset must be non-negative")
    }
    if binding.offset >= binding.buffer.byteLength() {
      return Failure("Shader vertex buffer binding offset must be smaller than its buffer")
    }
    result.indices.push(binding.index)
    result.handles.push(binding.buffer.nativeHandle())
    result.offsets.push(binding.offset)
  }
  return Success(result)
}

function markBound(bound: bool[], ordinal: int, name: string, label: string): Result<none, string> {
  if ordinal < 0 {
    return Failure("${label} binding '${name}' does not match a pipeline slot")
  }
  if bound[ordinal] {
    return Failure("${label} binding '${name}' is bound twice")
  }
  bound[ordinal] = true
  return Success()
}

function requireAllBound(bound: bool[], names: string[], label: string): Result<none, string> {
  for i of 0..<bound.length {
    if !bound[i] {
      return Failure("${label} slot '${names[i]}' has no binding")
    }
  }
  return Success()
}

function collectUniforms(pipeline: ShaderPipeline, bindings: readonly ShaderUniformBinding[]): Result<NativeUniforms, string> {
  result := NativeUniforms {}
  let bound: bool[] = []
  let names: string[] = []
  for i of 0..<pipeline.uniformSlotCount() {
    bound.push(false)
    names.push(pipeline.uniformSlotName(i))
  }

  packed := BlobBuilder()
  for binding of bindings {
    ordinal := pipeline.uniformSlotOrdinal(binding.name)
    try markBound(bound, ordinal, binding.name, "Shader uniform")
    result.slots.push(ordinal)

    if binding.bytes != none && binding.buffer != none {
      return Failure("Shader uniform binding '${binding.name}' must not set both bytes and buffer")
    }
    if buffer := binding.buffer {
      if binding.offset < 0 || binding.offset >= buffer.byteLength() {
        return Failure("Shader uniform binding '${binding.name}' offset must lie inside its buffer")
      }
      if binding.offset % SHADER_UNIFORM_BUFFER_OFFSET_ALIGNMENT != 0 {
        return Failure("Shader uniform binding '${binding.name}' offset must be a multiple of ${SHADER_UNIFORM_BUFFER_OFFSET_ALIGNMENT}")
      }
      result.handles.push(buffer.nativeHandle())
      result.offsets.push(binding.offset)
      result.lengths.push(buffer.byteLength() - binding.offset)
    } else if bytes := binding.bytes {
      if bytes.length == 0 {
        return Failure("Shader uniform binding '${binding.name}' bytes must not be empty")
      }
      if binding.offset != 0 {
        return Failure("Shader uniform binding '${binding.name}' offset applies only to buffers")
      }
      result.handles.push(0L)
      result.offsets.push(int(packed.length()))
      result.lengths.push(bytes.length)
      packed.writeBytes(bytes)
    } else {
      return Failure("Shader uniform binding '${binding.name}' must set bytes or buffer")
    }
  }
  try requireAllBound(bound, names, "Shader uniform")
  result.bytes = packed.build()
  return Success(result)
}

function collectTextures(pipeline: ShaderPipeline, bindings: readonly ShaderTextureBinding[]): Result<NativeTextures, string> {
  result := NativeTextures {}
  let bound: bool[] = []
  let names: string[] = []
  for i of 0..<pipeline.textureSlotCount() {
    bound.push(false)
    names.push(pipeline.textureSlotName(i))
  }

  for binding of bindings {
    if binding.texture == none && binding.depthTexture == none {
      return Failure("Shader texture binding '${binding.name}' must include a texture or depth texture")
    }
    if binding.texture != none && binding.depthTexture != none {
      return Failure("Shader texture binding '${binding.name}' must not include both texture and depth texture")
    }
    ordinal := pipeline.textureSlotOrdinal(binding.name)
    try markBound(bound, ordinal, binding.name, "Shader texture")
    result.slots.push(ordinal)
    result.handles.push(binding.nativeHandle())
  }
  try requireAllBound(bound, names, "Shader texture")
  return Success(result)
}

export function drawShader(pass: RenderPass, draw: ShaderDraw): Result<none, string> {
  if draw.vertexBuffers.length == 0 {
    return Failure("Shader draw must include at least one vertex buffer")
  }
  if draw.instanceCount <= 0 {
    return Failure("Shader draw instance count must be positive")
  }
  try vertexBuffers := collectVertexBuffers(draw.vertexBuffers)
  try uniforms := collectUniforms(draw.pipeline, draw.uniforms)
  try textures := collectTextures(draw.pipeline, draw.textures)

  let indexBufferHandle = 0L
  if indexBuffer := draw.indexBuffer {
    if draw.indexCount <= 0 {
      return Failure("Shader indexed draw must include a positive index count")
    }
    if indexBuffer.byteLength() % 4 != 0 {
      return Failure("Shader index buffer byte length must be divisible by 4")
    }
    if draw.indexCount * 4 > indexBuffer.byteLength() {
      return Failure("Shader index count exceeds index buffer length")
    }
    indexBufferHandle = indexBuffer.nativeHandle()
  } else if draw.vertexCount <= 0 {
    return Failure("Shader non-indexed draw must include a positive vertex count")
  }

  return drawNativeShader(
    draw.pipeline.nativeShaderPipeline(),
    vertexBuffers.indices,
    vertexBuffers.handles,
    vertexBuffers.offsets,
    uniforms.slots,
    uniforms.handles,
    uniforms.offsets,
    uniforms.lengths,
    uniforms.bytes,
    textures.slots,
    textures.handles,
    indexBufferHandle,
    draw.indexCount,
    draw.vertexCount,
    draw.instanceCount,
    pass.nativeCommandEncoderHandle(),
    pass.nativeBlendModeCode(),
    pass.hasColorAttachment(),
    pass.hasDepthAttachment(),
  )
}
