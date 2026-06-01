import {
  Blend,
  Clear,
  Color,
  Depth,
  GameEventKind,
  GameSurface,
  Key,
  MouseButton,
  Point,
  Point3,
  RenderPassDescriptor,
  SimpleMesh,
  SimpleMeshBuilder,
  SimpleModelBatch,
  SimpleModelInstance,
  Texture,
  Transform,
  Vec2,
  drawSimpleModelBatch,
  initGameApp,
} from "std/game"
import { min } from "std/math"

import function buildJigsawAtlas(
  photoPath: string,
  maskAtlasPath: string,
  outputPath: string,
  columns: int,
  rows: int,
): Result<void, string> from "native_jigsaw.hpp" as doof_game_jigsaw::buildJigsawAtlas

const COLUMNS = 32
const ROWS = 32
const PIECE_SIZE = 128.0
readonly SOURCE_PHOTO_PATH = "images/IMG_0459.jpeg"
readonly MASK_ATLAS_PATH = "images/jigjig.png"
readonly GENERATED_ATLAS_PATH = "images/generated_jigsaw_atlas.png"

class PuzzleLayout {
  pieceSize: double
  step: double
  originX: double
  originY: double
}

class Piece {
  id: int
  column: int
  row: int
  x: double
  y: double
}

function uvOffset(column: int, row: int): Vec2 {
  return Vec2.xy(double(column) / double(COLUMNS), double(row) / double(ROWS))
}

function createLayout(surface: GameSurface): PuzzleLayout {
  surfaceWidth := double(surface.pixelWidth())
  surfaceHeight := double(surface.pixelHeight())
  margin := min(surfaceWidth, surfaceHeight) * 0.045
  availableWidth := surfaceWidth - margin * 2.0
  availableHeight := surfaceHeight - margin * 2.0
  pieceSize := min(
    availableWidth * 2.0 / double(COLUMNS + 1),
    availableHeight * 2.0 / double(ROWS + 1),
  )
  step := pieceSize * 0.5
  boardWidth := step * double(COLUMNS - 1) + pieceSize
  boardHeight := step * double(ROWS - 1) + pieceSize
  return PuzzleLayout {
    pieceSize: pieceSize,
    step: step,
    originX: (surfaceWidth - boardWidth) * 0.5,
    originY: (surfaceHeight - boardHeight) * 0.5,
  }
}

function createPieceMesh(surface: GameSurface, layout: PuzzleLayout): SimpleMesh {
  return SimpleMeshBuilder
    .create()
    .quad{
      a: Point3(0.0, 0.0, 0.0),
      b: Point3(layout.pieceSize, 0.0, 0.0),
      c: Point3(layout.pieceSize, layout.pieceSize, 0.0),
      d: Point3(0.0, layout.pieceSize, 0.0),
      color: Color.white,
      uvA: Point(0.0, 0.0),
      uvB: Point(1.0, 0.0),
      uvC: Point(1.0, 1.0),
      uvD: Point(0.0, 1.0),
    }
    .build(surface)
}

function createPieces(layout: PuzzleLayout): Piece[] {
  pieces: Piece[] := []
  for row of 0..<ROWS {
    for column of 0..<COLUMNS {
      id := row * COLUMNS + column
      homeX := layout.originX + double(column) * layout.step
      homeY := layout.originY + double(row) * layout.step
      scatterX := (double((id * 37) % 47) - 23.0) * layout.step / 72.0
      scatterY := (double((id * 53) % 41) - 20.0) * layout.step / 72.0
      pieces.push(Piece {
        id: id,
        column: column,
        row: row,
        x: homeX + scatterX,
        y: homeY + scatterY,
      })
    }
  }
  return pieces
}

function createDrawOrder(): int[] {
  order: int[] := []
  for id of 0..<COLUMNS * ROWS {
    order.push(id)
  }
  return order
}

function addPieceToBatch(batch: SimpleModelBatch, piece: Piece): SimpleModelInstance {
  return batch.add{
    transform: Transform.identity().withPosition(Point3(piece.x, piece.y, 0.0)),
    tint: Color.white,
    uvOffset: uvOffset(piece.column, piece.row),
    uvScale: Vec2.xy(1.0 / double(COLUMNS), 1.0 / double(ROWS)),
  }
}

function createBatch(
  surface: GameSurface,
  mesh: SimpleMesh,
  texture: Texture,
  pieces: Piece[],
  drawOrder: int[],
  excludedPiece: int,
): SimpleModelBatch {
  batch := SimpleModelBatch {
    surface: surface,
    mesh: mesh,
    texture: texture,
    capacity: COLUMNS * ROWS,
  }

  for index of 0..<drawOrder.length {
    pieceId := drawOrder[index]
    if pieceId != excludedPiece {
      addPieceToBatch(batch, pieces[pieceId])
    }
  }

  return batch
}

function createDragBatch(surface: GameSurface, mesh: SimpleMesh, texture: Texture): SimpleModelBatch {
  return SimpleModelBatch {
    surface: surface,
    mesh: mesh,
    texture: texture,
    capacity: 1,
  }
}

function hitTestPiece(piece: Piece, layout: PuzzleLayout, x: double, y: double): bool {
  hitSize := layout.pieceSize * 0.5
  inset := (layout.pieceSize - hitSize) * 0.5
  return x >= piece.x + inset && x <= piece.x + inset + hitSize && y >= piece.y + inset && y <= piece.y + inset + hitSize
}

function hitTestTopmost(pieces: Piece[], drawOrder: int[], layout: PuzzleLayout, x: double, y: double): int {
  let index = drawOrder.length - 1
  while index >= 0 {
    pieceId := drawOrder[index]
    if hitTestPiece(pieces[pieceId], layout, x, y) {
      return pieceId
    }
    index = index - 1
  }
  return -1
}

function removeFromDrawOrder(drawOrder: int[], pieceId: int): int[] {
  next: int[] := []
  for index of 0..<drawOrder.length {
    if drawOrder[index] != pieceId {
      next.push(drawOrder[index])
    }
  }
  return next
}

function bringToFront(drawOrder: int[], pieceId: int): int[] {
  next := removeFromDrawOrder(drawOrder, pieceId)
  next.push(pieceId)
  return next
}

function hasArg(args: string[], expected: string): bool {
  for index of 0..<args.length {
    if args[index] == expected {
      return true
    }
  }
  return false
}

function main(args: string[]): int {
  atlasResult := buildJigsawAtlas(SOURCE_PHOTO_PATH, MASK_ATLAS_PATH, GENERATED_ATLAS_PATH, COLUMNS, ROWS)
  case atlasResult {
    s: Success -> {}
    f: Failure -> {
      println(f.error)
      return 1
    }
  }

  if hasArg(args, "--preprocess-only") {
    println(GENERATED_ATLAS_PATH)
    return 0
  }

  app := initGameApp{ title: "Doof Game Jigsaw" }
  loadedAtlasTexture := app.loadTexture(GENERATED_ATLAS_PATH) else {
    case loadedAtlasTexture {
      f: Failure -> println(f.error)
      _: Success -> println("Failed to load generated jigsaw atlas")
    }
    return 1
  }

  layout := createLayout(app.surface)
  mesh := createPieceMesh(app.surface, layout)
  pieces := createPieces(layout)
  let drawOrder = createDrawOrder()
  let mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
  let dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)

  let draggedPiece = -1
  let dragOffsetX = 0.0
  let dragOffsetY = 0.0
  let dragInstance: SimpleModelInstance | null = null

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }

    if event.kind() == GameEventKind.KeyDown && event.key() == Key.Escape {
      app.stop()
    }

    if event.kind() == GameEventKind.MouseDown && event.mouseButton() == MouseButton.Left {
      hit := hitTestTopmost(pieces, drawOrder, layout, event.x(), event.y())
      if hit >= 0 {
        draggedPiece = hit
        piece := pieces[hit]
        dragOffsetX = event.x() - piece.x
        dragOffsetY = event.y() - piece.y
        drawOrder = removeFromDrawOrder(drawOrder, hit)
        mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, hit)
        dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        dragInstance = addPieceToBatch(dragBatch, piece)
        app.requestRender()
      }
    }

    if event.kind() == GameEventKind.MouseMove && draggedPiece >= 0 {
      piece := pieces[draggedPiece]
      piece.x = event.x() - dragOffsetX
      piece.y = event.y() - dragOffsetY
      if dragInstance != null {
        dragInstance!.setPosition(Point3(piece.x, piece.y, 0.0))
      }
      app.requestRender()
    }

    if event.kind() == GameEventKind.MouseUp && event.mouseButton() == MouseButton.Left && draggedPiece >= 0 {
      drawOrder = bringToFront(drawOrder, draggedPiece)
      mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
      dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
      dragInstance = null
      draggedPiece = -1
      app.requestRender()
    }
  })

  app.onRender((renderer): void => {
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.colorDepth(Color(0.04, 0.04, 0.045), 1.0),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      },
      (pass): void => {
        drawSimpleModelBatch(pass, mainBatch)
        drawSimpleModelBatch(pass, dragBatch)
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
