import { Backpressure, ChannelReceiver, ChannelSender, SendError, createChannel } from "std/event"

import {
  COLUMNS,
  ROWS,
  GroupPosition,
  Piece,
  PuzzleState,
  bringGroupToFront,
  cloneIntArray,
  clonePuzzleState,
  groupPieceIds,
  groupPosition,
  moveGroup,
  setGroupCanonicalPosition,
} from "./jigsaw_model"

export enum JigsawClientCommandKind {
  MoveGroup,
  JoinGroups,
}

export enum JigsawServerEventKind {
  BoardSnapshot,
  GroupMoved,
  GroupJoined,
  MoveCancelled,
}

export class JigsawClientCommand {
  kind: JigsawClientCommandKind
  clientId: int
  primaryGroupId: int = -1
  groupIds: int[] = []
  additionalGroupIds: int[] = []
  x: double = 0.0
  y: double = 0.0
  position: GroupPosition | null = null
}

export class JigsawServerEvent {
  kind: JigsawServerEventKind
  clientId: int = -1
  groupId: int = -1
  groupIds: int[] = []
  pieceIds: int[] = []
  x: double = 0.0
  y: double = 0.0
  position: GroupPosition | null = null
  state: PuzzleState | null = null
  drawOrder: int[] = []
  cancelledGroups: GroupPosition[] = []
}

export class JigsawSessionConfig {
  commandCapacity: int = 256
  eventCapacity: int = 256
}

export class JigsawClientConnection {
  clientId: int
  commands: ChannelSender<JigsawClientCommand>
  events: ChannelReceiver<JigsawServerEvent>
}

class JigsawClientEndpoint {
  clientId: int
  sender: ChannelSender<JigsawServerEvent>
}

class JigsawGroupDefinition {
  id: int
  pieceIds: int[]
}

class MoveResolution {
  accepted: bool
  canonicalGroupId: int = -1
  requestedGroups: int[] = []
}

export class JigsawSession {
  commands: ChannelSender<JigsawClientCommand>
  private readonly commandEvents: ChannelReceiver<JigsawClientCommand>
  private state: PuzzleState
  private clients: JigsawClientEndpoint[] = []
  private groupDefinitions: JigsawGroupDefinition[] = []
  private nextClientId: int = 1
  private nextGroupId: int
  private eventCapacity: int
  private onStateChanged: (state: PuzzleState): void

  connectClient(): JigsawClientConnection {
    clientId := this.nextClientId
    this.nextClientId = this.nextClientId + 1
    (sender, events) := createChannel<JigsawServerEvent>{
      capacity: this.eventCapacity,
      keepsAlive: false,
    }
    endpoint := JigsawClientEndpoint { clientId, sender }
    this.clients.push(endpoint)
    ignored := sender.send(boardSnapshotEvent(this.state, clientId))
    return JigsawClientConnection { clientId, commands: this.commands, events }
  }

  currentState(): PuzzleState {
    return clonePuzzleState(this.state)
  }

  handleCommand(command: JigsawClientCommand): void {
    if command.kind == JigsawClientCommandKind.MoveGroup {
      this.handleMove(command)
    }
    if command.kind == JigsawClientCommandKind.JoinGroups {
      this.handleJoin(command)
    }
  }

  private handleMove(command: JigsawClientCommand): void {
    requested := requestedMoveGroups(command)
    resolution := this.resolveMove(requested)
    if resolution.accepted {
      setGroupCanonicalPosition(this.state.pieces, resolution.canonicalGroupId, command.x, command.y)
      this.state.drawOrder = bringGroupToFront(this.state.pieces, this.state.drawOrder, resolution.canonicalGroupId)
      position := groupPosition(this.state.pieces, resolution.canonicalGroupId)
      event := JigsawServerEvent {
        kind: JigsawServerEventKind.GroupMoved,
        clientId: command.clientId,
        groupId: resolution.canonicalGroupId,
        pieceIds: this.activeGroupPieceIds(resolution.canonicalGroupId),
        x: position.x,
        y: position.y,
        drawOrder: cloneIntArray(this.state.drawOrder),
      }
      this.broadcastExcept(command.clientId, event, moveEventKey(resolution.canonicalGroupId))
      this.notifyStateChanged()
    } else {
      this.sendToClient(command.clientId, JigsawServerEvent {
        kind: JigsawServerEventKind.MoveCancelled,
        clientId: command.clientId,
        groupIds: resolution.requestedGroups,
        cancelledGroups: this.canonicalPositionsForRequestedGroups(resolution.requestedGroups),
        drawOrder: cloneIntArray(this.state.drawOrder),
      }, null)
    }
  }

  private handleJoin(command: JigsawClientCommand): void {
    requestedGroups := uniqueInts(command.groupIds)
    requestedPieceIds := this.expandGroupIds(requestedGroups)
    if requestedPieceIds.length == 0 {
      return
    }
    requestedPosition := command.position else {
      return
    }
    newGroupId := this.nextGroupId
    this.nextGroupId = this.nextGroupId + 1
    for pieceId of requestedPieceIds {
      this.state.pieces[pieceId].group = newGroupId
    }
    pieceIds := groupPieceIds(this.state.pieces, newGroupId)
    this.groupDefinitions.push(JigsawGroupDefinition { id: newGroupId, pieceIds: cloneIntArray(pieceIds) })
    setGroupCanonicalPosition(this.state.pieces, newGroupId, requestedPosition.x, requestedPosition.y)
    this.state.drawOrder = bringGroupToFront(this.state.pieces, this.state.drawOrder, newGroupId)
    position := groupPosition(this.state.pieces, newGroupId)
    this.broadcastAll(JigsawServerEvent {
      kind: JigsawServerEventKind.GroupJoined,
      clientId: command.clientId,
      groupId: newGroupId,
      groupIds: requestedGroups,
      pieceIds,
      x: position.x,
      y: position.y,
      position,
      drawOrder: cloneIntArray(this.state.drawOrder),
    }, null)
    this.notifyStateChanged()
  }

  private resolveMove(requestedGroups: int[]): MoveResolution {
    if requestedGroups.length == 0 {
      return MoveResolution { accepted: false, requestedGroups }
    }
    requestedPieceIds := this.expandGroupIds(requestedGroups)
    if requestedPieceIds.length == 0 {
      return MoveResolution { accepted: false, requestedGroups }
    }
    canonicalGroup := this.canonicalGroupForPiece(requestedPieceIds[0])
    if canonicalGroup < 0 {
      return MoveResolution { accepted: false, requestedGroups }
    }
    canonicalPieceIds := this.activeGroupPieceIds(canonicalGroup)
    if sameIntSet(requestedPieceIds, canonicalPieceIds) {
      return MoveResolution { accepted: true, canonicalGroupId: canonicalGroup, requestedGroups }
    }
    return MoveResolution { accepted: false, requestedGroups }
  }

  private expandGroupIds(groupIds: int[]): int[] {
    pieceIds: int[] := []
    for groupId of groupIds {
      definition := this.groupDefinition(groupId)
      if definition != null {
        for pieceId of definition!.pieceIds {
          if !pieceIds.contains(pieceId) {
            pieceIds.push(pieceId)
          }
        }
      }
    }
    return pieceIds
  }

  private activeGroupPieceIds(groupId: int): int[] {
    return groupPieceIds(this.state.pieces, groupId)
  }

  private canonicalGroupForPiece(pieceId: int): int {
    if pieceId < 0 || pieceId >= COLUMNS * ROWS {
      return -1
    }
    return this.state.pieces[pieceId].group
  }

  private groupDefinition(groupId: int): JigsawGroupDefinition | null {
    for definition of this.groupDefinitions {
      if definition.id == groupId {
        return definition
      }
    }
    return null
  }

  private canonicalPositionsForRequestedGroups(groupIds: int[]): GroupPosition[] {
    positions: GroupPosition[] := []
    seen: int[] := []
    pieceIds := this.expandGroupIds(groupIds)
    for pieceId of pieceIds {
      canonicalGroup := this.canonicalGroupForPiece(pieceId)
      if canonicalGroup >= 0 && !seen.contains(canonicalGroup) {
        seen.push(canonicalGroup)
        positions.push(groupPosition(this.state.pieces, canonicalGroup))
      }
    }
    return positions
  }

  private broadcastAll(event: JigsawServerEvent, key: string | null): void {
    liveClients: JigsawClientEndpoint[] := []
    for client of this.clients {
      sent := client.sender.send(event, key)
      case sent {
        _: Success -> liveClients.push(client)
        _: Failure -> {}
      }
    }
    this.clients = liveClients
  }

  private broadcastExcept(originClientId: int, event: JigsawServerEvent, key: string | null): void {
    liveClients: JigsawClientEndpoint[] := []
    for client of this.clients {
      if client.clientId != originClientId {
        sent := client.sender.send(event, key)
        case sent {
          _: Success -> liveClients.push(client)
          _: Failure -> {}
        }
      } else {
        liveClients.push(client)
      }
    }
    this.clients = liveClients
  }

  private sendToClient(clientId: int, event: JigsawServerEvent, key: string | null): void {
    liveClients: JigsawClientEndpoint[] := []
    for client of this.clients {
      if client.clientId == clientId {
        sent := client.sender.send(event, key)
        case sent {
          _: Success -> liveClients.push(client)
          _: Failure -> {}
        }
      } else {
        liveClients.push(client)
      }
    }
    this.clients = liveClients
  }

  private notifyStateChanged(): void {
    this.onStateChanged.call(clonePuzzleState(this.state))
  }
}

export function createJigsawSession(initialState: PuzzleState, config: JigsawSessionConfig = JigsawSessionConfig {}): JigsawSession {
  return createJigsawSessionWithStateChanged(initialState, (state: PuzzleState): void => {}, config)
}

export function createJigsawSessionWithStateChanged(
  initialState: PuzzleState,
  onStateChanged: (state: PuzzleState): void,
  config: JigsawSessionConfig = JigsawSessionConfig {},
): JigsawSession {
  if config.commandCapacity <= 0 {
    panic("Jigsaw command capacity must be positive")
  }
  if config.eventCapacity <= 0 {
    panic("Jigsaw event capacity must be positive")
  }
  (commands, commandEvents) := createChannel<JigsawClientCommand>{
    capacity: config.commandCapacity,
    keepsAlive: false,
  }
  state := clonePuzzleState(initialState)
  session := JigsawSession {
    commands,
    commandEvents,
    state,
    groupDefinitions: initialGroupDefinitions(state),
    nextGroupId: maxInitialGroupId(state) + 1,
    eventCapacity: config.eventCapacity,
    onStateChanged,
  }
  commandEvents.onMessage((command: JigsawClientCommand): void => session.handleCommand(command))
  return session
}

export function sendMoveGroup(
  connection: JigsawClientConnection,
  primaryGroupId: int,
  x: double,
  y: double,
  additionalGroupIds: int[] = [],
): Result<Backpressure, SendError> {
  return connection.commands.send(JigsawClientCommand {
    kind: JigsawClientCommandKind.MoveGroup,
    clientId: connection.clientId,
    primaryGroupId,
    additionalGroupIds,
    x,
    y,
  }, moveCommandKey(connection.clientId, primaryGroupId))
}

export function sendJoinGroups(
  connection: JigsawClientConnection,
  groupIds: int[],
  x: double,
  y: double,
): Result<Backpressure, SendError> {
  return connection.commands.send(JigsawClientCommand {
    kind: JigsawClientCommandKind.JoinGroups,
    clientId: connection.clientId,
    groupIds,
    x,
    y,
    position: GroupPosition { groupId: -1, x, y },
  })
}

export function moveCommandKey(clientId: int, primaryGroupId: int): string {
  return "move:${clientId}:${primaryGroupId}"
}

export function moveEventKey(groupId: int): string {
  return "move:${groupId}"
}

function boardSnapshotEvent(state: PuzzleState, clientId: int): JigsawServerEvent {
  return JigsawServerEvent {
    kind: JigsawServerEventKind.BoardSnapshot,
    clientId,
    state: clonePuzzleState(state),
  }
}

function requestedMoveGroups(command: JigsawClientCommand): int[] {
  groups: int[] := []
  if command.primaryGroupId >= 0 {
    groups.push(command.primaryGroupId)
  }
  for groupId of command.additionalGroupIds {
    if !groups.contains(groupId) {
      groups.push(groupId)
    }
  }
  return groups
}

function initialGroupDefinitions(state: PuzzleState): JigsawGroupDefinition[] {
  definitions: JigsawGroupDefinition[] := []
  for piece of state.pieces {
    existing := findDefinition(definitions, piece.group)
    if existing == null {
      definitions.push(JigsawGroupDefinition { id: piece.group, pieceIds: [piece.id] })
    } else {
      existing!.pieceIds.push(piece.id)
    }
  }
  return definitions
}

function findDefinition(definitions: JigsawGroupDefinition[], groupId: int): JigsawGroupDefinition | null {
  for definition of definitions {
    if definition.id == groupId {
      return definition
    }
  }
  return null
}

function maxInitialGroupId(state: PuzzleState): int {
  let maxId = -1
  for piece of state.pieces {
    if piece.group > maxId {
      maxId = piece.group
    }
  }
  return maxId
}

function uniqueInts(values: int[]): int[] {
  unique: int[] := []
  for value of values {
    if !unique.contains(value) {
      unique.push(value)
    }
  }
  return unique
}

function sameIntSet(left: int[], right: int[]): bool {
  if left.length != right.length {
    return false
  }
  for value of left {
    if !right.contains(value) {
      return false
    }
  }
  return true
}
