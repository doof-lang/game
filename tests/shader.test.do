mock import for "../shader" {
  "./native" => "./shader_native.mock",
  "./surface" => "./shader_surface.mock",
  "./render" => "./shader_render.mock"
}

import { Assert } from "std/assert"
import { BlobBuilder } from "std/blob"

import {
  ShaderBuffer,
  ShaderDraw,
  ShaderPipeline,
  ShaderPipelineDescriptor,
  ShaderStages,
  ShaderTextureBinding,
  ShaderTextureSlot,
  ShaderUniformBinding,
  ShaderUniformSlot,
  ShaderVertexBufferBinding,
  ShaderVertexLayout,
  drawShader,
} from "../shader"
import { ShaderProgram } from "../shader_program"
import { capture } from "./shader_native.mock"
import { GameSurface } from "./shader_surface.mock"
import { RenderPass, Texture } from "./shader_render.mock"

function filled(length: int): readonly byte[] {
  builder := BlobBuilder()
  builder.writeZeroes(long(length))
  return builder.build()
}

function program(): ShaderProgram => ShaderProgram { vertexSource: "source" }

function pipelineWith(uniforms: readonly ShaderUniformSlot[], textures: readonly ShaderTextureSlot[]): Result<ShaderPipeline, string> {
  return ShaderPipeline(
    GameSurface {},
    ShaderPipelineDescriptor {
      program: program(),
      attributes: [],
      layouts: [ShaderVertexLayout { buffer: 0, stride: 8 }],
      uniforms,
      textures,
    },
  )
}

function standardPipeline(): ShaderPipeline {
  return pipelineWith(
    [
      ShaderUniformSlot { name: "Camera", index: 1 },
      ShaderUniformSlot { name: "Material", index: 0, stages: ShaderStages.Fragment },
    ],
    [
      ShaderTextureSlot { name: "albedo", index: 0 },
      ShaderTextureSlot { name: "detail", index: 3 },
    ],
  )!
}

function vertexBuffer(): ShaderBuffer => ShaderBuffer.create(GameSurface {}, filled(24))!

function drawWith(
  pipeline: ShaderPipeline,
  uniforms: readonly ShaderUniformBinding[],
  textures: readonly ShaderTextureBinding[],
): Result<none, string> {
  return drawShader(
    RenderPass {},
    ShaderDraw {
      pipeline,
      vertexBuffers: [ShaderVertexBufferBinding { index: 0, buffer: vertexBuffer() }],
      vertexCount: 3,
      uniforms,
      textures,
    },
  )
}

function bothTextures(): readonly ShaderTextureBinding[] {
  return [
    ShaderTextureBinding { name: "detail", texture: Texture {} },
    ShaderTextureBinding { name: "albedo", texture: Texture {} },
  ]
}

function assertFails(result: Result<none, string>, fragment: string): none {
  case result {
    _: Success -> Assert.isTrue(false, "expected failure mentioning '${fragment}'")
    f: Failure -> Assert.isTrue(f.error.contains(fragment), "'${f.error}' should mention '${fragment}'")
  }
}

function assertPipelineFails(result: Result<ShaderPipeline, string>, fragment: string): none {
  case result {
    _: Success -> Assert.isTrue(false, "expected pipeline failure mentioning '${fragment}'")
    f: Failure -> Assert.isTrue(f.error.contains(fragment), "'${f.error}' should mention '${fragment}'")
  }
}

export function testInlineUniformBytesArePackedBySlotOrdinal(): none {
  pipeline := standardPipeline()
  drawWith(
    pipeline,
    [
      ShaderUniformBinding { name: "Material", bytes: filled(16) },
      ShaderUniformBinding { name: "Camera", bytes: filled(64) },
    ],
    bothTextures(),
  )!

  Assert.mutableArrayEqual(capture.uniformSlots, [1, 0])
  Assert.mutableArrayEqual(capture.uniformBufferHandles, [0L, 0L])
  Assert.mutableArrayEqual(capture.uniformOffsets, [0, 16])
  Assert.mutableArrayEqual(capture.uniformLengths, [16, 64])
  Assert.equal(capture.uniformBytes.length, 80)
}

export function testTexturesBindBySlotName(): none {
  drawWith(
    standardPipeline(),
    [
      ShaderUniformBinding { name: "Camera", bytes: filled(64) },
      ShaderUniformBinding { name: "Material", bytes: filled(16) },
    ],
    bothTextures(),
  )!

  Assert.mutableArrayEqual(capture.textureSlots, [1, 0])
  Assert.mutableArrayEqual(capture.textureHandles, [77L, 77L])
}

export function testUniformBufferRangesPassHandleOffsetAndLength(): none {
  buffer := ShaderBuffer.create(GameSurface {}, filled(512))!
  drawWith(
    standardPipeline(),
    [
      ShaderUniformBinding { name: "Camera", buffer, offset: 256 },
      ShaderUniformBinding { name: "Material", buffer },
    ],
    bothTextures(),
  )!

  Assert.mutableArrayEqual(capture.uniformBufferHandles, [buffer.nativeHandle(), buffer.nativeHandle()])
  Assert.mutableArrayEqual(capture.uniformOffsets, [256, 0])
  Assert.mutableArrayEqual(capture.uniformLengths, [256, 512])
  Assert.equal(capture.uniformBytes.length, 0)
}

export function testUniformBufferOffsetMustBeAligned(): none {
  buffer := ShaderBuffer.create(GameSurface {}, filled(512))!
  assertFails(
    drawWith(
      standardPipeline(),
      [
        ShaderUniformBinding { name: "Camera", buffer, offset: 16 },
        ShaderUniformBinding { name: "Material", bytes: filled(16) },
      ],
      bothTextures(),
    ),
    "multiple of 256",
  )
}

export function testDrawRejectsUnknownDuplicateAndMissingBindings(): none {
  pipeline := standardPipeline()
  assertFails(
    drawWith(pipeline, [ShaderUniformBinding { name: "Lights", bytes: filled(16) }], bothTextures()),
    "'Lights' does not match",
  )
  assertFails(
    drawWith(
      pipeline,
      [
        ShaderUniformBinding { name: "Camera", bytes: filled(16) },
        ShaderUniformBinding { name: "Camera", bytes: filled(16) },
      ],
      bothTextures(),
    ),
    "'Camera' is bound twice",
  )
  assertFails(
    drawWith(pipeline, [ShaderUniformBinding { name: "Camera", bytes: filled(16) }], bothTextures()),
    "'Material' has no binding",
  )
  assertFails(
    drawWith(
      pipeline,
      [
        ShaderUniformBinding { name: "Camera", bytes: filled(16) },
        ShaderUniformBinding { name: "Material", bytes: filled(16) },
      ],
      [ShaderTextureBinding { name: "albedo", texture: Texture {} }],
    ),
    "'detail' has no binding",
  )
}

export function testUniformBindingNeedsExactlyOneSource(): none {
  pipeline := standardPipeline()
  buffer := ShaderBuffer.create(GameSurface {}, filled(256))!
  assertFails(
    drawWith(pipeline, [ShaderUniformBinding { name: "Camera" }], bothTextures()),
    "must set bytes or buffer",
  )
  assertFails(
    drawWith(pipeline, [ShaderUniformBinding { name: "Camera", bytes: filled(16), buffer }], bothTextures()),
    "must not set both",
  )
}

export function testPipelineRejectsConflictingSlots(): none {
  assertPipelineFails(
    pipelineWith(
      [ShaderUniformSlot { name: "A", index: 1 }, ShaderUniformSlot { name: "A", index: 2 }],
      [],
    ),
    "declared twice",
  )
  assertPipelineFails(
    pipelineWith(
      [ShaderUniformSlot { name: "A", index: 1 }, ShaderUniformSlot { name: "B", index: 1 }],
      [],
    ),
    "share index 1",
  )
  assertPipelineFails(
    pipelineWith([ShaderUniformSlot { name: "A", index: 0 }], []),
    "collides with a vertex buffer index",
  )
  assertPipelineFails(
    pipelineWith([ShaderUniformSlot { name: "", index: 1 }], []),
    "name must not be empty",
  )
}

export function testFragmentOnlyUniformMayShareVertexBufferIndex(): none {
  pipeline := pipelineWith([ShaderUniformSlot { name: "A", index: 0, stages: ShaderStages.Fragment }], [])
  Assert.isTrue(pipeline.isSuccess())
}

export function testShaderBufferUpdateChecksRange(): none {
  buffer := ShaderBuffer.allocate(GameSurface {}, 64)!
  Assert.equal(buffer.byteLength(), 64)
  buffer.update(filled(16), 48)!
  Assert.equal(capture.lastUpdateOffset, 48)
  assertFails(buffer.update(filled(16), 56), "exceeds the buffer")
  assertFails(buffer.update(filled(16), -1), "exceeds the buffer")
}
