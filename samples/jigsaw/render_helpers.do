import {
  Color,
  GameSurface,
  Point,
  Point3,
  SimpleMesh,
  SimpleMeshBuilder,
  SimpleModelBatch,
  SimpleModelInstance,
  Texture,
  Transform,
  Vec2,
  Vec3,
} from "std/game"

import {
  COLUMNS,
  ROWS,
  Piece,
  PuzzleCamera,
  PuzzleLayout,
} from "./jigsaw_model"

export function cameraTransform(camera: PuzzleCamera): Transform {
  inverseZoom := 1.0 / camera.zoom
  return Transform
    .identity()
    .withPosition(Point3(camera.x, camera.y, 0.0))
    .withScale(Vec3.xyz(inverseZoom, inverseZoom, 1.0))
}

function uvOffset(column: int, row: int): Vec2 {
  return Vec2.xy(double(column) / double(COLUMNS), double(row) / double(ROWS))
}

export function createPieceMesh(surface: GameSurface, layout: PuzzleLayout): SimpleMesh {
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

function addPieceToBatch(batch: SimpleModelBatch, piece: Piece): SimpleModelInstance {
  return batch.add{
    transform: Transform.identity().withPosition(Point3(piece.x, piece.y, 0.0)),
    tint: Color.white,
    uvOffset: uvOffset(piece.column, piece.row),
    uvScale: Vec2.xy(1.0 / double(COLUMNS), 1.0 / double(ROWS)),
  }
}

export function createBatch(
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

export function createDragBatch(surface: GameSurface, mesh: SimpleMesh, texture: Texture): SimpleModelBatch {
  return SimpleModelBatch {
    surface: surface,
    mesh: mesh,
    texture: texture,
    capacity: COLUMNS * ROWS,
  }
}

export function addGroupToBatch(batch: SimpleModelBatch, pieces: Piece[], group: int): void {
  for id of 0..<COLUMNS * ROWS {
    if pieces[id].group == group {
      addPieceToBatch(batch, pieces[id])
    }
  }
}
