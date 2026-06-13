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
import { drainMainEventLoop } from "std/event"
import { exists, readText, writeText, IoError } from "std/fs"
import { formatJsonValue, parseJsonValue } from "std/json"
import { abs } from "std/math"
import { dataDirectory, join, resourcesDirectory } from "std/path"

import {
  COLUMNS,
  ROWS,
  Piece,
  PuzzleCamera,
  PuzzleLayout,
  PuzzleState,
  bringGroupToFront,
  clampDouble,
  createCameraForSize,
  createDrawOrder,
  createLayoutForSize,
  createPieces,
  createPuzzleState,
  groupPosition,
  hitTestTopmost,
  joinNearbyPieces,
  removeGroupFromDrawOrder,
  setGroupCanonicalPosition,
  setGroupPositionFromPiece,
  validatePuzzleState,
} from "./jigsaw_model"
import {
  JigsawClientConnection,
  JigsawServerEvent,
  JigsawServerEventKind,
  JigsawSession,
  createJigsawSession,
  sendJoinGroups,
  sendMoveGroup,
} from "./session"
import { connectJigsawServer } from "./protocol"

import function buildJigsawAtlas(
  photoPath: string,
  maskAtlasPath: string,
  outputPath: string,
  columns: int,
  rows: int,
): Result<void, string> from "native_jigsaw.hpp" as doof_game_jigsaw::buildJigsawAtlas

const ZOOM_DELTA_SCALE = 0.002
const EVENT_DRAIN_PUMP_LIMIT = 16
readonly SOURCE_PHOTO_PATH = "images/IMG_0459.jpeg"
readonly MASK_ATLAS_PATH = "images/jigjig.png"
readonly GENERATED_ATLAS_PATH = "images/generated_jigsaw_atlas.png"
readonly PUZZLE_STATE_FILE = "puzzle-state.json"

function uvOffset(column: int, row: int): Vec2 {
  return Vec2.xy(double(column) / double(COLUMNS), double(row) / double(ROWS))
}

function createLayout(surface: GameSurface): PuzzleLayout {
  return createLayoutForSize(double(surface.pixelWidth()), double(surface.pixelHeight()))
}

function createCamera(surface: GameSurface, layout: PuzzleLayout): PuzzleCamera {
  return createCameraForSize(double(surface.pixelWidth()), double(surface.pixelHeight()), layout)
}

function screenToWorldX(camera: PuzzleCamera, x: double): double {
  return camera.x + x / camera.zoom
}

function screenToWorldY(camera: PuzzleCamera, y: double): double {
  return camera.y + y / camera.zoom
}

function setZoomAt(camera: PuzzleCamera, screenX: double, screenY: double, zoom: double): void {
  worldX := screenToWorldX(camera, screenX)
  worldY := screenToWorldY(camera, screenY)
  camera.zoom = clampDouble(zoom, camera.minZoom, camera.maxZoom)
  camera.x = worldX - screenX / camera.zoom
  camera.y = worldY - screenY / camera.zoom
}

function applyZoomAt(camera: PuzzleCamera, screenX: double, screenY: double, factor: double): void {
  setZoomAt(camera, screenX, screenY, camera.zoom * clampDouble(factor, 0.75, 1.25))
}

function zoomFactorForWheelDelta(delta: double): double {
  return 1.0 + delta * ZOOM_DELTA_SCALE
}

function isPieceDragButton(button: MouseButton): bool {
  return button == MouseButton.Left || button == MouseButton.Other
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

function ioErrorMessage(operation: string, path: string, error: IoError): string {
  return "${operation} failed for ${path}: ${error}"
}

function puzzleStatePath(): string {
  directory := dataDirectory() else error {
    panic("Failed to resolve puzzle state data directory: ${error}")
  }
  return join([directory, PUZZLE_STATE_FILE])
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

function addGroupToBatch(batch: SimpleModelBatch, pieces: Piece[], group: int): void {
  for id of 0..<COLUMNS * ROWS {
    if pieces[id].group == group {
      addPieceToBatch(batch, pieces[id])
    }
  }
}

function pumpMainEventLoop(): void {
  let remaining = EVENT_DRAIN_PUMP_LIMIT
  let dispatched = 1
  while remaining > 0 && dispatched > 0 {
    dispatched = drainMainEventLoop()
    remaining = remaining - 1
  }
}

class JigsawRuntime {
  connection: JigsawClientConnection
  session: JigsawSession | null = null

  currentState(pieces: Piece[], drawOrder: int[], camera: PuzzleCamera): PuzzleState {
    localSession := this.session else {
      return createPuzzleState(pieces, drawOrder, camera)
    }
    return localSession.currentState()
  }
}

function parseJigsawServerAddress(args: string[]): Result<string | null, string> {
  let address: string | null = null
  let index = 0
  while index < args.length {
    if args[index] == "--jigsaw-server" {
      if index + 1 >= args.length {
        return Failure("--jigsaw-server requires an address")
      }
      address = args[index + 1]
      index = index + 2
    } else {
      return Failure("Unknown option ${args[index]}")
    }
  }
  return Success(address)
}

function createJigsawRuntime(serverAddress: string | null, initialState: PuzzleState): Result<JigsawRuntime, string> {
  address := serverAddress else {
    session := createJigsawSession(initialState)
    return Success(JigsawRuntime {
      connection: session.connectClient(),
      session,
    })
  }

  connection := connectJigsawServer(address) else error {
    return Failure("Could not connect to jigsaw server: ${error}")
  }
  return Success(JigsawRuntime {
    connection,
  })
}

function main(args: string[]): int {

  // serverAddress := parseJigsawServerAddress(args) else error {
  //   println(error)
  //   println("Usage: DoofJigsaw [--jigsaw-server http://host:port]")
  //   return 1
  // }

  serverAddress := "ws://192.168.1.120:8765/jigsaw"

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

  runtime := createJigsawRuntime(serverAddress, createPuzzleState(pieces, drawOrder, camera)) else error {
    println(error)
    return 1
  }
  connection := runtime.connection
  let mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
  let dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)

  let draggedPiece = -1
  let draggedGroup = -1
  let dragOffsetX = 0.0
  let dragOffsetY = 0.0
  connection.events.onMessage() {
    serverEvent: JigsawServerEvent := it
    if serverEvent.kind == JigsawServerEventKind.BoardSnapshot {
      if serverEvent.state != null {
        pieces = serverEvent.state!.pieces
        drawOrder = serverEvent.state!.drawOrder
        camera = serverEvent.state!.camera
      }
    }
    if serverEvent.kind == JigsawServerEventKind.GroupMoved {
      for pieceId of serverEvent.pieceIds {
        pieces[pieceId].group = serverEvent.groupId
      }
      setGroupCanonicalPosition(pieces, serverEvent.groupId, serverEvent.x, serverEvent.y)
      if serverEvent.drawOrder.length > 0 {
        drawOrder = serverEvent.drawOrder
      } else {
        drawOrder = bringGroupToFront(pieces, drawOrder, serverEvent.groupId)
      }
    }
    if serverEvent.kind == JigsawServerEventKind.GroupJoined {
      for pieceId of serverEvent.pieceIds {
        pieces[pieceId].group = serverEvent.groupId
      }
      if serverEvent.position == null {
        println("Ignoring jigsaw join without position")
      } else {
        setGroupCanonicalPosition(pieces, serverEvent.groupId, serverEvent.position!.x, serverEvent.position!.y)
        if serverEvent.drawOrder.length > 0 {
          drawOrder = serverEvent.drawOrder
        } else {
          drawOrder = bringGroupToFront(pieces, drawOrder, serverEvent.groupId)
        }
        if draggedPiece >= 0 && serverEvent.pieceIds.contains(draggedPiece) {
          draggedGroup = serverEvent.groupId
        }
      }
    }
    if serverEvent.kind == JigsawServerEventKind.MoveCancelled {
      for position of serverEvent.cancelledGroups {
        setGroupCanonicalPosition(pieces, position.groupId, position.x, position.y)
      }
      if serverEvent.drawOrder.length > 0 {
        drawOrder = serverEvent.drawOrder
      }
      if draggedPiece >= 0 {
        draggedPiece = -1
        draggedGroup = -1
      }
    }

    mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, if draggedGroup >= 0 then draggedGroup else -1)
    dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
    if draggedGroup >= 0 {
      addGroupToBatch(dragBatch, pieces, draggedGroup)
    }
    if serverEvent.kind == JigsawServerEventKind.GroupJoined ||
      serverEvent.kind == JigsawServerEventKind.MoveCancelled {
      canonical := runtime.currentState(pieces, drawOrder, camera)
      savePuzzleStateSafely(statePath, canonical.pieces, canonical.drawOrder, camera)
    }
    app.requestRender()
  }
  connection.events.onClosed((): void => {
    println("Jigsaw server connection closed")
  })
  pumpMainEventLoop()

  app.onEvent() {
    if event.kind() == GameEventKind.CloseRequested {
      if draggedPiece >= 0 {
        drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
        mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
        dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        draggedPiece = -1
        draggedGroup = -1
      }
      pumpMainEventLoop()
      canonical := runtime.currentState(pieces, drawOrder, camera)
      savePuzzleStateSafely(statePath, canonical.pieces, canonical.drawOrder, camera)
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
      pumpMainEventLoop()
      canonical := runtime.currentState(pieces, drawOrder, camera)
      savePuzzleStateSafely(statePath, canonical.pieces, canonical.drawOrder, camera)
      app.stop()
    }

    pieceDragButton := isPieceDragButton(event.mouseButton())
    if event.kind() == GameEventKind.MouseDown && pieceDragButton {
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
      position := groupPosition(pieces, draggedGroup)
      sendMoveGroup(connection, draggedGroup, position.x, position.y) else error {
        println("Failed to queue jigsaw move: ${error}")
      }
      pumpMainEventLoop()
      dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
      addGroupToBatch(dragBatch, pieces, draggedGroup)
      app.requestRender()
    }

    touchPanActive := app.input.isMouseButtonDown(MouseButton.Other)
    if event.kind() == GameEventKind.MouseMove && draggedPiece < 0 && touchPanActive {
      camera.x = camera.x - event.deltaX() / camera.zoom
      camera.y = camera.y - event.deltaY() / camera.zoom
      canonical := runtime.currentState(pieces, drawOrder, camera)
      savePuzzleStateSafely(statePath, canonical.pieces, canonical.drawOrder, camera)
      app.requestRender()
    }

    if event.kind() == GameEventKind.MouseUp && pieceDragButton && draggedPiece >= 0 {
      joinedGroups := joinNearbyPieces(pieces, layout, draggedGroup)
      position := groupPosition(pieces, draggedGroup)
      if joinedGroups.length > 1 {
        sendJoinGroups(connection, joinedGroups, position.x, position.y) else error {
          println("Failed to queue jigsaw join: ${error}")
        }
      } else {
        sendMoveGroup(connection, draggedGroup, position.x, position.y) else error {
          println("Failed to queue jigsaw move: ${error}")
        }
      }
      pumpMainEventLoop()
      drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
      mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
      dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
      draggedPiece = -1
      draggedGroup = -1
      pumpMainEventLoop()
      canonical := runtime.currentState(pieces, drawOrder, camera)
      savePuzzleStateSafely(statePath, canonical.pieces, canonical.drawOrder, camera)
      app.requestRender()
    }

    if event.kind() == GameEventKind.MouseUp && !pieceDragButton && draggedPiece >= 0 {
      drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
      mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
      dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
      draggedPiece = -1
      draggedGroup = -1
      canonical := runtime.currentState(pieces, drawOrder, camera)
      savePuzzleStateSafely(statePath, canonical.pieces, canonical.drawOrder, camera)
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
      applyZoomAt(camera, event.x(), event.y(), zoomFactorForWheelDelta(event.wheelDeltaY()))
      canonical := runtime.currentState(pieces, drawOrder, camera)
      savePuzzleStateSafely(statePath, canonical.pieces, canonical.drawOrder, camera)
      app.requestRender()
    }

    if event.kind() == GameEventKind.DoubleTap {
      if draggedPiece >= 0 {
        drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
        mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
        dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        draggedPiece = -1
        draggedGroup = -1
      }
      targetZoom := if abs(camera.zoom - camera.maxZoom) < 0.001 then camera.minZoom else camera.maxZoom
      setZoomAt(camera, event.x(), event.y(), targetZoom)
      canonical := runtime.currentState(pieces, drawOrder, camera)
      savePuzzleStateSafely(statePath, canonical.pieces, canonical.drawOrder, camera)
      app.requestRender()
    }
  }

  app.onRender() {
    renderer.pass(RenderPassDescriptor {
        clear: Clear.colorDepth(Color(0.04, 0.04, 0.045), 1.0),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
        camera: Camera.screen().withTransform(cameraTransform(camera)),
    }) {
      drawSimpleModelBatch(pass, mainBatch)
      drawSimpleModelBatch(pass, dragBatch)
    }
  }

  app.run() else error {
    println(error)
    return 1
  }
  return 0
}
