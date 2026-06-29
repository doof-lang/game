import { ControllerAxis, ControllerButton, ControllerSlot, ControllerStick } from "./types"

readonly CONTROLLER_SLOT_ONE = 0
readonly CONTROLLER_SLOT_TWO = 1
readonly CONTROLLER_SLOT_THREE = 2
readonly CONTROLLER_SLOT_FOUR = 3

readonly CONTROLLER_BUTTON_SOUTH = 0
readonly CONTROLLER_BUTTON_EAST = 1
readonly CONTROLLER_BUTTON_WEST = 2
readonly CONTROLLER_BUTTON_NORTH = 3
readonly CONTROLLER_BUTTON_LEFT_SHOULDER = 4
readonly CONTROLLER_BUTTON_RIGHT_SHOULDER = 5
readonly CONTROLLER_BUTTON_LEFT_TRIGGER = 6
readonly CONTROLLER_BUTTON_RIGHT_TRIGGER = 7
readonly CONTROLLER_BUTTON_MENU = 8
readonly CONTROLLER_BUTTON_OPTIONS = 9
readonly CONTROLLER_BUTTON_LEFT_STICK = 10
readonly CONTROLLER_BUTTON_RIGHT_STICK = 11
readonly CONTROLLER_BUTTON_DPAD_UP = 12
readonly CONTROLLER_BUTTON_DPAD_DOWN = 13
readonly CONTROLLER_BUTTON_DPAD_LEFT = 14
readonly CONTROLLER_BUTTON_DPAD_RIGHT = 15

readonly CONTROLLER_AXIS_LEFT_X = 0
readonly CONTROLLER_AXIS_LEFT_Y = 1
readonly CONTROLLER_AXIS_RIGHT_X = 2
readonly CONTROLLER_AXIS_RIGHT_Y = 3
readonly CONTROLLER_AXIS_LEFT_TRIGGER = 4
readonly CONTROLLER_AXIS_RIGHT_TRIGGER = 5

export function controllerSlotCode(slot: ControllerSlot): int {
  return case slot {
    ControllerSlot.One -> CONTROLLER_SLOT_ONE,
    ControllerSlot.Two -> CONTROLLER_SLOT_TWO,
    ControllerSlot.Three -> CONTROLLER_SLOT_THREE,
    ControllerSlot.Four -> CONTROLLER_SLOT_FOUR,
    _ -> CONTROLLER_SLOT_ONE,
  }
}

export function controllerSlotFromCode(code: int): ControllerSlot {
  return case code {
    CONTROLLER_SLOT_ONE -> ControllerSlot.One,
    CONTROLLER_SLOT_TWO -> ControllerSlot.Two,
    CONTROLLER_SLOT_THREE -> ControllerSlot.Three,
    CONTROLLER_SLOT_FOUR -> ControllerSlot.Four,
    _ -> ControllerSlot.One,
  }
}

export function controllerButtonCode(button: ControllerButton): int {
  return case button {
    ControllerButton.South -> CONTROLLER_BUTTON_SOUTH,
    ControllerButton.East -> CONTROLLER_BUTTON_EAST,
    ControllerButton.West -> CONTROLLER_BUTTON_WEST,
    ControllerButton.North -> CONTROLLER_BUTTON_NORTH,
    ControllerButton.LeftShoulder -> CONTROLLER_BUTTON_LEFT_SHOULDER,
    ControllerButton.RightShoulder -> CONTROLLER_BUTTON_RIGHT_SHOULDER,
    ControllerButton.LeftTrigger -> CONTROLLER_BUTTON_LEFT_TRIGGER,
    ControllerButton.RightTrigger -> CONTROLLER_BUTTON_RIGHT_TRIGGER,
    ControllerButton.Menu -> CONTROLLER_BUTTON_MENU,
    ControllerButton.Options -> CONTROLLER_BUTTON_OPTIONS,
    ControllerButton.LeftStick -> CONTROLLER_BUTTON_LEFT_STICK,
    ControllerButton.RightStick -> CONTROLLER_BUTTON_RIGHT_STICK,
    ControllerButton.DPadUp -> CONTROLLER_BUTTON_DPAD_UP,
    ControllerButton.DPadDown -> CONTROLLER_BUTTON_DPAD_DOWN,
    ControllerButton.DPadLeft -> CONTROLLER_BUTTON_DPAD_LEFT,
    ControllerButton.DPadRight -> CONTROLLER_BUTTON_DPAD_RIGHT,
    _ -> CONTROLLER_BUTTON_SOUTH,
  }
}

export function controllerButtonFromCode(code: int): ControllerButton {
  return case code {
    CONTROLLER_BUTTON_SOUTH -> ControllerButton.South,
    CONTROLLER_BUTTON_EAST -> ControllerButton.East,
    CONTROLLER_BUTTON_WEST -> ControllerButton.West,
    CONTROLLER_BUTTON_NORTH -> ControllerButton.North,
    CONTROLLER_BUTTON_LEFT_SHOULDER -> ControllerButton.LeftShoulder,
    CONTROLLER_BUTTON_RIGHT_SHOULDER -> ControllerButton.RightShoulder,
    CONTROLLER_BUTTON_LEFT_TRIGGER -> ControllerButton.LeftTrigger,
    CONTROLLER_BUTTON_RIGHT_TRIGGER -> ControllerButton.RightTrigger,
    CONTROLLER_BUTTON_MENU -> ControllerButton.Menu,
    CONTROLLER_BUTTON_OPTIONS -> ControllerButton.Options,
    CONTROLLER_BUTTON_LEFT_STICK -> ControllerButton.LeftStick,
    CONTROLLER_BUTTON_RIGHT_STICK -> ControllerButton.RightStick,
    CONTROLLER_BUTTON_DPAD_UP -> ControllerButton.DPadUp,
    CONTROLLER_BUTTON_DPAD_DOWN -> ControllerButton.DPadDown,
    CONTROLLER_BUTTON_DPAD_LEFT -> ControllerButton.DPadLeft,
    CONTROLLER_BUTTON_DPAD_RIGHT -> ControllerButton.DPadRight,
    _ -> ControllerButton.South,
  }
}

export function controllerAxisCode(axis: ControllerAxis): int {
  return case axis {
    ControllerAxis.LeftX -> CONTROLLER_AXIS_LEFT_X,
    ControllerAxis.LeftY -> CONTROLLER_AXIS_LEFT_Y,
    ControllerAxis.RightX -> CONTROLLER_AXIS_RIGHT_X,
    ControllerAxis.RightY -> CONTROLLER_AXIS_RIGHT_Y,
    ControllerAxis.LeftTrigger -> CONTROLLER_AXIS_LEFT_TRIGGER,
    ControllerAxis.RightTrigger -> CONTROLLER_AXIS_RIGHT_TRIGGER,
    _ -> CONTROLLER_AXIS_LEFT_X,
  }
}

export function controllerAxisFromCode(code: int): ControllerAxis {
  return case code {
    CONTROLLER_AXIS_LEFT_X -> ControllerAxis.LeftX,
    CONTROLLER_AXIS_LEFT_Y -> ControllerAxis.LeftY,
    CONTROLLER_AXIS_RIGHT_X -> ControllerAxis.RightX,
    CONTROLLER_AXIS_RIGHT_Y -> ControllerAxis.RightY,
    CONTROLLER_AXIS_LEFT_TRIGGER -> ControllerAxis.LeftTrigger,
    CONTROLLER_AXIS_RIGHT_TRIGGER -> ControllerAxis.RightTrigger,
    _ -> ControllerAxis.LeftX,
  }
}

export function controllerStickXAxis(stick: ControllerStick): ControllerAxis {
  return case stick {
    ControllerStick.Right -> ControllerAxis.RightX,
    _ -> ControllerAxis.LeftX,
  }
}

export function controllerStickYAxis(stick: ControllerStick): ControllerAxis {
  return case stick {
    ControllerStick.Right -> ControllerAxis.RightY,
    _ -> ControllerAxis.LeftY,
  }
}
