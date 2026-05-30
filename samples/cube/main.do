import { setInterval } from "std/event"
import { Duration, Instant } from "std/time"

import {
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  GameApp,
  GameEventKind,
  GameSurface,
  Key,
  Mat4,
  Point3,
  RenderPassDescriptor,
  SimpleMesh,
  SimpleMeshBuilder,
  drawSimpleMesh,
  initGameApp,
} from "std/game"

function createCubeMesh(surface: GameSurface): SimpleMesh {
  builder := SimpleMeshBuilder.create()

  p000 := Point3(-1.0, -1.0, -1.0)
  p001 := Point3(-1.0, -1.0, 1.0)
  p010 := Point3(-1.0, 1.0, -1.0)
  p011 := Point3(-1.0, 1.0, 1.0)
  p100 := Point3(1.0, -1.0, -1.0)
  p101 := Point3(1.0, -1.0, 1.0)
  p110 := Point3(1.0, 1.0, -1.0)
  p111 := Point3(1.0, 1.0, 1.0)

  builder.quad{
    a: p001, b: p101, c: p111, d: p011,
    color: Color.rgb(0.95, 0.20, 0.16),
    normal: Point3.xyz(0.0, 0.0, 1.0),
  }
  builder.quad{
    a: p100, b: p000, c: p010, d: p110,
    color: Color.rgb(0.12, 0.42, 0.95),
    normal: Point3.xyz(0.0, 0.0, -1.0),
  }
  builder.quad{
    a: p000, b: p001, c: p011, d: p010,
    color: Color.rgb(0.15, 0.78, 0.42),
    normal: Point3.xyz(-1.0, 0.0, 0.0),
  }
  builder.quad{
    a: p101, b: p100, c: p110, d: p111,
    color: Color.rgb(0.98, 0.72, 0.18),
    normal: Point3.xyz(1.0, 0.0, 0.0),
  }
  builder.quad{
    a: p010, b: p011, c: p111, d: p110,
    color: Color.rgb(0.72, 0.32, 0.92),
    normal: Point3.xyz(0.0, 1.0, 0.0),
  }
  builder.quad{
    a: p000, b: p100, c: p101, d: p001,
    color: Color.rgb(0.10, 0.82, 0.86),
    normal: Point3.xyz(0.0, -1.0, 0.0),
  }

  return builder.build(surface)
}

function main(): int {
  app := initGameApp{ title: "Doof Game Spinning Cube" }

  let angle = 0.0
  let lastFrameAt = Instant.now()

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }

    if event.kind() == GameEventKind.KeyDown && event.key() == Key.Escape {
      app.stop()
    }
  })

  cubeMesh := createCubeMesh(app.surface)

  surface := app.surface
  aspect := double(surface.pixelWidth()) / double(surface.pixelHeight())
  camera := Camera.perspective(1.0471975512, aspect, 0.1, 100.0).withView(Mat4.translation(0.0, 0.0, -5.0))

  renderPassDescriptor := RenderPassDescriptor {
    camera,
    clear: Clear.colorDepth(Color.rgb(0.018, 0.022, 0.030), 1.0),
    depth: Depth.readWrite(),
    blend: Blend.opaque(),
  }

  app.onRender((renderer): void => {
    now := Instant.now()
    elapsed := lastFrameAt.durationUntil(now)
    lastFrameAt = now
    angle += double(elapsed.toNanos()) / 1000000000.0

    renderer.pass(
      renderPassDescriptor,
      (pass): void => {
        model := Mat4.rotationX(angle * 0.62).multiply(Mat4.rotationY(angle))
        drawSimpleMesh(pass, cubeMesh, model)
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
