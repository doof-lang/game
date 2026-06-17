import {
  Blend,
  Clear,
  Color,
  Depth,
  GameEventKind,
  GameSurface,
  Key,
  Point3,
  RenderPassDescriptor,
  SimpleMesh,
  SimpleMeshBuilder,
  drawSimpleMesh,
  initGameApp,
} from "std/game"

function createMinimalMesh(surface: GameSurface): SimpleMesh {
  builder := SimpleMeshBuilder.create()

  topLeft := builder.vertex{
    position: Point3(80.0, 80.0, 0.0),
    color: Color(0.95, 0.25, 0.12),
  }
  topRight := builder.vertex{
    position: Point3(400.0, 80.0, 0.0),
    color: Color(0.98, 0.72, 0.18),
  }
  bottomRight := builder.vertex{
    position: Point3(400.0, 280.0, 0.0),
    color: Color(0.15, 0.78, 0.42),
  }
  bottomLeft := builder.vertex{
    position: Point3(80.0, 280.0, 0.0),
    color: Color(0.12, 0.42, 0.95),
  }

  builder.triangle(topLeft, topRight, bottomRight)
  builder.triangle(topLeft, bottomRight, bottomLeft)

  return builder.build(surface)
}

function main(): int {
  app := initGameApp{ title: "Doof Game Minimal" }

  app.key(.Escape).onPressed() {
    app.stop()
  }

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }
  })

  mesh := createMinimalMesh(app.surface)

  app.onRender((renderer): void => {
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.colorDepth(Color(0.02, 0.03, 0.04), 1.0),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      },
      (pass): void => {
        drawSimpleMesh(pass, mesh)
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
