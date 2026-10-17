import { BlobBuilder } from "std/blob"
import { PixelBytes } from "std/image"
import { cos, sin } from "std/math"
import {
  Blend,
  Clear,
  Color,
  Depth,
  RenderPassDescriptor,
  ShaderBuffer,
  ShaderBytesBuilder,
  ShaderDraw,
  ShaderPipeline,
  ShaderPipelineDescriptor,
  ShaderProgram,
  ShaderTextureBinding,
  ShaderTextureSlot,
  ShaderUniformBinding,
  ShaderUniformSlot,
  ShaderVertexAttribute,
  ShaderVertexBufferBinding,
  ShaderVertexFormat,
  ShaderVertexLayout,
  drawShader,
  initGameApp,
} from "std/game"

function prismBytes(): readonly byte[] {
  return ShaderBytesBuilder()
    .float2(-0.5, -0.34).float3(1.0, 0.0, 0.0)
    .float2(0.5, -0.34).float3(0.0, 1.0, 0.0)
    .float2(0.0, 0.58).float3(0.0, 0.0, 1.0)
    .build()
}

readonly PALETTE_WIDTH = 256
readonly TAU = 6.28318530718

// The prism hue ramp, baked once into a texture the fragment shader samples.
function paletteBytes(): readonly byte[] {
  builder := BlobBuilder()
  for i of 0..<PALETTE_WIDTH {
    t := double(i) / double(PALETTE_WIDTH) * TAU
    builder.writeByte(byte(int((0.56 + 0.44 * cos(t + 0.1)) * 255.0)))
    builder.writeByte(byte(int((0.56 + 0.44 * cos(t + 2.15)) * 255.0)))
    builder.writeByte(byte(int((0.56 + 0.44 * cos(t + 4.3)) * 255.0)))
    builder.writeByte(byte(255))
  }
  return builder.build()
}

function glowBytes(frame: int): readonly byte[] {
  return ShaderBytesBuilder()
    .float4(1.0 + 0.12 * sin(double(frame) * 0.02), 0.0, 0.0, 0.0)
    .build()
}

function backdropBytes(): readonly byte[] {
  return ShaderBytesBuilder()
    .float2(-1.0, -1.0)
    .float2(3.0, -1.0)
    .float2(-1.0, 3.0)
    .build()
}

export function start(
  backdropVertexSource: string,
  backdropFragmentSource: string,
  prismVertexSource: string,
  prismFragmentSource: string,
): none {
  app := initGameApp("Doof WebGL 2 Prism Field")
  backdropPipeline := ShaderPipeline(
    app.surface,
    ShaderPipelineDescriptor {
      program: ShaderProgram {
        vertexSource: backdropVertexSource,
        fragmentSource: backdropFragmentSource,
      },
      attributes: [
        ShaderVertexAttribute { attribute: 0, offset: 0, format: ShaderVertexFormat.Float2 },
      ],
      layouts: [ShaderVertexLayout { stride: 8 }],
      uniforms: [ShaderUniformSlot { name: "Backdrop", index: 0, stages: .Fragment }],
    },
  )!
  prismPipeline := ShaderPipeline(
    app.surface,
    ShaderPipelineDescriptor {
      program: ShaderProgram {
        vertexSource: prismVertexSource,
        fragmentSource: prismFragmentSource,
      },
      attributes: [
        ShaderVertexAttribute { attribute: 0, offset: 0, format: ShaderVertexFormat.Float2 },
        ShaderVertexAttribute { attribute: 1, offset: 8, format: ShaderVertexFormat.Float3 },
      ],
      layouts: [ShaderVertexLayout { stride: 20 }],
      uniforms: [ShaderUniformSlot { name: "Field", index: 1, stages: .Fragment }],
      textures: [ShaderTextureSlot { name: "palette", index: 0 }],
    },
  )!
  backdrop := ShaderBuffer.create(app.surface, backdropBytes())!
  prism := ShaderBuffer.create(app.surface, prismBytes())!
  // A persistent uniform buffer rewritten in place each frame.
  glow := ShaderBuffer.create(app.surface, glowBytes(0))!
  palette := app.createTextureFromPixels(PixelBytes(PALETTE_WIDTH, 1, paletteBytes()))!
  let frame = 0

  app.onRender((renderer): none => {
    frame += 1
    glow.update(glowBytes(frame))!
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.color(Color(0.01, 0.015, 0.04)),
        depth: Depth.disabled(),
        blend: Blend.opaque(),
      },
      (pass): none => {
        drawShader(
          pass,
          ShaderDraw {
            pipeline: backdropPipeline,
            vertexBuffers: [ShaderVertexBufferBinding { index: 0, buffer: backdrop }],
            vertexCount: 3,
            uniforms: [ShaderUniformBinding { name: "Backdrop", buffer: glow }],
          },
        )!
      },
    )
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.disabled(),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      },
      (pass): none => {
        drawShader(
          pass,
          ShaderDraw {
            pipeline: prismPipeline,
            vertexBuffers: [ShaderVertexBufferBinding { index: 0, buffer: prism }],
            vertexCount: 3,
            instanceCount: 384,
            // Small per-draw data is copied inline; no buffer needed.
            uniforms: [ShaderUniformBinding { name: "Field", bytes: ShaderBytesBuilder().float4(1.0, 1.0, 1.0, 1.0).build() }],
            textures: [ShaderTextureBinding { name: "palette", texture: palette }],
          },
        )!
      },
    )
  })

  _ := app.run() else error { panic(error) }
}
