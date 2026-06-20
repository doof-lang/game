import {
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  GameEventKind,
  Key,
  synthSound,
  RenderPassDescriptor,
  SimpleModelBatch,
  drawSimpleModelBatch,
  initGameApp,
} from "std/game"
import { Timer, setInterval } from "std/event"
import { abs } from "std/math"
import { cacheDirectory, join, resourcesDirectory } from "std/path"
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
import { jigsawAtlasCachePath, loadJigsawAtlasTexture } from "./jigsaw_atlas"

const RECONNECT_INTERVAL_MILLIS = 1000L
readonly SOURCE_PHOTO_PATH = "images/IMG_0459.jpeg"
readonly MASK_ATLAS_PATH = "images/jigjig.png"
const DRAG_EDGE_AUTO_PAN_INTERVAL_MILLIS = 16L
const DRAG_EDGE_AUTO_PAN_MARGIN = 72.0
const DRAG_EDGE_AUTO_PAN_MAX_STEP = 18.0

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

  app := initGameApp{ title: "Doof Game Jigsaw" }
  cacheRoot := case cacheDirectory() {
    success: Success -> success.value,
    failure: Failure -> {
      println("Could not resolve jigsaw cache directory: ${failure.error}")
      yield ""
    },
  }
  let atlasCachePath: string | null = null
  if cacheRoot.length > 0 {
    case jigsawAtlasCachePath(cacheRoot, sourcePhoto, maskAtlas, COLUMNS, ROWS) {
      success: Success -> {
        atlasCachePath = success.value
      }
      failure: Failure -> {
        println(failure.error)
      }
    }
  }
  loadedAtlasTexture := loadJigsawAtlasTexture(
    app,
    sourcePhoto,
    maskAtlas,
    atlasCachePath,
    COLUMNS,
    ROWS,
  ) else error {
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
  overlay := createJigsawConnectionOverlay(app)
  overlay.update(runtime)

  let draggedPiece = -1
  let draggedGroup = -1
  let dragOffsetX = 0.0
  let dragOffsetY = 0.0
  let lastDragScreenX = 0.0
  let lastDragScreenY = 0.0
  let boardPanActive = false
  let reconnectTimer: Timer | null = null

  click := try! synthSound({
    wave: .Noise,
    baseFrequency: 1220.0,
    frequencySlide: 0,
    vibratoDepth: 0.0,
    vibratoSpeed: 0.0,
    attackTime: 0.0,
    sustainTime: 0.008,
    sustainPunch: 0.42,
    decayTime: 0.015,
    lowPassCutoff: 0.72,
    highPassCutoff: 0.16,
    volume: 0.3,
  })

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

  dropDraggedGroup := (): void => {
    if draggedPiece < 0 {
      return
    }
    drawOrder = bringGroupToFront(pieces, drawOrder, draggedGroup)
    mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, -1)
    dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
    draggedPiece = -1
    draggedGroup = -1
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

  stopApp := (): void => {
    boardPanActive = false
    app.cancelPanGesture()
    dropDraggedGroup()
    pumpMainEventLoop()
    savePuzzleStateForRuntime(runtime, statePath, pieces, drawOrder, camera)
    app.stop()
  }

  pointer := app.screenPointer()
  gestures := app.gestures()

  pointer.onPressed((point): void => {
    if !runtime.isInteractive() {
      boardPanActive = false
      app.cancelPanGesture()
      app.requestRender()
      return
    }

    screenX := point.x
    screenY := point.y
    worldX := screenToWorldX(camera, screenX)
    worldY := screenToWorldY(camera, screenY)
    hit := hitTestTopmost(pieces, drawOrder, layout, worldX, worldY)
    if hit >= 0 {
      boardPanActive = false
      app.cancelPanGesture()
      draggedPiece = hit
      draggedGroup = pieces[hit].group
      lastDragScreenX = screenX
      lastDragScreenY = screenY
      piece := pieces[hit]
      dragOffsetX = worldX - piece.x
      dragOffsetY = worldY - piece.y
      drawOrder = removeGroupFromDrawOrder(pieces, drawOrder, draggedGroup)
      mainBatch = createBatch(app.surface, mesh, loadedAtlasTexture, pieces, drawOrder, draggedGroup)
      dragBatch = createDragBatch(app.surface, mesh, loadedAtlasTexture)
      addGroupToBatch(dragBatch, pieces, draggedGroup)
      app.requestRender()
      return
    }

    boardPanActive = true
    app.beginPanGesture(screenX, screenY)
  })
  pointer.onReleased((point): void => {
    if boardPanActive {
      app.endPanGesture()
      boardPanActive = false
    }

    if draggedPiece >= 0 {
      joinedGroups := joinNearbyPieces(pieces, layout, draggedGroup)
      position := groupPosition(pieces, draggedGroup)
      activeConnection := runtime.connection
      if activeConnection != null {
        if joinedGroups.length > 1 {
          click.play({}) else {}
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
  })
  pointer.onMoved((point): void => {
    if !runtime.isInteractive() {
      boardPanActive = false
      app.cancelPanGesture()
      app.requestRender()
      return
    }

    if draggedPiece >= 0 {
      lastDragScreenX = point.x
      lastDragScreenY = point.y
      moveDraggedGroupToPointer()
      app.requestRender()
    }

    if draggedPiece < 0 && boardPanActive {
      app.updatePanGesture(point.x, point.y)
    }
  })

  gestures.onPan((gesture): void => {
    if !runtime.isInteractive() {
      boardPanActive = false
      app.cancelPanGesture()
      app.requestRender()
      return
    }

    dropDraggedGroup()
    camera.x = camera.x - gesture.deltaX / camera.zoom
    camera.y = camera.y - gesture.deltaY / camera.zoom
    savePuzzleStateForRuntime(runtime, statePath, pieces, drawOrder, camera)
    app.requestRender()
  })
  gestures.onScroll((gesture): void => {
    if !runtime.isInteractive() {
      boardPanActive = false
      app.cancelPanGesture()
      app.requestRender()
      return
    }

    dropDraggedGroup()
    boardPanActive = false
    app.cancelPanGesture()
    applyZoomAt(camera, gesture.point.x, gesture.point.y, zoomFactorForScrollDelta(gesture.deltaY))
    savePuzzleStateForRuntime(runtime, statePath, pieces, drawOrder, camera)
    app.requestRender()
  })
  gestures.onMagnify((gesture): void => {
    if !runtime.isInteractive() {
      boardPanActive = false
      app.cancelPanGesture()
      app.requestRender()
      return
    }

    dropDraggedGroup()
    boardPanActive = false
    app.cancelPanGesture()
    camera.x = camera.x - gesture.deltaX / camera.zoom
    camera.y = camera.y - gesture.deltaY / camera.zoom
    applyZoomAt(camera, gesture.point.x, gesture.point.y, zoomFactorForMagnificationDelta(gesture.magnificationDelta))
    savePuzzleStateForRuntime(runtime, statePath, pieces, drawOrder, camera)
    app.requestRender()
  })
  gestures.onDoubleTap((gesture): void => {
    if !runtime.isInteractive() {
      boardPanActive = false
      app.cancelPanGesture()
      app.requestRender()
      return
    }

    dropDraggedGroup()
    boardPanActive = false
    app.cancelPanGesture()
    targetZoom := if abs(camera.zoom - camera.maxZoom) < 0.001 then camera.minZoom else camera.maxZoom
    setZoomAt(camera, gesture.point.x, gesture.point.y, targetZoom)
    savePuzzleStateForRuntime(runtime, statePath, pieces, drawOrder, camera)
    app.requestRender()
  })
  app.key(Key.Escape).onPressed(stopApp)

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      stopApp.call()
    }

    if event.kind() == GameEventKind.Resized {
      overlay.configure(app.surface)
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
