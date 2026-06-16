import {
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  GameEventKind,
  Key,
  MouseButton,
  RenderPassDescriptor,
  SimpleModelBatch,
  drawSimpleModelBatch,
  initGameApp,
  loadBitmapFont,
} from "std/game"
import { Timer, setInterval } from "std/event"
import { abs } from "std/math"
import { join, resourcesDirectory } from "std/path"
import { Duration } from "std/time"

import {
  COLUMNS,
  ROWS,
  bringGroupToFront,
  createDrawOrder,
  createPieces,
  createPuzzleState,
  groupPosition,
  hitTestTopmost,
  joinNearbyPieces,
  removeGroupFromDrawOrder,
  setGroupCanonicalPosition,
  setGroupPositionFromPiece,
} from "./jigsaw_model"
import {
  JigsawClientConnection,
  JigsawServerEvent,
  JigsawServerEventKind,
  sendJoinGroups,
  sendMoveGroup,
} from "./session"
import {
  JigsawRuntime,
  ServerConnectionState,
  applyZoomAt,
  createCamera,
  createJigsawRuntime,
  createLayout,
  emptyPuzzleStateForCamera,
  parseJigsawServerAddress,
  pumpMainEventLoop,
  screenToWorldX,
  screenToWorldY,
  setZoomAt,
  zoomFactorForMagnificationDelta,
  zoomFactorForScrollDelta,
} from "./client_runtime"
import { createJigsawConnectionOverlay } from "./connection_overlay"
import { connectJigsawServer } from "./protocol"
import {
  loadSavedPuzzleStateForLocalMode,
  puzzleStatePath,
  savePuzzleStateForRuntime,
} from "./puzzle_storage"
import {
  addGroupToBatch,
  cameraTransform,
  createBatch,
  createDragBatch,
  createPieceMesh,
} from "./render_helpers"

import function buildJigsawAtlas(
  photoPath: string,
  maskAtlasPath: string,
  outputPath: string,
  columns: int,
  rows: int,
): Result<void, string> from "native_jigsaw.hpp" as doof_game_jigsaw::buildJigsawAtlas

const RECONNECT_INTERVAL_MILLIS = 1000L
readonly SOURCE_PHOTO_PATH = "images/IMG_0459.jpeg"
readonly MASK_ATLAS_PATH = "images/jigjig.png"
readonly GENERATED_ATLAS_PATH = "images/generated_jigsaw_atlas.png"
const DRAG_EDGE_AUTO_PAN_INTERVAL_MILLIS = 16L
const DRAG_EDGE_AUTO_PAN_MARGIN = 72.0
const DRAG_EDGE_AUTO_PAN_MAX_STEP = 18.0

function isPieceDragButton(button: MouseButton): bool {
  return button == MouseButton.Left || button == MouseButton.Other
}

function isBoardPanButton(button: MouseButton): bool {
  return button == MouseButton.Left || button == MouseButton.Other
}

function dragEdgeAutoPanAxis(pointer: double, size: double): double {
  margin := if size * 0.35 < DRAG_EDGE_AUTO_PAN_MARGIN then size * 0.35 else DRAG_EDGE_AUTO_PAN_MARGIN
  if margin <= 0.0 {
    return 0.0
  }
  if pointer < margin {
    distance := margin - pointer
    t := if distance > margin then 1.0 else distance / margin
    return -DRAG_EDGE_AUTO_PAN_MAX_STEP * t * t
  }
  if pointer > size - margin {
    distance := pointer - (size - margin)
    t := if distance > margin then 1.0 else distance / margin
    return DRAG_EDGE_AUTO_PAN_MAX_STEP * t * t
  }
  return 0.0
}

function main(args: string[]): int {

  // serverAddress := parseJigsawServerAddress(args) else error {
  //   println(error)
  //   println("Usage: DoofJigsaw [--jigsaw-server http://host:port]")
  //   return 1
  // }

  serverAddress: string | null := "ws://192.168.1.120:8765/jigsaw"

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
  font := loadBitmapFont(join([resources, "fonts/DejaVuSans.fnt"])) else error {
    println(error)
    return 1
  }
  fontTexture := app.loadTexture(join([resources, "fonts/DejaVuSans_0.png"])) else error {
    println(error)
    return 1
  }

  layout := createLayout(app.surface)
  let camera = createCamera(app.surface, layout)
  mesh := createPieceMesh(app.surface, layout)
  let pieces = createPieces(layout)
  let drawOrder = createDrawOrder()
  statePath := puzzleStatePath()

  fallbackState := if serverAddress == null then
    createPuzzleState(pieces, drawOrder, camera)
  else
    emptyPuzzleStateForCamera(camera)
  initialState := loadSavedPuzzleStateForLocalMode(serverAddress, statePath, fallbackState)
  pieces = initialState.pieces
  drawOrder = initialState.drawOrder
  camera = initialState.camera

  runtime := createJigsawRuntime(serverAddress, createPuzzleState(pieces, drawOrder, camera)) else error {
    println(error)
    return 1
  }
  let mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
  let dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
  overlay := createJigsawConnectionOverlay(app.surface, font, fontTexture)
  overlay.update(runtime)

  let draggedPiece = -1
  let draggedGroup = -1
  let dragOffsetX = 0.0
  let dragOffsetY = 0.0
  let lastDragScreenX = 0.0
  let lastDragScreenY = 0.0
  let boardPanActive = false
  let reconnectTimer: Timer | null = null

  moveDraggedGroupToPointer := (): void => {
    if draggedPiece < 0 {
      return
    }
    worldX := screenToWorldX(camera, lastDragScreenX)
    worldY := screenToWorldY(camera, lastDragScreenY)
    setGroupPositionFromPiece(pieces, draggedGroup, draggedPiece, worldX - dragOffsetX, worldY - dragOffsetY)
    position := groupPosition(pieces, draggedGroup)
    activeConnection := runtime.connection
    if activeConnection != null {
      sendMoveGroup(activeConnection!, draggedGroup, position.x, position.y) else error {
        println("Failed to queue jigsaw move: ${error}")
      }
    }
    pumpMainEventLoop()
    dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
    addGroupToBatch(dragBatch, pieces, draggedGroup)
  }

  dragAutoPanTimer := setInterval{
    interval: Duration.ofMillis(DRAG_EDGE_AUTO_PAN_INTERVAL_MILLIS),
    keepsAlive: false,
    handler: (): void => {
      if draggedPiece < 0 || !runtime.isInteractive() {
        return
      }
      panX := dragEdgeAutoPanAxis(lastDragScreenX, app.surface.width())
      panY := dragEdgeAutoPanAxis(lastDragScreenY, app.surface.height())
      if panX == 0.0 && panY == 0.0 {
        return
      }
      camera.x = camera.x + panX / camera.zoom
      camera.y = camera.y + panY / camera.zoom
      moveDraggedGroupToPointer()
      app.requestRender()
    },
  }

  bindConnection := (boundConnection: JigsawClientConnection, generation: int): void => {
    boundConnection.events.onMessage((serverEvent: JigsawServerEvent): void => {
      if generation != runtime.connectionGeneration {
        return
      }
      if serverEvent.kind == JigsawServerEventKind.BoardSnapshot {
        runtime.state = ServerConnectionState.Connected
        runtime.lastError = null
        if serverEvent.state != null {
          pieces = serverEvent.state!.pieces
          drawOrder = serverEvent.state!.drawOrder
          if !runtime.isServerMode() {
            camera = serverEvent.state!.camera
          }
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
          boardPanActive = false
          app.cancelPanGesture()
        }
      }

      mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, if draggedGroup >= 0 then draggedGroup else -1)
      dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
      if draggedGroup >= 0 {
        addGroupToBatch(dragBatch, pieces, draggedGroup)
      }
      if serverEvent.kind == JigsawServerEventKind.GroupJoined ||
        serverEvent.kind == JigsawServerEventKind.MoveCancelled {
        savePuzzleStateForRuntime(runtime, statePath, pieces, drawOrder, camera)
      }
      app.requestRender()
    })
    boundConnection.events.onClosed((): void => {
      if generation != runtime.connectionGeneration {
        return
      }
      if runtime.isServerMode() {
        println("Jigsaw server connection closed; reconnecting")
        wasConnected := runtime.state == ServerConnectionState.Connected
        runtime.connection = null
        runtime.state = ServerConnectionState.Disconnected
        runtime.lastError = "Connection closed"
        draggedPiece = -1
        draggedGroup = -1
        boardPanActive = false
        if wasConnected {
          emptyState := emptyPuzzleStateForCamera(camera)
          pieces = emptyState.pieces
          drawOrder = emptyState.drawOrder
          mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
          dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        }
        overlay.update(runtime)
        app.requestRender()
      } else {
        println("Jigsaw local session connection closed")
      }
    })
  }

  attemptServerConnect := (): void => {
    address := runtime.serverAddress else {
      return
    }
    if runtime.state == ServerConnectionState.Connected || runtime.state == ServerConnectionState.Connecting {
      return
    }
    runtime.connectionGeneration = runtime.connectionGeneration + 1
    runtime.state = ServerConnectionState.Connecting
    runtime.lastError = null
    draggedPiece = -1
    draggedGroup = -1
    boardPanActive = false
    overlay.update(runtime)
    app.requestRender()

    connection := connectJigsawServer(address) else error {
      runtime.state = ServerConnectionState.Disconnected
      runtime.lastError = error
      overlay.update(runtime)
      app.requestRender()
      return
    }
    runtime.connection = connection
    bindConnection(connection, runtime.connectionGeneration)
    pumpMainEventLoop()
  }

  existingConnection := runtime.connection
  if existingConnection != null {
    bindConnection(existingConnection!, runtime.connectionGeneration)
  }
  if runtime.isServerMode() {
    attemptServerConnect()
    reconnectTimer = setInterval{
      interval: Duration.ofMillis(RECONNECT_INTERVAL_MILLIS),
      handler: (): void => {
        attemptServerConnect()
        pumpMainEventLoop()
      },
    }
  }
  pumpMainEventLoop()

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      boardPanActive = false
      app.cancelPanGesture()
      if draggedPiece >= 0 {
        drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
        mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
        dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        draggedPiece = -1
        draggedGroup = -1
      }
      pumpMainEventLoop()
      savePuzzleStateForRuntime(runtime, statePath, pieces, drawOrder, camera)
      app.stop()
    }

    if event.kind() == GameEventKind.KeyDown && event.key() == Key.Escape {
      boardPanActive = false
      app.cancelPanGesture()
      if draggedPiece >= 0 {
        drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
        mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
        dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        draggedPiece = -1
        draggedGroup = -1
      }
      pumpMainEventLoop()
      savePuzzleStateForRuntime(runtime, statePath, pieces, drawOrder, camera)
      app.stop()
    }

    if event.kind() == GameEventKind.Resized {
      overlay.configure(app.surface)
      app.requestRender()
    }

    if !runtime.isInteractive() {
      boardPanActive = false
      app.cancelPanGesture()
      app.requestRender()
      return
    }

    pieceDragButton := isPieceDragButton(event.mouseButton())
    boardPanButton := isBoardPanButton(event.mouseButton())
    if event.kind() == GameEventKind.MouseDown && pieceDragButton {
      worldX := screenToWorldX(camera, event.x())
      worldY := screenToWorldY(camera, event.y())
      hit := hitTestTopmost(pieces, drawOrder, layout, worldX, worldY)
      if hit >= 0 {
        boardPanActive = false
        app.cancelPanGesture()
        draggedPiece = hit
        draggedGroup = pieces[hit].group
        lastDragScreenX = event.x()
        lastDragScreenY = event.y()
        piece := pieces[hit]
        dragOffsetX = worldX - piece.x
        dragOffsetY = worldY - piece.y
        drawOrder = removeGroupFromDrawOrder(pieces, drawOrder, draggedGroup)
        mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, draggedGroup)
        dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        addGroupToBatch(dragBatch, pieces, draggedGroup)
        app.requestRender()
      } else if boardPanButton {
        boardPanActive = true
        app.beginPanGesture(event.x(), event.y())
      }
    }

    if event.kind() == GameEventKind.MouseMove && draggedPiece >= 0 {
      lastDragScreenX = event.x()
      lastDragScreenY = event.y()
      moveDraggedGroupToPointer()
      app.requestRender()
    }

    if event.kind() == GameEventKind.MouseMove && draggedPiece < 0 && boardPanActive {
      app.updatePanGesture(event.x(), event.y())
    }

    if event.kind() == GameEventKind.MouseUp && boardPanButton && boardPanActive {
      app.endPanGesture()
      boardPanActive = false
    }

    if event.kind() == GameEventKind.MouseUp && pieceDragButton && draggedPiece >= 0 {
      joinedGroups := joinNearbyPieces(pieces, layout, draggedGroup)
      position := groupPosition(pieces, draggedGroup)
      activeConnection := runtime.connection
      if activeConnection != null {
        if joinedGroups.length > 1 {
          sendJoinGroups(activeConnection!, joinedGroups, position.x, position.y) else error {
            println("Failed to queue jigsaw join: ${error}")
          }
        } else {
          sendMoveGroup(activeConnection!, draggedGroup, position.x, position.y) else error {
            println("Failed to queue jigsaw move: ${error}")
          }
        }
      }
      pumpMainEventLoop()
      drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
      mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
      dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
      draggedPiece = -1
      draggedGroup = -1
      boardPanActive = false
      app.cancelPanGesture()
      pumpMainEventLoop()
      savePuzzleStateForRuntime(runtime, statePath, pieces, drawOrder, camera)
      app.requestRender()
    }

    if event.kind() == GameEventKind.MouseUp && !pieceDragButton && draggedPiece >= 0 {
      drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
      mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
      dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
      draggedPiece = -1
      draggedGroup = -1
      boardPanActive = false
      app.cancelPanGesture()
      savePuzzleStateForRuntime(runtime, statePath, pieces, drawOrder, camera)
      app.requestRender()
    }

    if event.kind() == GameEventKind.Pan || event.kind() == GameEventKind.Scroll || event.kind() == GameEventKind.Magnify {
      if draggedPiece >= 0 {
        drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
        mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
        dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
        draggedPiece = -1
        draggedGroup = -1
      }
      if event.kind() != GameEventKind.Pan {
        boardPanActive = false
        app.cancelPanGesture()
      }
      if event.kind() == GameEventKind.Magnify {
        camera.x = camera.x - event.panDeltaX() / camera.zoom
        camera.y = camera.y - event.panDeltaY() / camera.zoom
        applyZoomAt(camera, event.x(), event.y(), zoomFactorForMagnificationDelta(event.magnificationDelta()))
      } else if event.kind() == GameEventKind.Pan {
        camera.x = camera.x - event.panDeltaX() / camera.zoom
        camera.y = camera.y - event.panDeltaY() / camera.zoom
      } else {
        applyZoomAt(camera, event.x(), event.y(), zoomFactorForScrollDelta(event.scrollDeltaY()))
      }
      savePuzzleStateForRuntime(runtime, statePath, pieces, drawOrder, camera)
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
      boardPanActive = false
      app.cancelPanGesture()
      targetZoom := if abs(camera.zoom - camera.maxZoom) < 0.001 then camera.minZoom else camera.maxZoom
      setZoomAt(camera, event.x(), event.y(), targetZoom)
      savePuzzleStateForRuntime(runtime, statePath, pieces, drawOrder, camera)
      app.requestRender()
    }
  })

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
    if runtime.isServerMode() && runtime.state != ServerConnectionState.Connected {
      renderer.pass(RenderPassDescriptor {
          camera: Camera.screen(),
          depth: Depth.disabled(),
          blend: Blend.alpha(),
      }) {
        overlay.draw(pass)
      }
    }
  }

  app.run() else error {
    println(error)
    return 1
  }
  return 0
}
