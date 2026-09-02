import {
  Blend,
  Clear,
  Color,
  Depth,
  RenderPassDescriptor,
  ShaderBuffer,
  ShaderBufferBinding,
  ShaderBytesBuilder,
  ShaderDraw,
  ShaderPipeline,
  ShaderPipelineDescriptor,
  ShaderProgram,
  ShaderVertexAttribute,
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
  backdropPipeline := try! ShaderPipeline(
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
    },
  )
  prismPipeline := try! ShaderPipeline(
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
    },
  )
  backdrop := try! ShaderBuffer.create(app.surface, backdropBytes())
  prism := try! ShaderBuffer.create(app.surface, prismBytes())

  app.onRender((renderer): none => {
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.color(Color(0.01, 0.015, 0.04)),
        depth: Depth.disabled(),
        blend: Blend.opaque(),
      },
      (pass): none => {
        try! drawShader(
          pass,
          ShaderDraw {
            pipeline: backdropPipeline,
            vertexBuffers: [ShaderBufferBinding { index: 0, buffer: backdrop }],
            vertexCount: 3,
          },
        )
      },
    )
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.disabled(),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      },
      (pass): none => {
        try! drawShader(
          pass,
          ShaderDraw {
            pipeline: prismPipeline,
            vertexBuffers: [ShaderBufferBinding { index: 0, buffer: prism }],
            vertexCount: 3,
            instanceCount: 384,
          },
        )
      },
    )
  })

  _ := app.run() else error { panic(error) }
}
