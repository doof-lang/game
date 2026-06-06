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
import { abs, min } from "std/math"
import { randomInt } from "std/random"
import { join, resourcesDirectory } from "std/path"

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
  boardWidth: double
  boardHeight: double
}

class Piece {
  id: int
  column: int
  row: int
  group: int
  x: double
  y: double
}

class SnapMatch {
  targetGroup: int
  dx: double
  dy: double
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
    pieceSize,
    step,
    originX: (surfaceWidth - boardWidth) * 0.5,
    originY: (surfaceHeight - boardHeight) * 0.5,
    boardWidth,
    boardHeight,
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
        group: id,
        x: randomInt(int(layout.boardWidth)),
        y: randomInt(int(layout.boardHeight)),
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
  excludedGroup: int,
): SimpleModelBatch {
  batch := SimpleModelBatch {
    surface: surface,
    mesh: mesh,
    texture: texture,
    capacity: COLUMNS * ROWS,
  }

  for index of 0..<drawOrder.length {
    pieceId := drawOrder[index]
    if excludedGroup < 0 || pieces[pieceId].group != excludedGroup {
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
    capacity: COLUMNS * ROWS,
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

function removeGroupFromDrawOrder(pieces: Piece[], drawOrder: int[], group: int): int[] {
  next: int[] := []
  for index of 0..<drawOrder.length {
    pieceId := drawOrder[index]
    if pieces[pieceId].group != group {
      next.push(pieceId)
    }
  }
  return next
}

function bringGroupToFront(pieces: Piece[], drawOrder: int[], group: int): int[] {
  next := removeGroupFromDrawOrder(pieces, drawOrder, group)
  for id of 0..<COLUMNS * ROWS {
    if pieces[id].group == group {
      next.push(id)
    }
  }
  return next
}

function addGroupToBatch(batch: SimpleModelBatch, pieces: Piece[], group: int): void {
  for id of 0..<COLUMNS * ROWS {
    if pieces[id].group == group {
      addPieceToBatch(batch, pieces[id])
    }
  }
}

function moveGroup(pieces: Piece[], group: int, dx: double, dy: double): void {
  for id of 0..<COLUMNS * ROWS {
    if pieces[id].group == group {
      pieces[id].x = pieces[id].x + dx
      pieces[id].y = pieces[id].y + dy
    }
  }
}

function setGroupPositionFromPiece(pieces: Piece[], group: int, pieceId: int, x: double, y: double): void {
  dx := x - pieces[pieceId].x
  dy := y - pieces[pieceId].y
  moveGroup(pieces, group, dx, dy)
}

function mergeGroups(pieces: Piece[], fromGroup: int, intoGroup: int): void {
  for id of 0..<COLUMNS * ROWS {
    if pieces[id].group == fromGroup {
      pieces[id].group = intoGroup
    }
  }
}

function snapMatchIfClose(piece: Piece, neighbor: Piece, layout: PuzzleLayout, dx: double, dy: double): SnapMatch | null {
  threshold := layout.step * 0.32
  if abs(dx) <= threshold && abs(dy) <= threshold {
    return SnapMatch {
      targetGroup: neighbor.group,
      dx: dx,
      dy: dy,
    }
  }
  return null
}

function findSnapMatch(pieces: Piece[], layout: PuzzleLayout, group: int): SnapMatch | null {
  for id of 0..<COLUMNS * ROWS {
    piece := pieces[id]
    if piece.group == group {
      if piece.column < COLUMNS - 1 {
        neighbor := pieces[piece.id + 1]
        if neighbor.group != group {
          match := snapMatchIfClose(piece, neighbor, layout, neighbor.x - layout.step - piece.x, neighbor.y - piece.y)
          if match != null {
            return match
          }
        }
      }

      if piece.column > 0 {
        neighbor := pieces[piece.id - 1]
        if neighbor.group != group {
          match := snapMatchIfClose(piece, neighbor, layout, neighbor.x + layout.step - piece.x, neighbor.y - piece.y)
          if match != null {
            return match
          }
        }
      }

      if piece.row < ROWS - 1 {
        neighbor := pieces[piece.id + COLUMNS]
        if neighbor.group != group {
          match := snapMatchIfClose(piece, neighbor, layout, neighbor.x - piece.x, neighbor.y - layout.step - piece.y)
          if match != null {
            return match
          }
        }
      }

      if piece.row > 0 {
        neighbor := pieces[piece.id - COLUMNS]
        if neighbor.group != group {
          match := snapMatchIfClose(piece, neighbor, layout, neighbor.x - piece.x, neighbor.y + layout.step - piece.y)
          if match != null {
            return match
          }
        }
      }
    }
  }
  return null
}

function joinNearbyPieces(pieces: Piece[], layout: PuzzleLayout, group: int): void {
  let searching = true
  while searching {
    match := findSnapMatch(pieces, layout, group)
    if match != null {
      moveGroup(pieces, group, match!.dx, match!.dy)
      mergeGroups(pieces, match!.targetGroup, group)
    } else {
      searching = false
    }
  }
}

function main(): int {
  resources := try! resourcesDirectory()
  sourcePhoto := join([resources, SOURCE_PHOTO_PATH])
  maskAtlas := join([resources, MASK_ATLAS_PATH])
  generatedAtlas := join([resources, GENERATED_ATLAS_PATH])

  atlasResult := buildJigsawAtlas(sourcePhoto, maskAtlas, generatedAtlas, COLUMNS, ROWS)
  case atlasResult {
    s: Success -> {}
    f: Failure -> {
      println(f.error)
      return 1
    }
  }

  app := initGameApp{ title: "Doof Game Jigsaw" }
  loadedAtlasTexture := app.loadTexture(generatedAtlas) else {
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
  let draggedGroup = -1
  let dragOffsetX = 0.0
  let dragOffsetY = 0.0

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
        draggedGroup = pieces[hit].group
        piece := pieces[hit]
        dragOffsetX = event.x() - piece.x
        dragOffsetY = event.y() - piece.y
        drawOrder = removeGroupFromDrawOrder(pieces, drawOrder, draggedGroup)
        mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, draggedGroup)
        dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        addGroupToBatch(dragBatch, pieces, draggedGroup)
        app.requestRender()
      }
    }

    if event.kind() == GameEventKind.MouseMove && draggedPiece >= 0 {
      setGroupPositionFromPiece(pieces, draggedGroup, draggedPiece, event.x() - dragOffsetX, event.y() - dragOffsetY)
      dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
      addGroupToBatch(dragBatch, pieces, draggedGroup)
      app.requestRender()
    }

    if event.kind() == GameEventKind.MouseUp && event.mouseButton() == MouseButton.Left && draggedPiece >= 0 {
      joinNearbyPieces(pieces, layout, draggedGroup)
      drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
      mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
      dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
      draggedPiece = -1
      draggedGroup = -1
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
