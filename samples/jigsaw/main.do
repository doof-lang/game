import {
  Blend,
  Camera,
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
  Vec3,
  drawSimpleModelBatch,
  initGameApp,
} from "std/game"
import { exists, readText, writeText, IoError } from "std/fs"
import { formatJsonValue, parseJsonValue } from "std/json"
import { abs, min } from "std/math"
import { randomInt } from "std/random"
import { dataDirectory, join, resourcesDirectory } from "std/path"

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
const PUZZLE_STATE_VERSION = 1
readonly SOURCE_PHOTO_PATH = "images/IMG_0459.jpeg"
readonly MASK_ATLAS_PATH = "images/jigjig.png"
readonly GENERATED_ATLAS_PATH = "images/generated_jigsaw_atlas.png"
readonly PUZZLE_STATE_FILE = "puzzle-state.json"

class PuzzleLayout {
  pieceSize: double
  step: double
  originX: double
  originY: double
  boardWidth: double
  boardHeight: double
}

class PuzzleCamera {
  x: double
  y: double
  zoom: double
  minZoom: double
  maxZoom: double
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

class PuzzleState {
  version: int
  columns: int
  rows: int
  pieces: Piece[]
  drawOrder: int[]
  camera: PuzzleCamera
}

function uvOffset(column: int, row: int): Vec2 {
  return Vec2.xy(double(column) / double(COLUMNS), double(row) / double(ROWS))
}

function clampDouble(value: double, low: double, high: double): double {
  if value < low {
    return low
  }
  if value > high {
    return high
  }
  return value
}

function createLayout(surface: GameSurface): PuzzleLayout {
  surfaceWidth := double(surface.pixelWidth())
  pieceSize := PIECE_SIZE
  step := pieceSize * 0.5
  boardWidth := step * double(COLUMNS - 1) + pieceSize
  boardHeight := step * double(ROWS - 1) + pieceSize
  return PuzzleLayout {
    pieceSize,
    step,
    originX: 0.0,
    originY: 0.0,
    boardWidth,
    boardHeight,
  }
}

function createCamera(surface: GameSurface, layout: PuzzleLayout): PuzzleCamera {
  surfaceWidth := double(surface.pixelWidth())
  surfaceHeight := double(surface.pixelHeight())
  fitZoom := min(surfaceWidth * 0.92 / layout.boardWidth, surfaceHeight * 0.92 / layout.boardHeight)
  targetPiecePixels := if min(surfaceWidth, surfaceHeight) < 1400.0 then 96.0 else 64.0
  readableZoom := targetPiecePixels / layout.pieceSize
  zoom := clampDouble(if readableZoom > fitZoom then readableZoom else fitZoom, fitZoom * 0.85, 3.0)
  return PuzzleCamera {
    x: layout.originX + layout.boardWidth * 0.5 - surfaceWidth * 0.5 / zoom,
    y: layout.originY + layout.boardHeight * 0.5 - surfaceHeight * 0.5 / zoom,
    zoom,
    minZoom: fitZoom * 0.85,
    maxZoom: 3.0,
  }
}

function screenToWorldX(camera: PuzzleCamera, x: double): double {
  return camera.x + x / camera.zoom
}

function screenToWorldY(camera: PuzzleCamera, y: double): double {
  return camera.y + y / camera.zoom
}

function applyZoomAt(camera: PuzzleCamera, screenX: double, screenY: double, factor: double): void {
  worldX := screenToWorldX(camera, screenX)
  worldY := screenToWorldY(camera, screenY)
  camera.zoom = clampDouble(camera.zoom * clampDouble(factor, 0.5, 1.5), camera.minZoom, camera.maxZoom)
  camera.x = worldX - screenX / camera.zoom
  camera.y = worldY - screenY / camera.zoom
}

function cameraTransform(camera: PuzzleCamera): Transform {
  inverseZoom := 1.0 / camera.zoom
  return Transform
    .identity()
    .withPosition(Point3(camera.x, camera.y, 0.0))
    .withScale(Vec3.xyz(inverseZoom, inverseZoom, 1.0))
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

function ioErrorMessage(operation: string, path: string, error: IoError): string {
  return "${operation} failed for ${path}: ${error}"
}

function puzzleStatePath(): string {
  directory := dataDirectory() else error {
    panic("Failed to resolve puzzle state data directory: ${error}")
  }
  return join([directory, PUZZLE_STATE_FILE])
}

function createPuzzleState(pieces: Piece[], drawOrder: int[], camera: PuzzleCamera): PuzzleState {
  return PuzzleState {
    version: PUZZLE_STATE_VERSION,
    columns: COLUMNS,
    rows: ROWS,
    pieces,
    drawOrder,
    camera,
  }
}

function validatePuzzleState(state: PuzzleState): Result<void, string> {
  pieceCount := COLUMNS * ROWS
  if state.version != PUZZLE_STATE_VERSION {
    return Failure("Unsupported puzzle state version ${state.version}")
  }
  if state.columns != COLUMNS || state.rows != ROWS {
    return Failure("Puzzle state dimensions do not match this puzzle")
  }
  if state.pieces.length != pieceCount {
    return Failure("Puzzle state has ${state.pieces.length} pieces, expected ${pieceCount}")
  }
  if state.drawOrder.length != pieceCount {
    return Failure("Puzzle state draw order has ${state.drawOrder.length} entries, expected ${pieceCount}")
  }

  pieceIds: int[] := []
  drawIds: int[] := []
  for id of 0..<pieceCount {
    pieceIds.push(0)
    drawIds.push(0)
  }

  for index of 0..<state.pieces.length {
    piece := state.pieces[index]
    if piece.id < 0 || piece.id >= pieceCount {
      return Failure("Puzzle state contains invalid piece id ${piece.id}")
    }
    if piece.column != piece.id % COLUMNS || piece.row != piece.id \ COLUMNS {
      return Failure("Puzzle state contains invalid coordinates for piece ${piece.id}")
    }
    if piece.group < 0 || piece.group >= pieceCount {
      return Failure("Puzzle state contains invalid group ${piece.group}")
    }
    if pieceIds[piece.id] != 0 {
      return Failure("Puzzle state contains duplicate piece id ${piece.id}")
    }
    pieceIds[piece.id] = 1
  }

  for index of 0..<state.drawOrder.length {
    pieceId := state.drawOrder[index]
    if pieceId < 0 || pieceId >= pieceCount {
      return Failure("Puzzle state contains invalid draw order id ${pieceId}")
    }
    if drawIds[pieceId] != 0 {
      return Failure("Puzzle state contains duplicate draw order id ${pieceId}")
    }
    drawIds[pieceId] = 1
  }

  return Success()
}

function loadPuzzleState(path: string): Result<PuzzleState, string> {
  text := readText(path) else error {
    return Failure(ioErrorMessage("read", path, error))
  }

  try json := parseJsonValue(text)
  try state := PuzzleState.fromJsonValue(json)
  try validatePuzzleState(state)
  return Success(state)
}

function savePuzzleState(path: string, pieces: Piece[], drawOrder: int[], camera: PuzzleCamera): Result<void, string> {
  state := createPuzzleState(pieces, drawOrder, camera)
  try validatePuzzleState(state)

  writeText(path, formatJsonValue(state.toJsonObject())) else error {
    return Failure(ioErrorMessage("write", path, error))
  }

  return Success()
}

function savePuzzleStateSafely(
  statePath: string,
  pieces: Piece[],
  drawOrder: int[],
  camera: PuzzleCamera,
): void {
  savePuzzleState(statePath, pieces, drawOrder, camera) else error {
    println("Failed to save puzzle state: ${error}")
  }
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

  buildJigsawAtlas(sourcePhoto, maskAtlas, generatedAtlas, COLUMNS, ROWS) else error {
    println(error)
    return 1
  }

  app := initGameApp{ title: "Doof Game Jigsaw" }
  loadedAtlasTexture := app.loadTexture(generatedAtlas) else error {
    println(error)
    return 1
  }

  layout := createLayout(app.surface)
  let camera = createCamera(app.surface, layout)
  mesh := createPieceMesh(app.surface, layout)
  let pieces = createPieces(layout)
  let drawOrder = createDrawOrder()
  statePath := puzzleStatePath()

  if exists(statePath) {
    case loadPuzzleState(statePath) {
      loaded: Success -> {
        pieces = loaded.value.pieces
        drawOrder = loaded.value.drawOrder
        camera = loaded.value.camera
      }
      failed: Failure -> println("Ignoring saved puzzle state: ${failed.error}")
    }
  }

  let mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
  let dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)

  let draggedPiece = -1
  let draggedGroup = -1
  let dragOffsetX = 0.0
  let dragOffsetY = 0.0

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      if draggedPiece >= 0 {
        drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
        mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
        dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        draggedPiece = -1
        draggedGroup = -1
      }
      savePuzzleStateSafely(statePath, pieces, drawOrder, camera)
      app.stop()
    }

    if event.kind() == GameEventKind.KeyDown && event.key() == Key.Escape {
      if draggedPiece >= 0 {
        drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
        mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
        dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        draggedPiece = -1
        draggedGroup = -1
      }
      savePuzzleStateSafely(statePath, pieces, drawOrder, camera)
      app.stop()
    }

    if event.kind() == GameEventKind.MouseDown && event.mouseButton() == MouseButton.Left {
      worldX := screenToWorldX(camera, event.x())
      worldY := screenToWorldY(camera, event.y())
      hit := hitTestTopmost(pieces, drawOrder, layout, worldX, worldY)
      if hit >= 0 {
        draggedPiece = hit
        draggedGroup = pieces[hit].group
        piece := pieces[hit]
        dragOffsetX = worldX - piece.x
        dragOffsetY = worldY - piece.y
        drawOrder = removeGroupFromDrawOrder(pieces, drawOrder, draggedGroup)
        mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, draggedGroup)
        dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        addGroupToBatch(dragBatch, pieces, draggedGroup)
        app.requestRender()
      }
    }

    if event.kind() == GameEventKind.MouseMove && draggedPiece >= 0 {
      worldX := screenToWorldX(camera, event.x())
      worldY := screenToWorldY(camera, event.y())
      setGroupPositionFromPiece(pieces, draggedGroup, draggedPiece, worldX - dragOffsetX, worldY - dragOffsetY)
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
      savePuzzleStateSafely(statePath, pieces, drawOrder, camera)
      app.requestRender()
    }

    if event.kind() == GameEventKind.MouseUp && event.mouseButton() != MouseButton.Left && draggedPiece >= 0 {
      drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
      mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
      dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
      draggedPiece = -1
      draggedGroup = -1
      savePuzzleStateSafely(statePath, pieces, drawOrder, camera)
      app.requestRender()
    }

    if event.kind() == GameEventKind.MouseWheel {
      if draggedPiece >= 0 {
        drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
        mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
        dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        draggedPiece = -1
        draggedGroup = -1
      }
      camera.x = camera.x - event.deltaX() / camera.zoom
      camera.y = camera.y - event.deltaY() / camera.zoom
      applyZoomAt(camera, event.x(), event.y(), 1.0 + event.wheelDeltaY() * 0.003)
      savePuzzleStateSafely(statePath, pieces, drawOrder, camera)
      app.requestRender()
    }
  })

  app.onRender((renderer): void => {
    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.colorDepth(Color(0.04, 0.04, 0.045), 1.0),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
        camera: Camera.screen().withTransform(cameraTransform(camera)),
      },
      (pass): void => {
        drawSimpleModelBatch(pass, mainBatch)
        drawSimpleModelBatch(pass, dragBatch)
      },
    )
  })

  app.run() else error {
    println(error)
    return 1
  }
  return 0
}
