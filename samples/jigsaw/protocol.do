import { ChannelSender, createChannel, setInterval } from "std/event"
import {
  WebSocketClose,
  WebSocketBinary,
  WebSocketError,
  WebSocketConnection,
  WebSocketOpen,
  WebSocketOptions,
  WebSocketSendText,
  WebSocketText,
  WebSocketWritable,
  connectWebSocket,
} from "std/http/websocket"
import { formatJsonValue, parseJsonValue } from "std/json"
import { Duration } from "std/time"

import {
  GroupPosition,
  PuzzleState,
} from "./jigsaw_model"
import {
  JigsawClientCommand,
  JigsawClientConnection,
  JigsawServerEvent,
  JigsawServerEventKind,
  jigsawClientCommandKey,
  jigsawServerEventKey,
} from "./session"

export readonly JIGSAW_WEBSOCKET_PATH = "/jigsaw"
readonly JIGSAW_MOVE_FLUSH_INTERVAL_MILLIS = 16L

export function encodeJigsawCommandFrame(command: JigsawClientCommand): string {
  frame: JsonObject := {
    "type": "command",
    "command": command.toJsonObject(),
  }
  return formatJsonValue(frame)
}

export function decodeJigsawCommandFrame(text: string): Result<JigsawClientCommand, string> {
  try json := parseJsonValue(text)
  object := json as JsonObject else {
    return Failure("Expected jigsaw command frame object")
  }
  frameType := object.get("type") as string else {
    return Failure("Expected jigsaw command frame type")
  }
  if frameType != "command" {
    return Failure("Expected jigsaw command frame")
  }
  payload: JsonValue := object.get("command") else {
    return Failure("Expected jigsaw command payload")
  }
  try command := JigsawClientCommand.fromJsonValue(payload)
  return Success(command)
}

export function encodeJigsawEventFrame(event: JigsawServerEvent): string {
  frame: JsonObject := {
    "type": "event",
    "event": eventToJsonObject(event),
  }
  return formatJsonValue(frame)
}

export function decodeJigsawEventFrame(text: string): Result<JigsawServerEvent, string> {
  try json := parseJsonValue(text)
  object := json as JsonObject else {
    return Failure("Expected jigsaw event frame object")
  }
  frameType := object.get("type") as string else {
    return Failure("Expected jigsaw event frame type")
  }
  if frameType != "event" {
    return Failure("Expected jigsaw event frame")
  }
  payloadValue: JsonValue := object.get("event") else {
    return Failure("Expected jigsaw event payload")
  }
  try event := eventFromJsonValue(payloadValue)
  return Success(event)
}

export function encodeJigsawErrorFrame(message: string): string {
  frame: JsonObject := {
    "type": "error",
    "message": message,
  }
  return formatJsonValue(frame)
}

function eventKindName(kind: JigsawServerEventKind): string {
  return case kind {
    JigsawServerEventKind.BoardSnapshot -> "BoardSnapshot",
    JigsawServerEventKind.GroupMoved -> "GroupMoved",
    JigsawServerEventKind.GroupJoined -> "GroupJoined",
    JigsawServerEventKind.MoveCancelled -> "MoveCancelled",
  }
}

function parseEventKind(name: string): Result<JigsawServerEventKind, string> {
  return case name {
    "BoardSnapshot" -> Success(JigsawServerEventKind.BoardSnapshot),
    "GroupMoved" -> Success(JigsawServerEventKind.GroupMoved),
    "GroupJoined" -> Success(JigsawServerEventKind.GroupJoined),
    "MoveCancelled" -> Success(JigsawServerEventKind.MoveCancelled),
    _ -> Failure("Unknown jigsaw event kind ${name}"),
  }
}

function intArrayToJson(values: int[]): JsonValue[] {
  result: JsonValue[] := []
  for value of values {
    result.push(value)
  }
  return result
}

function groupPositionsToJson(values: GroupPosition[]): JsonValue[] {
  result: JsonValue[] := []
  for value of values {
    result.push(value.toJsonObject())
  }
  return result
}

function eventToJsonObject(event: JigsawServerEvent): JsonObject {
  payload: JsonObject := {}
  payload.set("kind", eventKindName(event.kind))
  payload.set("clientId", event.clientId)
  payload.set("groupId", event.groupId)
  payload.set("groupIds", intArrayToJson(event.groupIds))
  payload.set("pieceIds", intArrayToJson(event.pieceIds))
  payload.set("x", event.x)
  payload.set("y", event.y)
  if event.position == null {
    payload.set("position", null)
  } else {
    payload.set("position", event.position!.toJsonObject())
  }
  if event.state == null {
    payload.set("state", null)
  } else {
    payload.set("state", event.state!.toJsonObject())
  }
  payload.set("drawOrder", intArrayToJson(event.drawOrder))
  payload.set("cancelledGroups", groupPositionsToJson(event.cancelledGroups))
  return payload
}

function readStringField(object: JsonObject, name: string): Result<string, string> {
  value := object.get(name) as string else {
    return Failure("Expected string field ${name}")
  }
  return Success(value)
}

function readIntField(object: JsonObject, name: string, defaultValue: int): Result<int, string> {
  if !object.has(name) {
    return Success(defaultValue)
  }
  value := object.get(name) as int else {
    return Failure("Expected int field ${name}")
  }
  return Success(value)
}

function readDoubleField(object: JsonObject, name: string, defaultValue: double): Result<double, string> {
  if !object.has(name) {
    return Success(defaultValue)
  }
  value := object.get(name) else {
    return Failure("Expected double field ${name}")
  }
  doubleValue := value as double
  case doubleValue {
    s: Success -> return Success(s.value)
    _: Failure -> {}
  }
  intValue := value as int
  case intValue {
    s: Success -> return Success(double(s.value))
    _: Failure -> {}
  }
  return Failure("Expected double field ${name}")
}

function readIntArrayField(object: JsonObject, name: string): Result<int[], string> {
  if !object.has(name) {
    empty: int[] := []
    return Success(empty)
  }
  value := object.get(name) else {
    return Failure("Expected int array field ${name}")
  }
  raw := value as JsonValue[] else {
    return Failure("Expected int array field ${name}")
  }
  result: int[] := []
  for item of raw {
    number := item as int else {
      return Failure("Expected int item in ${name}")
    }
    result.push(number)
  }
  return Success(result)
}

function readGroupPositionsField(object: JsonObject, name: string): Result<GroupPosition[], string> {
  if !object.has(name) {
    empty: GroupPosition[] := []
    return Success(empty)
  }
  value := object.get(name) else {
    return Failure("Expected group position array field ${name}")
  }
  raw := value as JsonValue[] else {
    return Failure("Expected group position array field ${name}")
  }
  result: GroupPosition[] := []
  for item of raw {
    try position := GroupPosition.fromJsonValue(item)
    result.push(position)
  }
  return Success(result)
}

function readGroupPositionField(object: JsonObject, name: string): Result<GroupPosition | null, string> {
  if !object.has(name) {
    empty: GroupPosition | null := null
    return Success(empty)
  }
  value := object.get(name) else {
    return Failure("Expected group position field ${name}")
  }
  positionObject := value as JsonObject else {
    empty: GroupPosition | null := null
    return Success(empty)
  }
  try position := GroupPosition.fromJsonValue(positionObject)
  return Success(position)
}

function readStateField(object: JsonObject, name: string): Result<PuzzleState | null, string> {
  if !object.has(name) {
    empty: PuzzleState | null := null
    return Success(empty)
  }
  value := object.get(name) else {
    return Failure("Expected state field ${name}")
  }
  stateObject := value as JsonObject else {
    empty: PuzzleState | null := null
    return Success(empty)
  }
  try state := PuzzleState.fromJsonValue(stateObject)
  return Success(state)
}

function eventFromJsonValue(value: JsonValue): Result<JigsawServerEvent, string> {
  object := value as JsonObject else {
    return Failure("Expected jigsaw event object")
  }
  try kindName := readStringField(object, "kind")
  try kind := parseEventKind(kindName)
  try clientId := readIntField(object, "clientId", -1)
  try groupId := readIntField(object, "groupId", -1)
  try groupIds := readIntArrayField(object, "groupIds")
  try pieceIds := readIntArrayField(object, "pieceIds")
  try x := readDoubleField(object, "x", 0.0)
  try y := readDoubleField(object, "y", 0.0)
  try position := readGroupPositionField(object, "position")
  try state := readStateField(object, "state")
  try drawOrder := readIntArrayField(object, "drawOrder")
  try cancelledGroups := readGroupPositionsField(object, "cancelledGroups")
  return Success(JigsawServerEvent {
    kind,
    clientId,
    groupId,
    groupIds,
    pieceIds,
    x,
    y,
    position,
    state,
    drawOrder,
    cancelledGroups,
  })
}

export function normalizeJigsawServerUrl(address: string): string {
  let url = address.trim()
  if url.startsWith("http://") {
    url = "ws://" + url.slice(7)
  } else if url.startsWith("https://") {
    url = "wss://" + url.slice(8)
  }

  let schemeEnd = url.indexOf("://")
  if schemeEnd < 0 {
    url = "ws://" + url
    schemeEnd = 2
  }

  afterAuthority := url.slice(schemeEnd + 3)
  if !afterAuthority.contains("/") {
    url += JIGSAW_WEBSOCKET_PATH
  }

  return url
}

export function connectJigsawServer(address: string): Result<JigsawClientConnection, string> {
  options := WebSocketOptions {
    eventCapacity: 8,
    commandCapacity: 256,
  }
  socket := connectWebSocket(normalizeJigsawServerUrl(address), options) else error {
    return Failure("${error.kind}: ${error.message}")
  }

  (commands, commandEvents) := createChannel<JigsawClientCommand>{
    capacity: 256,
    keepsAlive: false,
  }
  (eventSender, events) := createChannel<JigsawServerEvent>{
    capacity: 256,
    keepsAlive: false,
  }

  connection := JigsawClientConnection {
    clientId: -1,
    commands,
    events,
  }

  let pendingCommand: JigsawClientCommand | null = null
  flushPendingCommand := (): void => {
    command := pendingCommand else {
      return
    }
    pendingCommand = null
    key := jigsawClientCommandKey(command) else {
      return
    }
    if !sendCommandFrame(socket, command, key) {
      eventSender.close()
    }
  }
  flushTimer := setInterval{
    interval: Duration.ofMillis(JIGSAW_MOVE_FLUSH_INTERVAL_MILLIS),
    keepsAlive: false,
    handler: flushPendingCommand,
  }

  commandEvents.onMessage((command: JigsawClientCommand): void => {
    if jigsawClientCommandKey(command) == null {
      flushPendingCommand.call()
      if !sendCommandFrame(socket, command, null) {
        eventSender.close()
      }
      return
    }
    pendingCommand = command
  })
  commandEvents.onClosed((): void => {
    flushPendingCommand.call()
    flushTimer.cancel()
    socket.close()
  })
  eventSender.onClosed((): void => {
    flushTimer.cancel()
    socket.close()
  })

  socket.events.onMessage((
    event: WebSocketOpen | WebSocketText | WebSocketBinary | WebSocketWritable | WebSocketClose | WebSocketError,
  ): void => handleRemoteSocketEvent(connection, eventSender, event))
  socket.events.onClosed((): void => {
    flushTimer.cancel()
    commands.close()
    eventSender.close()
  })

  return Success(connection)
}

function sendCommandFrame(
  socket: WebSocketConnection,
  command: JigsawClientCommand,
  key: string | null,
): bool {
  sent := if key == null then socket.commands.send(WebSocketSendText {
    text: encodeJigsawCommandFrame(command),
  }) else socket.commands.send(WebSocketSendText {
    text: encodeJigsawCommandFrame(command),
    coalesceKey: key,
  }, key!)
  return case sent {
    _: Success -> true,
    _: Failure -> false,
  }
}

function handleRemoteSocketEvent(
  connection: JigsawClientConnection,
  eventSender: ChannelSender<JigsawServerEvent>,
  event: WebSocketOpen | WebSocketText | WebSocketBinary | WebSocketWritable | WebSocketClose | WebSocketError,
): void {
  textEvent := event as WebSocketText
  case textEvent {
    textSuccess: Success -> {
      decoded := decodeJigsawEventFrame(textSuccess.value.text)
      case decoded {
        eventSuccess: Success -> {
          serverEvent := eventSuccess.value
          if serverEvent.kind == JigsawServerEventKind.BoardSnapshot {
            connection.clientId = serverEvent.clientId
          }
          ignored := eventSender.send(serverEvent, jigsawServerEventKey(serverEvent))
        }
        _: Failure -> {
          eventSender.close()
        }
      }
      return
    }
    _: Failure -> {}
  }

  closeEvent := event as WebSocketClose
  case closeEvent {
    _: Success -> {
      eventSender.close()
      return
    }
    _: Failure -> {}
  }

  errorEvent := event as WebSocketError
  case errorEvent {
    _: Success -> {
      eventSender.close()
      return
    }
    _: Failure -> {}
  }
}
