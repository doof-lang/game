import { abs, min } from "std/math"
import { randomInt } from "std/random"

export readonly COLUMNS = 32
export readonly ROWS = 32
export readonly PIECE_SIZE = 128.0
export readonly PUZZLE_STATE_VERSION = 1
export readonly PIECE_HIT_SIZE_SCALE = 0.62

export class PuzzleLayout {
  pieceSize: double
  step: double
  originX: double
  originY: double
  boardWidth: double
  boardHeight: double
}

export class PuzzleCamera {
  x: double
  y: double
  zoom: double
  minZoom: double
  maxZoom: double
}

export class Piece {
  id: int
  column: int
  row: int
  group: int
  x: double
  y: double
}

export class SnapMatch {
  targetGroup: int
  dx: double
  dy: double
}

export class PuzzleState {
  version: int
  columns: int
  rows: int
  pieces: Piece[]
  drawOrder: int[]
  camera: PuzzleCamera
}

export class GroupPosition {
  groupId: int
  x: double
  y: double
}

export function clampDouble(value: double, low: double, high: double): double {
  if value < low {
    return low
  }
  if value > high {
    return high
  }
  return value
}

export function createLayoutForSize(surfaceWidth: double, surfaceHeight: double): PuzzleLayout {
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

export function createCameraForSize(surfaceWidth: double, surfaceHeight: double, layout: PuzzleLayout): PuzzleCamera {
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

export function createPieces(layout: PuzzleLayout): Piece[] {
  pieces: Piece[] := []
  for row of 0..<ROWS {
    for column of 0..<COLUMNS {
      id := row * COLUMNS + column
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

export function createDrawOrder(): int[] {
  order: int[] := []
  for id of 0..<COLUMNS * ROWS {
    order.push(id)
  }
  return order
}

export function cloneCamera(camera: PuzzleCamera): PuzzleCamera {
  return PuzzleCamera { x: camera.x, y: camera.y, zoom: camera.zoom, minZoom: camera.minZoom, maxZoom: camera.maxZoom }
}

export function clonePiece(piece: Piece): Piece {
  return Piece { id: piece.id, column: piece.column, row: piece.row, group: piece.group, x: piece.x, y: piece.y }
}

export function clonePieces(pieces: Piece[]): Piece[] {
  cloned: Piece[] := []
  for piece of pieces {
    cloned.push(clonePiece(piece))
  }
  return cloned
}

export function cloneIntArray(values: int[]): int[] {
  cloned: int[] := []
  for value of values {
    cloned.push(value)
  }
  return cloned
}

export function clonePuzzleState(state: PuzzleState): PuzzleState {
  return PuzzleState {
    version: state.version,
    columns: state.columns,
    rows: state.rows,
    pieces: clonePieces(state.pieces),
    drawOrder: cloneIntArray(state.drawOrder),
    camera: cloneCamera(state.camera),
  }
}

export function createPuzzleState(pieces: Piece[], drawOrder: int[], camera: PuzzleCamera): PuzzleState {
  return PuzzleState {
    version: PUZZLE_STATE_VERSION,
    columns: COLUMNS,
    rows: ROWS,
    pieces,
    drawOrder,
    camera,
  }
}

export function validatePuzzleState(state: PuzzleState): Result<void, string> {
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
    if piece.group < 0 {
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

export function hitTestPiece(piece: Piece, layout: PuzzleLayout, x: double, y: double): bool {
  hitSize := layout.pieceSize * PIECE_HIT_SIZE_SCALE
  inset := (layout.pieceSize - hitSize) * 0.5
  return x >= piece.x + inset && x <= piece.x + inset + hitSize && y >= piece.y + inset && y <= piece.y + inset + hitSize
}

export function hitTestTopmost(pieces: Piece[], drawOrder: int[], layout: PuzzleLayout, x: double, y: double): int {
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

export function removeGroupFromDrawOrder(pieces: Piece[], drawOrder: int[], group: int): int[] {
  next: int[] := []
  for index of 0..<drawOrder.length {
    pieceId := drawOrder[index]
    if pieces[pieceId].group != group {
      next.push(pieceId)
    }
  }
  return next
}

export function bringGroupToFront(pieces: Piece[], drawOrder: int[], group: int): int[] {
  next := removeGroupFromDrawOrder(pieces, drawOrder, group)
  for id of 0..<COLUMNS * ROWS {
    if pieces[id].group == group {
      next.push(id)
    }
  }
  return next
}

export function moveGroup(pieces: Piece[], group: int, dx: double, dy: double): void {
  for id of 0..<COLUMNS * ROWS {
    if pieces[id].group == group {
      pieces[id].x = pieces[id].x + dx
      pieces[id].y = pieces[id].y + dy
    }
  }
}

export function firstPieceInGroup(pieces: Piece[], group: int): int {
  for id of 0..<COLUMNS * ROWS {
    if pieces[id].group == group {
      return id
    }
  }
  return -1
}

export function groupPosition(pieces: Piece[], group: int): GroupPosition {
  pieceId := firstPieceInGroup(pieces, group)
  if pieceId < 0 {
    return GroupPosition { groupId: group, x: 0.0, y: 0.0 }
  }
  piece := pieces[pieceId]
  return GroupPosition { groupId: group, x: piece.x, y: piece.y }
}

export function setGroupPosition(pieces: Piece[], group: int, x: double, y: double): void {
  pieceId := firstPieceInGroup(pieces, group)
  if pieceId >= 0 {
    setGroupPositionFromPiece(pieces, group, pieceId, x, y)
  }
}

export function setGroupCanonicalPosition(pieces: Piece[], group: int, x: double, y: double): void {
  anchorPieceId := firstPieceInGroup(pieces, group)
  if anchorPieceId < 0 {
    return
  }
  anchor := pieces[anchorPieceId]
  step := PIECE_SIZE * 0.5
  for id of 0..<COLUMNS * ROWS {
    piece := pieces[id]
    if piece.group == group {
      piece.x = x + double(piece.column - anchor.column) * step
      piece.y = y + double(piece.row - anchor.row) * step
    }
  }
}

export function setGroupPositionFromPiece(pieces: Piece[], group: int, pieceId: int, x: double, y: double): void {
  dx := x - pieces[pieceId].x
  dy := y - pieces[pieceId].y
  moveGroup(pieces, group, dx, dy)
}

export function mergeGroups(pieces: Piece[], fromGroup: int, intoGroup: int): void {
  for id of 0..<COLUMNS * ROWS {
    if pieces[id].group == fromGroup {
      pieces[id].group = intoGroup
    }
  }
}

export function groupPieceIds(pieces: Piece[], group: int): int[] {
  ids: int[] := []
  for id of 0..<COLUMNS * ROWS {
    if pieces[id].group == group {
      ids.push(id)
    }
  }
  return ids
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

export function findSnapMatch(pieces: Piece[], layout: PuzzleLayout, group: int): SnapMatch | null {
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

export function joinNearbyPieces(pieces: Piece[], layout: PuzzleLayout, group: int): int[] {
  joinedGroups: int[] := [group]
  let searching = true
  while searching {
    match := findSnapMatch(pieces, layout, group)
    if match != null {
      if !joinedGroups.contains(match!.targetGroup) {
        joinedGroups.push(match!.targetGroup)
      }
      moveGroup(pieces, group, match!.dx, match!.dy)
      mergeGroups(pieces, match!.targetGroup, group)
    } else {
      searching = false
    }
  }
  return joinedGroups
}
