import {
  Blend,
  Clear,
  Color,
  ColorMesh,
  ColorMeshBuilder,
  Depth,
  GameEventKind,
  GameSurface,
  Key,
  Point3,
  RenderPassDescriptor,
  drawColorMesh,
  initGameApp,
} from "std/game"

function createMinimalMesh(surface: GameSurface): Result<ColorMesh, string> {
  builder := ColorMeshBuilder.create()

  topLeft := builder.addVertex(Point3.xyz(80.0, 80.0, 0.0), Color.rgb(0.95, 0.25, 0.12))
  topRight := builder.addVertex(Point3.xyz(400.0, 80.0, 0.0), Color.rgb(0.98, 0.72, 0.18))
  bottomRight := builder.addVertex(Point3.xyz(400.0, 280.0, 0.0), Color.rgb(0.15, 0.78, 0.42))
  bottomLeft := builder.addVertex(Point3.xyz(80.0, 280.0, 0.0), Color.rgb(0.12, 0.42, 0.95))

  builder.addIndexedTriangle(topLeft, topRight, bottomRight)
  builder.addIndexedTriangle(topLeft, bottomRight, bottomLeft)

  return builder.build(surface)
}

function main(): int {
  app := initGameApp{ title: "Doof Game Minimal" }

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }

    if event.kind() == .KeyDown && event.key() == .Escape {
      app.stop()
    }
  })

  mesh := createMinimalMesh(app.surface) else {
    panic("failed to create minimal mesh")
  }

  app.onRender((renderer): void => {
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.colorDepth(Color.rgb(0.02, 0.03, 0.04), 1.0),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      },
      (pass): void => {
        drawColorMesh(pass, mesh)
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
