import { GameSurface } from "std/game"
import { drainMainEventLoop } from "std/event"

import {
  Piece,
  PuzzleCamera,
  PuzzleLayout,
  PuzzleState,
  clampDouble,
  createCameraForSize,
  createDrawOrder,
  createLayoutForSize,
  createPieces,
  createPuzzleState,
} from "./jigsaw_model"
import {
  JigsawClientConnection,
  JigsawSession,
  createJigsawSession,
} from "./session"

const EVENT_DRAIN_PUMP_LIMIT = 16
const ZOOM_DELTA_SCALE = 0.002

export enum ServerConnectionState {
  Local,
  Connecting,
  Connected,
  Disconnected,
}

export class JigsawRuntime {
  connection: JigsawClientConnection | null = null
  session: JigsawSession | null = null
  serverAddress: string | null = null
  state: ServerConnectionState = ServerConnectionState.Local
  connectionGeneration: int = 0
  lastError: string | null = null

  currentState(pieces: Piece[], drawOrder: int[], camera: PuzzleCamera): PuzzleState {
    localSession := this.session else {
      return createPuzzleState(pieces, drawOrder, camera)
    }
    return localSession.currentState()
  }

  isServerMode(): bool {
    return this.serverAddress != null
  }

  isInteractive(): bool {
    return !this.isServerMode() || this.state == ServerConnectionState.Connected
  }
}

export function parseJigsawServerAddress(args: string[]): Result<string | null, string> {
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

export function createJigsawRuntime(serverAddress: string | null, initialState: PuzzleState): Result<JigsawRuntime, string> {
  address := serverAddress else {
    session := createJigsawSession(initialState)
    return Success(JigsawRuntime {
      connection: session.connectClient(),
      session,
      state: ServerConnectionState.Local,
    })
  }

  return Success(JigsawRuntime {
    serverAddress: address,
    state: ServerConnectionState.Disconnected,
  })
}

export function createLayout(surface: GameSurface): PuzzleLayout {
  return createLayoutForSize(surface.width(), surface.height())
}

export function createCamera(surface: GameSurface, layout: PuzzleLayout): PuzzleCamera {
  return createCameraForSize(surface.width(), surface.height(), layout)
}

export function initialPuzzleStateForSurface(surface: GameSurface): PuzzleState {
  layout := createLayout(surface)
  freshCamera := createCamera(surface, layout)
  return createPuzzleState(createPieces(layout), createDrawOrder(), freshCamera)
}

export function emptyPuzzleStateForCamera(camera: PuzzleCamera): PuzzleState {
  pieces: Piece[] := []
  drawOrder: int[] := []
  return createPuzzleState(pieces, drawOrder, camera)
}

export function screenToWorldX(camera: PuzzleCamera, x: double): double {
  return camera.x + x / camera.zoom
}

export function screenToWorldY(camera: PuzzleCamera, y: double): double {
  return camera.y + y / camera.zoom
}

export function setZoomAt(camera: PuzzleCamera, screenX: double, screenY: double, zoom: double): void {
  worldX := screenToWorldX(camera, screenX)
  worldY := screenToWorldY(camera, screenY)
  camera.zoom = clampDouble(zoom, camera.minZoom, camera.maxZoom)
  camera.x = worldX - screenX / camera.zoom
  camera.y = worldY - screenY / camera.zoom
}

export function applyZoomAt(camera: PuzzleCamera, screenX: double, screenY: double, factor: double): void {
  setZoomAt(camera, screenX, screenY, camera.zoom * clampDouble(factor, 0.75, 1.25))
}

export function zoomFactorForWheelDelta(delta: double): double {
  return 1.0 + delta * ZOOM_DELTA_SCALE
}

export function pumpMainEventLoop(): void {
  let remaining = EVENT_DRAIN_PUMP_LIMIT
  let dispatched = 1
  while remaining > 0 && dispatched > 0 {
    dispatched = drainMainEventLoop()
    remaining = remaining - 1
  }
}
