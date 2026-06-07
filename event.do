import { NativeGameEvent } from "./native"
import { keyFromCode } from "./keys"
import { mouseButtonFromCode } from "./mouse"
import { GameEventKind, Key, MouseButton } from "./types"

const KIND_CLOSE_REQUESTED = 0
const KIND_RESIZED = 1
const KIND_KEY_DOWN = 2
const KIND_KEY_UP = 3
const KIND_MOUSE_DOWN = 4
const KIND_MOUSE_UP = 5
const KIND_MOUSE_MOVE = 6
const KIND_MOUSE_WHEEL = 7
const KIND_DOUBLE_TAP = 8

export class GameEvent {
  private readonly native: NativeGameEvent

  kind(): GameEventKind => gameEventKindFromCode(this.native.kindCode())
  key(): Key => keyFromCode(this.native.keyCode())
  mouseButton(): MouseButton => mouseButtonFromCode(this.native.mouseButtonCode())
  x(): double => this.native.x()
  y(): double => this.native.y()
  deltaX(): double => this.native.deltaX()
  deltaY(): double => this.native.deltaY()
  wheelDeltaX(): double => this.native.wheelDeltaX()
  wheelDeltaY(): double => this.native.wheelDeltaY()
  pixelWidth(): int => this.native.pixelWidth()
  pixelHeight(): int => this.native.pixelHeight()
}

export function gameEventKindFromCode(code: int): GameEventKind {
  return case code {
    KIND_CLOSE_REQUESTED -> GameEventKind.CloseRequested,
    KIND_RESIZED -> GameEventKind.Resized,
    KIND_KEY_DOWN -> GameEventKind.KeyDown,
    KIND_KEY_UP -> GameEventKind.KeyUp,
    KIND_MOUSE_DOWN -> GameEventKind.MouseDown,
    KIND_MOUSE_UP -> GameEventKind.MouseUp,
    KIND_MOUSE_MOVE -> GameEventKind.MouseMove,
    KIND_MOUSE_WHEEL -> GameEventKind.MouseWheel,
    KIND_DOUBLE_TAP -> GameEventKind.DoubleTap,
    _ -> GameEventKind.CloseRequested,
  }
}
