import { setInterval } from "std/event"
import { Duration, Instant } from "std/time"

import {
  Blend,
  Camera,
  Clear,
  ColorMesh,
  ColorMeshBuilder,
  Color,
  Depth,
  GameApp,
  GameEventKind,
  GameSurface,
  Key,
  Mat4,
  Point3,
  RenderPassDescriptor,
  drawColorMesh,
  initGameApp,
} from "std/game"

function createCubeMesh(surface: GameSurface): Result<ColorMesh, string> {
  builder := ColorMeshBuilder.create()

  p000 := Point3(-1.0, -1.0, -1.0)
  p001 := Point3(-1.0, -1.0, 1.0)
  p010 := Point3(-1.0, 1.0, -1.0)
  p011 := Point3(-1.0, 1.0, 1.0)
  p100 := Point3(1.0, -1.0, -1.0)
  p101 := Point3(1.0, -1.0, 1.0)
  p110 := Point3(1.0, 1.0, -1.0)
  p111 := Point3(1.0, 1.0, 1.0)

  builder.addQuad(p001, p101, p111, p011, Color.rgb(0.95, 0.20, 0.16))
  builder.addQuad(p100, p000, p010, p110, Color.rgb(0.12, 0.42, 0.95))
  builder.addQuad(p000, p001, p011, p010, Color.rgb(0.15, 0.78, 0.42))
  builder.addQuad(p101, p100, p110, p111, Color.rgb(0.98, 0.72, 0.18))
  builder.addQuad(p010, p011, p111, p110, Color.rgb(0.72, 0.32, 0.92))
  builder.addQuad(p000, p100, p101, p001, Color.rgb(0.10, 0.82, 0.86))

  return builder.build(surface)
}

function main(): int {
  app := initGameApp{ title: "Doof Game Spinning Cube" }

  let angle = 0.0
  let lastFrameAt = Instant.now()

  fpsTimer := setInterval{
    interval: Duration.ofSeconds(1L),
    handler: (): void => {
      println("fps ${app.fps()}")
    },
  }

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }

    if event.kind() == GameEventKind.KeyDown && event.key() == Key.Escape {
      app.stop()
    }
  })

  cubeMesh := createCubeMesh(app.surface) else {
    panic("failed to create cube mesh")
  }

  app.onRender((renderer): void => {
    now := Instant.now()
    elapsed := lastFrameAt.durationUntil(now)
    lastFrameAt = now
    angle += double(elapsed.toNanos()) / 1000000000.0

    surface := renderer.surface()

    aspect := double(surface.pixelWidth()) / double(surface.pixelHeight())
    camera := Camera.perspective(1.0471975512, aspect, 0.1, 100.0).withView(Mat4.translation(0.0, 0.0, -5.0))

    renderer.pass(
      RenderPassDescriptor {
        camera,
        clear: Clear.colorDepth(Color.rgb(0.018, 0.022, 0.030), 1.0),
        depth: Depth.readWrite(),
        blend: Blend.opaque(),
      },
      (pass): void => {
        model := Mat4.rotationX(angle * 0.62).multiply(Mat4.rotationY(angle))
        drawColorMesh(pass, cubeMesh, model)
        app.requestRender()
      },
    )

  })

  result := app.run()
  case result {
    s: Success -> return 0
    f: Failure -> {
      println(f.error)
      return 1
    }
  }
}
