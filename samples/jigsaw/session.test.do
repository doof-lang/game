import { Assert } from "std/assert"
import { drainMainEventLoop } from "std/event"
import { approxEqual } from "std/math"

import {
  COLUMNS,
  ROWS,
  GroupPosition,
  Piece,
  PuzzleCamera,
  PuzzleState,
  createLayoutForSize,
  groupPosition,
  joinNearbyPieces,
  setGroupCanonicalPosition,
  setGroupPositionFromPiece,
} from "./jigsaw_model"
import {
  screenToWorldX,
  screenToWorldY,
  setZoomAt,
  zoomFactorForMagnificationDelta,
  zoomFactorForScrollDelta,
} from "./client_runtime"
import {
  JigsawClientCommand,
  JigsawClientCommandKind,
  JigsawServerEvent,
  JigsawServerEventKind,
  JigsawSessionConfig,
  createJigsawSession,
  sendJoinGroups,
  sendMoveGroup,
} from "./session"
import {
  decodeJigsawCommandFrame,
  decodeJigsawEventFrame,
  encodeJigsawCommandFrame,
  encodeJigsawEventFrame,
  normalizeJigsawServerUrl,
} from "./protocol"

function testState(): PuzzleState {
  pieces: Piece[] := []
  for row of 0..<ROWS {
    for column of 0..<COLUMNS {
      id := row * COLUMNS + column
      pieces.push(Piece {
        id,
        column,
        row,
        group: id,
        x: double(column) * 10.0,
        y: double(row) * 10.0,
      })
    }
  }
  drawOrder: int[] := []
  for id of 0..<COLUMNS * ROWS {
    drawOrder.push(id)
  }
  return PuzzleState {
    version: 1,
    columns: COLUMNS,
    rows: ROWS,
    pieces,
    drawOrder,
    camera: PuzzleCamera { x: 0.0, y: 0.0, zoom: 1.0, minZoom: 0.5, maxZoom: 2.0 },
  }
}

function collectEvents(connectionEvents: JigsawServerEvent[]): (event: JigsawServerEvent): void {
  return (event: JigsawServerEvent): void => connectionEvents.push(event)
}

function assertApprox(actual: double, expected: double): void {
  Assert.isTrue(approxEqual(actual, expected), "expected ${actual} to approximately equal ${expected}")
}

export function testZoomFactorsSeparateScrollAndMagnifyInput(): void {
  assertApprox(zoomFactorForScrollDelta(10.0), 0.9)
  assertApprox(zoomFactorForMagnificationDelta(0.1), 1.1)
}

export function testSetZoomAtPreservesWorldPointUnderCursor(): void {
  camera := PuzzleCamera { x: 10.0, y: 20.0, zoom: 1.0, minZoom: 0.5, maxZoom: 4.0 }
  screenX := 120.0
  screenY := 80.0
  worldX := screenToWorldX(camera, screenX)
  worldY := screenToWorldY(camera, screenY)

  setZoomAt(camera, screenX, screenY, 2.0)

  assertApprox(camera.zoom, 2.0)
  assertApprox(screenToWorldX(camera, screenX), worldX)
  assertApprox(screenToWorldY(camera, screenY), worldY)
}

export function testConnectEmitsFullBoardSnapshot(): void {
  session := createJigsawSession(testState())
  client := session.connectClient()
  events: JigsawServerEvent[] := []
  client.events.onMessage(collectEvents(events))

  drainMainEventLoop()

  Assert.equal(events.length, 1)
  Assert.equal(events[0].kind, JigsawServerEventKind.BoardSnapshot)
  snapshot := events[0].state as PuzzleState else {
    Assert.fail("expected snapshot state")
    return
  }
  Assert.equal(snapshot.pieces.length, COLUMNS * ROWS)
  Assert.equal(events[0].clientId, client.clientId)
}

export function testProtocolRoundTripsCommandAndEventFrames(): void {
  command := JigsawClientCommand {
    kind: JigsawClientCommandKind.MoveGroup,
    clientId: 99,
    primaryGroupId: 4,
    x: 12.0,
    y: 24.0,
  }
  decodedCommand := try! decodeJigsawCommandFrame(encodeJigsawCommandFrame(command))
  Assert.equal(decodedCommand.kind, JigsawClientCommandKind.MoveGroup)
  Assert.equal(decodedCommand.clientId, 99)
  Assert.equal(decodedCommand.primaryGroupId, 4)
  Assert.equal(decodedCommand.x, 12.0)
  Assert.equal(decodedCommand.y, 24.0)

  event := JigsawServerEvent {
    kind: JigsawServerEventKind.GroupMoved,
    clientId: 2,
    groupId: 4,
    pieceIds: [4],
    x: 18.0,
    y: 30.0,
  }
  decodedEvent := try! decodeJigsawEventFrame(encodeJigsawEventFrame(event))
  Assert.equal(decodedEvent.kind, JigsawServerEventKind.GroupMoved)
  Assert.equal(decodedEvent.clientId, 2)
  Assert.equal(decodedEvent.groupId, 4)
  Assert.equal(decodedEvent.pieceIds.length, 1)
  Assert.equal(decodedEvent.x, 18.0)
  Assert.equal(decodedEvent.y, 30.0)

  joinCommand := JigsawClientCommand {
    kind: JigsawClientCommandKind.JoinGroups,
    clientId: 7,
    groupIds: [1, 0],
    position: GroupPosition { groupId: -1, x: 64.0, y: 8.0 },
  }
  decodedJoinCommand := try! decodeJigsawCommandFrame(encodeJigsawCommandFrame(joinCommand))
  joinCommandPosition := decodedJoinCommand.position else {
    Assert.fail("expected decoded join command position")
    return
  }
  Assert.equal(decodedJoinCommand.kind, JigsawClientCommandKind.JoinGroups)
  Assert.equal(decodedJoinCommand.groupIds.length, 2)
  Assert.equal(joinCommandPosition.x, 64.0)
  Assert.equal(joinCommandPosition.y, 8.0)

  joinEvent := JigsawServerEvent {
    kind: JigsawServerEventKind.GroupJoined,
    clientId: 7,
    groupId: 100,
    groupIds: [1, 0],
    pieceIds: [0, 1],
    position: GroupPosition { groupId: 100, x: 0.0, y: 0.0 },
  }
  decodedJoinEvent := try! decodeJigsawEventFrame(encodeJigsawEventFrame(joinEvent))
  joinEventPosition := decodedJoinEvent.position else {
    Assert.fail("expected decoded join event position")
    return
  }
  Assert.equal(decodedJoinEvent.kind, JigsawServerEventKind.GroupJoined)
  Assert.equal(joinEventPosition.groupId, 100)
  Assert.equal(joinEventPosition.x, 0.0)
}

export function testNormalizeJigsawServerUrlDefaultsToWebSocketPath(): void {
  Assert.equal(normalizeJigsawServerUrl("127.0.0.1:8765"), "ws://127.0.0.1:8765/jigsaw")
  Assert.equal(normalizeJigsawServerUrl("http://example.test:8080"), "ws://example.test:8080/jigsaw")
  Assert.equal(normalizeJigsawServerUrl("https://example.test"), "wss://example.test/jigsaw")
  Assert.equal(normalizeJigsawServerUrl("ws://example.test/custom"), "ws://example.test/custom")
  Assert.equal(normalizeJigsawServerUrl("wss://example.test/jigsaw"), "wss://example.test/jigsaw")
}

export function testSingleClientMoveUpdatesServerWithoutLocalEcho(): void {
  session := createJigsawSession(testState())
  client := session.connectClient()
  events: JigsawServerEvent[] := []
  client.events.onMessage(collectEvents(events))
  drainMainEventLoop()

  try! sendMoveGroup(client, 0, 42.0, 24.0)
  drainMainEventLoop()

  state := session.currentState()
  position := groupPosition(state.pieces, 0)
  Assert.equal(position.x, 42.0)
  Assert.equal(position.y, 24.0)
  Assert.equal(events.length, 1)
}

export function testMoveCommandsCoalesceByClientAndGroupKey(): void {
  session := createJigsawSession(testState(), JigsawSessionConfig { commandCapacity: 1, eventCapacity: 4 })
  client := session.connectClient()
  try! sendMoveGroup(client, 0, 10.0, 20.0)
  try! sendMoveGroup(client, 0, 30.0, 40.0)

  drainMainEventLoop()

  state := session.currentState()
  position := groupPosition(state.pieces, 0)
  Assert.equal(position.x, 30.0)
  Assert.equal(position.y, 40.0)
}

export function testServerMoveBroadcastsCoalesceByGroupKey(): void {
  session := createJigsawSession(testState(), JigsawSessionConfig { commandCapacity: 8, eventCapacity: 2 })
  first := session.connectClient()
  second := session.connectClient()
  try! sendMoveGroup(first, 0, 10.0, 20.0)
  drainMainEventLoop()
  try! sendMoveGroup(first, 0, 30.0, 40.0)
  drainMainEventLoop()

  events: JigsawServerEvent[] := []
  second.events.onMessage(collectEvents(events))
  drainMainEventLoop()

  Assert.equal(events.length, 2)
  Assert.equal(events[0].kind, JigsawServerEventKind.BoardSnapshot)
  Assert.equal(events[1].kind, JigsawServerEventKind.GroupMoved)
  Assert.equal(events[1].x, 30.0)
  Assert.equal(events[1].y, 40.0)
}

export function testJoinCreatesNewGroupAndBroadcastsIdentity(): void {
  session := createJigsawSession(testState())
  first := session.connectClient()
  second := session.connectClient()
  events: JigsawServerEvent[] := []
  second.events.onMessage(collectEvents(events))
  drainMainEventLoop()

  try! sendJoinGroups(first, [0, 1], 0.0, 0.0)
  drainMainEventLoop()

  joined := events[events.length - 1]
  Assert.equal(joined.kind, JigsawServerEventKind.GroupJoined)
  Assert.equal(joined.groupId, COLUMNS * ROWS)
  Assert.equal(joined.pieceIds.length, 2)
  state := session.currentState()
  Assert.equal(state.pieces[0].group, COLUMNS * ROWS)
  Assert.equal(state.pieces[1].group, COLUMNS * ROWS)
}

export function testJoinWithoutPositionIsIgnored(): void {
  session := createJigsawSession(testState())
  client := session.connectClient()
  drainMainEventLoop()

  sent := client.commands.send(JigsawClientCommand {
    kind: JigsawClientCommandKind.JoinGroups,
    clientId: client.clientId,
    groupIds: [0, 1],
  })
  case sent {
    _: Success -> {}
    _: Failure -> Assert.fail("expected command send to succeed")
  }
  drainMainEventLoop()

  state := session.currentState()
  Assert.equal(state.pieces[0].group, 0)
  Assert.equal(state.pieces[1].group, 1)
}

export function testJoinAnchorsMergedGroupToLowestPiece(): void {
  session := createJigsawSession(testState())
  first := session.connectClient()
  watcher := session.connectClient()
  watcherEvents: JigsawServerEvent[] := []
  watcher.events.onMessage(collectEvents(watcherEvents))
  drainMainEventLoop()

  try! sendMoveGroup(first, 1, 100.0, 0.0)
  drainMainEventLoop()
  try! sendJoinGroups(first, [1, 0], 0.0, 0.0)
  drainMainEventLoop()

  state := session.currentState()
  joinedGroup := COLUMNS * ROWS
  Assert.equal(state.pieces[0].group, joinedGroup)
  Assert.equal(state.pieces[1].group, joinedGroup)
  Assert.equal(state.pieces[0].x, 0.0)
  Assert.equal(state.pieces[1].x, 64.0)

  joined := watcherEvents[watcherEvents.length - 1]
  Assert.equal(joined.kind, JigsawServerEventKind.GroupJoined)
  Assert.equal(joined.x, 0.0)
}

export function testClientJoinPositionIsLowestPieceEvenWhenDraggedPieceIsHigher(): void {
  state := testState()
  layout := createLayoutForSize(1000.0, 800.0)
  setGroupPositionFromPiece(state.pieces, 1, 1, 70.0, 0.0)

  joinedGroups := joinNearbyPieces(state.pieces, layout, 1)
  position := groupPosition(state.pieces, 1)

  Assert.equal(joinedGroups.length, 2)
  Assert.equal(joinedGroups[0], 1)
  Assert.equal(joinedGroups[1], 0)
  Assert.equal(state.pieces[0].group, 1)
  Assert.equal(state.pieces[1].group, 1)
  Assert.equal(state.pieces[0].x, 0.0)
  Assert.equal(state.pieces[1].x, 64.0)
  Assert.equal(position.x, 0.0)
}

export function testJoinCanonicalizesEvenAfterStaleRightSideFinalMove(): void {
  session := createJigsawSession(testState())
  first := session.connectClient()
  drainMainEventLoop()

  try! sendMoveGroup(first, 1, 70.0, 0.0)
  drainMainEventLoop()
  try! sendMoveGroup(first, 1, 0.0, 0.0)
  drainMainEventLoop()
  try! sendJoinGroups(first, [1, 0], 0.0, 0.0)
  drainMainEventLoop()

  state := session.currentState()
  joinedGroup := COLUMNS * ROWS
  Assert.equal(state.pieces[0].group, joinedGroup)
  Assert.equal(state.pieces[1].group, joinedGroup)
  Assert.equal(state.pieces[0].x, 0.0)
  Assert.equal(state.pieces[1].x, 64.0)
}

export function testCanonicalGroupPositionRepairsOverlappedClientGeometry(): void {
  state := testState()
  state.pieces[0].group = 9
  state.pieces[1].group = 9
  state.pieces[0].x = 0.0
  state.pieces[1].x = 0.0

  setGroupCanonicalPosition(state.pieces, 9, 10.0, 20.0)

  Assert.equal(state.pieces[0].x, 10.0)
  Assert.equal(state.pieces[0].y, 20.0)
  Assert.equal(state.pieces[1].x, 74.0)
  Assert.equal(state.pieces[1].y, 20.0)
}

export function testMoveWithJoinedGroupsResolvesToCanonicalGroup(): void {
  session := createJigsawSession(testState())
  first := session.connectClient()
  second := session.connectClient()
  secondEvents: JigsawServerEvent[] := []
  second.events.onMessage(collectEvents(secondEvents))
  drainMainEventLoop()

  try! sendJoinGroups(first, [0, 1], 0.0, 0.0)
  drainMainEventLoop()
  try! sendMoveGroup(first, 0, 50.0, 60.0, [1])
  drainMainEventLoop()

  moved := secondEvents[secondEvents.length - 1]
  Assert.equal(moved.kind, JigsawServerEventKind.GroupMoved)
  Assert.equal(moved.groupId, COLUMNS * ROWS)
  Assert.equal(moved.x, 50.0)
  Assert.equal(moved.y, 60.0)
}

export function testStalePartialMoveCancelsWithCanonicalLocation(): void {
  session := createJigsawSession(testState())
  staleClient := session.connectClient()
  joiningClient := session.connectClient()
  staleEvents: JigsawServerEvent[] := []
  staleClient.events.onMessage(collectEvents(staleEvents))
  drainMainEventLoop()

  try! sendJoinGroups(joiningClient, [0, 1], 0.0, 0.0)
  drainMainEventLoop()
  try! sendMoveGroup(staleClient, 0, 50.0, 60.0)
  drainMainEventLoop()

  cancelled := staleEvents[staleEvents.length - 1]
  Assert.equal(cancelled.kind, JigsawServerEventKind.MoveCancelled)
  Assert.equal(cancelled.cancelledGroups.length, 1)
  Assert.equal(cancelled.cancelledGroups[0].groupId, COLUMNS * ROWS)
}

export function testSingleUserFlowUsesSessionApi(): void {
  session := createJigsawSession(testState())
  client := session.connectClient()
  events: JigsawServerEvent[] := []
  client.events.onMessage(collectEvents(events))
  drainMainEventLoop()

  try! sendMoveGroup(client, 2, 12.0, 18.0)
  try! sendJoinGroups(client, [2, 3], 12.0, 18.0)
  drainMainEventLoop()

  state := session.currentState()
  Assert.equal(state.pieces[2].group, COLUMNS * ROWS)
  Assert.equal(state.pieces[3].group, COLUMNS * ROWS)
  Assert.equal(events[events.length - 1].kind, JigsawServerEventKind.GroupJoined)
}
