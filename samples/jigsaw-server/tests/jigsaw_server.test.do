import { Assert } from "std/assert"
import { drainMainEventLoop, runMainEventLoop, setTimeout } from "std/event"
import { exists, remove } from "std/fs"
import { join, tempDirectory } from "std/path"
import { Duration } from "std/time"

import {
  JigsawClientCommand,
  JigsawClientCommandKind,
  JigsawServerEvent,
  JigsawServerEventKind,
  encodeJigsawCommandFrame,
  groupPosition,
} from "../../jigsaw"

import {
  JigsawHttpServerOptions,
  createDefaultJigsawServerState,
  forwardJigsawCommandForClient,
  loadJigsawServerState,
  startJigsawHttpServer,
} from "../index"

import class NativeWebSocketTestClient from "http-server/native_http_server_test_support.hpp" as doof_http_server_test::NativeWebSocketTestClient {
  static startExchangeText(host: string, port: int, requestText: string, text: string): NativeWebSocketTestClient
  static startHandshakeOnly(host: string, port: int, requestText: string): NativeWebSocketTestClient
  wait(): string
}

class MoveState {
  movedClientId: int = -1
  movedX: double = 0.0
  movedY: double = 0.0
}

function socketRequest(path: string): string {
  return "GET ${path} HTTP/1.1\r\nHost: example.test\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
}

function moveCommandFrame(clientId: int, groupId: int, x: double, y: double): string {
  return encodeJigsawCommandFrame(JigsawClientCommand {
    kind: JigsawClientCommandKind.MoveGroup,
    clientId,
    primaryGroupId: groupId,
    x,
    y,
  })
}

function tempStatePath(name: string): string {
  path := join([tempDirectory(), name])
  if exists(path) {
    ignored := remove(path)
  }
  return path
}

export function testRemoteWebSocketReceivesBoardSnapshot(): void {
  server := try! startJigsawHttpServer(
    createDefaultJigsawServerState(),
    JigsawHttpServerOptions { port: 0 },
  )

  client := NativeWebSocketTestClient.startExchangeText(
    server.host,
    server.port,
    socketRequest("/jigsaw"),
    moveCommandFrame(999, 0, 1.0, 2.0),
  )

  setTimeout{
    delay: Duration.ofMillis(100L),
    handler: (): void => server.close(),
  }

  runMainEventLoop()
  response := client.wait()

  Assert.isTrue(response.contains("HTTP/1.1 101 Switching Protocols"), response)
  Assert.isTrue(response.contains("\"type\":\"event\""), response)
  Assert.isTrue(response.contains("\"kind\":\"BoardSnapshot\""), response)
}

export function testServerOverwritesSpoofedClientIdBeforeBroadcast(): void {
  server := try! startJigsawHttpServer(
    createDefaultJigsawServerState(),
    JigsawHttpServerOptions { port: 0 },
  )
  watcher := server.session.connectClient()
  remote := server.session.connectClient()
  state := MoveState()

  watcher.events.onMessage((event: JigsawServerEvent): void => {
    if event.kind == JigsawServerEventKind.GroupMoved {
      state.movedClientId = event.clientId
      state.movedX = event.x
      state.movedY = event.y
    }
  })

  try! forwardJigsawCommandForClient(remote, moveCommandFrame(999, 0, 50.0, 60.0))
  ignored := drainMainEventLoop()
  watcher.events.close()
  remote.events.close()
  server.close()

  Assert.notEqual(state.movedClientId, 999)
  Assert.equal(state.movedClientId, remote.clientId)
  Assert.equal(state.movedX, 50.0)
  Assert.equal(state.movedY, 60.0)
}

export function testServerPersistsStateAfterCommand(): void {
  statePath := tempStatePath("doof-jigsaw-server-persist-command.json")
  server := try! startJigsawHttpServer(
    createDefaultJigsawServerState(),
    JigsawHttpServerOptions { port: 0, statePath },
  )
  remote := server.session.connectClient()

  try! forwardJigsawCommandForClient(remote, moveCommandFrame(999, 0, 70.0, 80.0))
  ignored := drainMainEventLoop()
  remote.events.close()
  server.close()

  Assert.isTrue(exists(statePath))
  saved := try! loadJigsawServerState(statePath)
  position := groupPosition(saved.pieces, 0)
  Assert.equal(position.x, 70.0)
  Assert.equal(position.y, 80.0)
}

export function testServerLoadsPersistedStateOnStartup(): void {
  statePath := tempStatePath("doof-jigsaw-server-persist-startup.json")
  first := try! startJigsawHttpServer(
    createDefaultJigsawServerState(),
    JigsawHttpServerOptions { port: 0, statePath },
  )
  remote := first.session.connectClient()
  try! forwardJigsawCommandForClient(remote, moveCommandFrame(999, 0, 90.0, 100.0))
  ignored := drainMainEventLoop()
  remote.events.close()
  first.close()

  second := try! startJigsawHttpServer(
    createDefaultJigsawServerState(),
    JigsawHttpServerOptions { port: 0, statePath },
  )
  loaded := second.session.currentState()
  second.close()

  position := groupPosition(loaded.pieces, 0)
  Assert.equal(position.x, 90.0)
  Assert.equal(position.y, 100.0)
}

export function testResetStateIgnoresAndOverwritesPersistedState(): void {
  statePath := tempStatePath("doof-jigsaw-server-reset-startup.json")
  first := try! startJigsawHttpServer(
    createDefaultJigsawServerState(),
    JigsawHttpServerOptions { port: 0, statePath },
  )
  remote := first.session.connectClient()
  try! forwardJigsawCommandForClient(remote, moveCommandFrame(999, 0, 110.0, 120.0))
  ignored := drainMainEventLoop()
  remote.events.close()
  first.close()

  reset := try! startJigsawHttpServer(
    createDefaultJigsawServerState(),
    JigsawHttpServerOptions { port: 0, statePath, resetState: true },
  )
  resetState := reset.session.currentState()
  reset.close()

  position := groupPosition(resetState.pieces, 0)
  Assert.notEqual(position.x, 110.0)
  Assert.notEqual(position.y, 120.0)

  saved := try! loadJigsawServerState(statePath)
  savedPosition := groupPosition(saved.pieces, 0)
  Assert.equal(savedPosition.x, position.x)
  Assert.equal(savedPosition.y, position.y)
}

export function testBadPathRejectsHandshake(): void {
  server := try! startJigsawHttpServer(
    createDefaultJigsawServerState(),
    JigsawHttpServerOptions { port: 0 },
  )

  client := NativeWebSocketTestClient.startHandshakeOnly(
    server.host,
    server.port,
    socketRequest("/bad"),
  )

  setTimeout{
    delay: Duration.ofMillis(100L),
    handler: (): void => server.close(),
  }

  runMainEventLoop()
  response := client.wait()

  Assert.isTrue(response.contains("HTTP/1.1 404 Not Found"), response)
}
