import { NativeGameEvent } from "./native"
import { controllerSlotFromCode } from "./controller"
import { keyFromCode } from "./keys"
import { mouseButtonFromCode } from "./mouse"
import { ControllerSlot, GameEventKind, Key, MouseButton } from "./types"

const KIND_CLOSE_REQUESTED = 0
const KIND_RESIZED = 1
const KIND_KEY_DOWN = 2
const KIND_KEY_UP = 3
const KIND_MOUSE_DOWN = 4
const KIND_MOUSE_UP = 5
const KIND_MOUSE_MOVE = 6
const KIND_SCROLL = 7
const KIND_DOUBLE_TAP = 8
const KIND_MAGNIFY = 9
const KIND_PAN = 10
const KIND_CONTROLLER_CONNECTED = 11
const KIND_CONTROLLER_DISCONNECTED = 12

export class ControllerEvent {
  private readonly native: NativeGameEvent

  slot(): ControllerSlot => controllerSlotFromCode(this.native.controllerSlotCode())
  connected(): bool => this.native.kindCode() == KIND_CONTROLLER_CONNECTED
  name(): string => this.native.controllerName()
}

export class GameEvent {
  private readonly native: NativeGameEvent

  kind(): GameEventKind => gameEventKindFromCode(this.native.kindCode())
  controller(): ControllerEvent => ControllerEvent(this.native)
  key(): Key => keyFromCode(this.native.keyCode())
  mouseButton(): MouseButton => mouseButtonFromCode(this.native.mouseButtonCode())
  x(): double => this.native.x()
  y(): double => this.native.y()
  deltaX(): double => this.native.deltaX()
  deltaY(): double => this.native.deltaY()
  panDeltaX(): double => this.native.panDeltaX()
  panDeltaY(): double => this.native.panDeltaY()
  scrollDeltaX(): double => this.native.scrollDeltaX()
  scrollDeltaY(): double => this.native.scrollDeltaY()
  pixelWidth(): int => this.native.pixelWidth()
  pixelHeight(): int => this.native.pixelHeight()
  magnificationDelta(): double => this.native.magnificationDelta()
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
    KIND_SCROLL -> GameEventKind.Scroll,
    KIND_DOUBLE_TAP -> GameEventKind.DoubleTap,
    KIND_MAGNIFY -> GameEventKind.Magnify,
    KIND_PAN -> GameEventKind.Pan,
    KIND_CONTROLLER_CONNECTED -> GameEventKind.ControllerConnected,
    KIND_CONTROLLER_DISCONNECTED -> GameEventKind.ControllerDisconnected,
    _ -> GameEventKind.CloseRequested,
  }
}
