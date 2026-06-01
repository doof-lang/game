import {
  Atlas,
  Blend,
  Clear,
  Color,
  Depth,
  GameEventKind,
  Key,
  Point,
  Point3,
  RenderPassDescriptor,
  SimpleMeshBuilder,
  SimpleModelBatch,
  Transform,
  Vec2,
  Vec3,
  drawSimpleModelBatch,
  initGameApp,
} from "std/game"

function cardUvOffset(column: int, row: int, columns: int, rows: int): Vec2 {
  return Vec2.xy(double(column) / double(columns), double(row) / double(rows))
}

function main(): int {
  readonly cardAtlasPath = "/Users/andrew/develop/doof-stdlib/game/samples/cards/images/card_atlas.png"
  readonly cardColumns = 14
  readonly cardRows = 4
  readonly cardWidth = 121.0
  readonly cardHeight = 176.0
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
  cardMesh := SimpleMeshBuilder
    .create()
    .quad{
      a: Point3(0.0, 0.0, 0.0),
      b: Point3(cardWidth, 0.0, 0.0),
      c: Point3(cardWidth, cardHeight, 0.0),
      d: Point3(0.0, cardHeight, 0.0),
      color: Color.white,
      uvA: Point(0.0, 0.0),
      uvB: Point(1.0, 0.0),
      uvC: Point(1.0, 1.0),
      uvD: Point(0.0, 1.0),
    }
    .build(app.surface)

  cardBatch := SimpleModelBatch {
    surface: app.surface,
    mesh: cardMesh,
    texture: cardAtlas.texture,
    capacity: 6,
  }
  uvScale := Vec2.xy(1.0 / double(cardColumns), 1.0 / double(cardRows))
  cardBatch.add{
    transform: Transform.identity().withPosition(Point3(80.0, 90.0, 0.0)),
    uvOffset: cardUvOffset(0, 0, cardColumns, cardRows),
    uvScale: uvScale,
  }
  cardBatch.add{
    transform: Transform.identity().withPosition(Point3(220.0, 90.0, 0.0)),
    uvOffset: cardUvOffset(10, 1, cardColumns, cardRows),
    uvScale: uvScale,
  }
  cardBatch.add{
    transform: Transform.identity().withPosition(Point3(360.0, 90.0, 0.0)),
    uvOffset: cardUvOffset(12, 2, cardColumns, cardRows),
    uvScale: uvScale,
  }
  cardBatch.add{
    transform: Transform.identity().withPosition(Point3(500.0, 90.0, 0.0)),
    uvOffset: cardUvOffset(13, 0, cardColumns, cardRows),
    uvScale: uvScale,
  }
  cardBatch.add{
    transform: Transform.identity().withPosition(Point3(640.0, 90.0, 0.0)),
    uvOffset: cardUvOffset(13, 1, cardColumns, cardRows),
    uvScale: uvScale,
  }
  joker := cardBatch.add{
    transform: Transform.identity().withPosition(Point3(780.0, 90.0, 0.0)),
    uvOffset: cardUvOffset(13, 2, cardColumns, cardRows),
    uvScale: uvScale,
  }
  joker.moveWorldBy(Vec3.xyz(0.0, 12.0, 0.0)).setTint(Color(0.9, 1.0, 0.9))

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
        drawSimpleModelBatch(pass, cardBatch)
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
