import { MouseButton } from "./types"

const MOUSE_LEFT = 0
const MOUSE_RIGHT = 1
const MOUSE_MIDDLE = 2
const MOUSE_OTHER = 3

export function mouseButtonCode(button: MouseButton): int {
  return case button {
    MouseButton.Left -> MOUSE_LEFT,
    MouseButton.Right -> MOUSE_RIGHT,
    MouseButton.Middle -> MOUSE_MIDDLE,
    _ -> MOUSE_OTHER,
  }
}

export function mouseButtonFromCode(code: int): MouseButton {
  return case code {
    MOUSE_LEFT -> MouseButton.Left,
    MOUSE_RIGHT -> MouseButton.Right,
    MOUSE_MIDDLE -> MouseButton.Middle,
    _ -> MouseButton.Other,
  }
}
