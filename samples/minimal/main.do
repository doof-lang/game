import {
  Blend,
  Clear,
  Color,
  Depth,
  GameEventKind,
  Key,
  Rect,
  RenderPassDescriptor,
  drawRect,
  initGameApp,
} from "std/game"

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

  app.onRender((renderer): void => {
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.colorDepth(Color.rgb(0.02, 0.03, 0.04), 1.0),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      },
      (pass): void => {
        drawRect(pass, Rect.xywh(80.0, 80.0, 320.0, 200.0), Color.rgb(0.95, 0.25, 0.12))
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
