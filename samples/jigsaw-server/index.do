import { ChannelSender, createChannel } from "std/event"
import {
  Request,
  Response,
  Server,
  ServerOptions,
} from "std/http-server"
import {
  WebSocketBinary,
  WebSocketClose,
  WebSocketConnection,
  WebSocketError,
  WebSocketOpen,
  WebSocketOptions,
  WebSocketSendText,
  WebSocketText,
  WebSocketWritable,
  createWebSocketConnection,
} from "std/http-server/websocket"
import { exists, readText, writeText, IoError } from "std/fs"
import { formatJsonValue, parseJsonValue } from "std/json"
import { dataDirectory, join } from "std/path"

import {
  JigsawClientConnection,
  JigsawServerEvent,
  JigsawSession,
  JigsawSessionConfig,
  PuzzleState,
  createCameraForSize,
  createDrawOrder,
  createJigsawSession,
  createJigsawSessionWithStateChanged,
  createLayoutForSize,
  createPieces,
  createPuzzleState,
  decodeJigsawCommandFrame,
  encodeJigsawErrorFrame,
  encodeJigsawEventFrame,
  validatePuzzleState,
} from "../jigsaw"

export class JigsawHttpServerOptions {
  host: string = "127.0.0.1"
  port: int = 8765
  socketPath: string = "/jigsaw"
  statePath: string | null = null
  requestCapacity: int = 256
  eventCapacity: int = 1024
  commandCapacity: int = 1024
}

export class JigsawHttpServer {
  readonly host: string
  readonly port: int
  readonly socketPath: string
  session: JigsawSession
  private readonly server: Server
  private readonly requests: ChannelSender<Request>

  close(): void {
    this.requests.close()
    ignored := this.server.close()
  }
}

export function createDefaultJigsawServerState(): PuzzleState {
  layout := createLayoutForSize(1440.0, 1000.0)
  camera := createCameraForSize(1440.0, 1000.0, layout)
  pieces := createPieces(layout)
  drawOrder := createDrawOrder()
  return createPuzzleState(pieces, drawOrder, camera)
}

export function defaultJigsawServerStatePath(): Result<string, string> {
  directory := dataDirectory("dev.doof.jigsaw-server") else error {
    return Failure("Could not resolve jigsaw server data directory: ${error}")
  }
  return Success(join([directory, "puzzle-state.json"]))
}

export function loadJigsawServerState(path: string): Result<PuzzleState, string> {
  text := readText(path) else error {
    return Failure(ioErrorMessage("read", path, error))
  }

  try json := parseJsonValue(text)
  try state := PuzzleState.fromJsonValue(json)
  try validatePuzzleState(state)
  return Success(state)
}

export function saveJigsawServerState(path: string, state: PuzzleState): Result<void, string> {
  try validatePuzzleState(state)
  writeText(path, formatJsonValue(state.toJsonObject())) else error {
    return Failure(ioErrorMessage("write", path, error))
  }
  return Success()
}

export function startJigsawHttpServer(
  initialState: PuzzleState,
  options: JigsawHttpServerOptions = JigsawHttpServerOptions {},
): Result<JigsawHttpServer, string> {
  if options.requestCapacity <= 0 {
    panic("Jigsaw HTTP server request capacity must be positive")
  }

  state := loadInitialJigsawServerState(initialState, options.statePath) else error {
    return Failure(error)
  }
  sessionConfig := JigsawSessionConfig {
    commandCapacity: options.commandCapacity,
    eventCapacity: options.eventCapacity,
  }
  session := createJigsawHttpSession(state, options.statePath, sessionConfig)
  (requests, requestReceiver) := createChannel<Request>{
    capacity: options.requestCapacity,
    keepsAlive: true,
  }

  requestReceiver.onMessage((request: Request): void => handleJigsawHttpRequest(session, options, request))

  server := Server.listen{
    options: ServerOptions {
      host: options.host,
      port: options.port,
    },
    requests,
  } else error {
    requests.close()
    return Failure(error.message)
  }

  return Success(JigsawHttpServer {
    host: server.host,
    port: server.port,
    socketPath: options.socketPath,
    session,
    server,
    requests,
  })
}

function ioErrorMessage(operation: string, path: string, error: IoError): string {
  return "${operation} failed for ${path}: ${error}"
}

function loadInitialJigsawServerState(fallback: PuzzleState, statePath: string | null): Result<PuzzleState, string> {
  if statePath != null && exists(statePath!) {
    return loadJigsawServerState(statePath!)
  }
  return Success(fallback)
}

function createJigsawHttpSession(
  state: PuzzleState,
  statePath: string | null,
  config: JigsawSessionConfig,
): JigsawSession {
  if statePath != null {
    return createJigsawSessionWithStateChanged(state, (state: PuzzleState): void => {
      saveJigsawServerState(statePath!, state) else error {
        println("Failed to save jigsaw server state: ${error}")
      }
    }, config)
  }
  return createJigsawSession(state, config)
}

export function forwardJigsawCommandForClient(client: JigsawClientConnection, text: string): Result<void, string> {
  try command := decodeJigsawCommandFrame(text)
  command.clientId = client.clientId
  sent := client.commands.send(command)
  return case sent {
    _: Success -> Success(),
    f: Failure -> Failure("Could not queue jigsaw command: ${f.error}"),
  }
}

function handleJigsawHttpRequest(
  session: JigsawSession,
  options: JigsawHttpServerOptions,
  request: Request,
): void {
  if request.path != options.socketPath {
    ignored := request.respond(Response.text(404, "not found\n"))
    return
  }

  if request.method != "GET" || !request.isWebSocketUpgrade() {
    ignored := request.respond(Response.text(400, "expected websocket upgrade\n"))
    return
  }

  socket := createWebSocketConnection(WebSocketOptions {
    eventCapacity: options.eventCapacity,
    commandCapacity: options.commandCapacity,
  })
  client := session.connectClient()

  client.events.onMessage((event: JigsawServerEvent): void => {
    ignored := socket.commands.send(WebSocketSendText {
      text: encodeJigsawEventFrame(event),
    })
  })
  client.events.onClosed((): void => socket.close())
  socket.events.onMessage((
    event: WebSocketOpen | WebSocketText | WebSocketBinary | WebSocketWritable | WebSocketClose | WebSocketError,
  ): void => handleJigsawSocketEvent(client, socket, event))
  socket.events.onClosed((): void => client.events.close())

  request.upgradeToWebSocket(socket)
}

function handleJigsawSocketEvent(
  client: JigsawClientConnection,
  socket: WebSocketConnection,
  event: WebSocketOpen | WebSocketText | WebSocketBinary | WebSocketWritable | WebSocketClose | WebSocketError,
): void {
  textEvent := event as WebSocketText
  case textEvent {
    textSuccess: Success -> {
      forwarded := forwardJigsawCommandForClient(client, textSuccess.value.text)
      case forwarded {
        _: Success -> {}
        commandFailure: Failure -> {
          ignored := socket.commands.send(WebSocketSendText {
            text: encodeJigsawErrorFrame(commandFailure.error),
          })
          socket.close()
        }
      }
      return
    }
    _: Failure -> {}
  }

  closeEvent := event as WebSocketClose
  case closeEvent {
    _: Success -> {
      client.events.close()
      return
    }
    _: Failure -> {}
  }

  errorEvent := event as WebSocketError
  case errorEvent {
    _: Success -> {
      client.events.close()
      return
    }
    _: Failure -> {}
  }
}
