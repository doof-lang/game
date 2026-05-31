import {
  Atlas,
  Blend,
  Clear,
  Color,
  Depth,
  GameEventKind,
  Key,
  Rect,
  RenderPassDescriptor,
  TextureQuadBatchBuilder,
  drawTextureQuadBatch,
  initGameApp,
} from "std/game"

function main(): int {
  readonly cardAtlasPath = "/Users/andrew/develop/doof-stdlib/game/samples/cards/images/card_atlas.png"
  readonly cardColumns = 14
  readonly cardRows = 4
  app := initGameApp{ title: "Doof Game Cards" }

  loadedAtlasTexture := app.loadTexture(cardAtlasPath) else {
    case loadedAtlasTexture {
      f: Failure -> println(f.error)
      _: Success -> println("Failed to load card atlas texture")
    }
    return 1
  }
  cardAtlas := Atlas {
    texture: loadedAtlasTexture,
    columns: cardColumns,
    rows: cardRows,
  }
  batchBuilder := TextureQuadBatchBuilder.forAtlas(cardAtlas)
  batchBuilder.addAtlasCell(cardAtlas, 0, 0, Rect.xywh(80.0, 90.0, 121.0, 176.0))
  batchBuilder.addAtlasCell(cardAtlas, 10, 1, Rect.xywh(220.0, 90.0, 121.0, 176.0))
  batchBuilder.addAtlasCell(cardAtlas, 12, 2, Rect.xywh(360.0, 90.0, 121.0, 176.0))
  batchBuilder.addAtlasCell(cardAtlas, 13, 0, Rect.xywh(500.0, 90.0, 121.0, 176.0))
  batchBuilder.addAtlasCell(cardAtlas, 13, 1, Rect.xywh(640.0, 90.0, 121.0, 176.0))
  batchBuilder.addAtlasCell(cardAtlas, 13, 2, Rect.xywh(780.0, 90.0, 121.0, 176.0))
  cardBatch := batchBuilder.build(app.surface) else {
    case cardBatch {
      f: Failure -> println(f.error)
      _: Success -> println("Failed to build card batch")
    }
    return 1
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
        clear: Clear.colorDepth(Color(0.03, 0.16, 0.10), 1.0),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      },
      (pass): void => {
        drawTextureQuadBatch(pass, cardBatch)
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
