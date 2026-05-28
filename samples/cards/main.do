import {
  Atlas,
  Blend,
  Clear,
  Color,
  Depth,
  GameEventKind,
  Key,
  Rect,
  RenderPass,
  RenderPassDescriptor,
  drawAtlasCell,
  initGameApp,
} from "std/game"

function drawCard(pass: RenderPass, atlas: Atlas, column: int, row: int, x: double, y: double): void {
  drawAtlasCell(pass, atlas, column, row, Rect.xywh(x, y, 121.0, 176.0))
}

function main(): int {
  readonly cardAtlasPath = "/Users/andrew/develop/doof-stdlib/game/samples/cards/images/card_atlas.png"
  readonly cardColumns = 14
  readonly cardRows = 4
  app := initGameApp{ title: "Doof Game Cards" }

  loadedAtlasTexture := app.loadTexture(cardAtlasPath) else {
    println("Failed to load card atlas texture")
    return 1
  }
  cardAtlas := Atlas {
        texture: loadedAtlasTexture,
        columns: cardColumns,
        rows: cardRows,
  }

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }

    if event.kind() == GameEventKind.KeyDown && event.key() == Key.Escape {
      app.stop()
    }
  })

  app.onRender((renderer): void => {
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.colorDepth(Color.rgb(0.03, 0.16, 0.10), 1.0),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      },
      (pass): void => {
        drawCard(pass, cardAtlas, 0, 0, 80.0, 90.0)
        drawCard(pass, cardAtlas, 10, 1, 220.0, 90.0)
        drawCard(pass, cardAtlas, 12, 2, 360.0, 90.0)
        drawCard(pass, cardAtlas, 13, 0, 500.0, 90.0)
        drawCard(pass, cardAtlas, 13, 1, 640.0, 90.0)
        drawCard(pass, cardAtlas, 13, 2, 780.0, 90.0)
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
