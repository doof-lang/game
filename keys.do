import { Key } from "./types"

const KEY_UNKNOWN = 0
const KEY_A = 1
const KEY_B = 2
const KEY_C = 3
const KEY_D = 4
const KEY_E = 5
const KEY_F = 6
const KEY_G = 7
const KEY_H = 8
const KEY_I = 9
const KEY_J = 10
const KEY_K = 11
const KEY_L = 12
const KEY_M = 13
const KEY_N = 14
const KEY_O = 15
const KEY_P = 16
const KEY_Q = 17
const KEY_R = 18
const KEY_S = 19
const KEY_T = 20
const KEY_U = 21
const KEY_V = 22
const KEY_W = 23
const KEY_X = 24
const KEY_Y = 25
const KEY_Z = 26
const KEY_DIGIT_0 = 27
const KEY_DIGIT_1 = 28
const KEY_DIGIT_2 = 29
const KEY_DIGIT_3 = 30
const KEY_DIGIT_4 = 31
const KEY_DIGIT_5 = 32
const KEY_DIGIT_6 = 33
const KEY_DIGIT_7 = 34
const KEY_DIGIT_8 = 35
const KEY_DIGIT_9 = 36
const KEY_ARROW_LEFT = 37
const KEY_ARROW_RIGHT = 38
const KEY_ARROW_UP = 39
const KEY_ARROW_DOWN = 40
const KEY_ESCAPE = 41
const KEY_ENTER = 42
const KEY_SPACE = 43
const KEY_BACKSPACE = 44
const KEY_TAB = 45
const KEY_SHIFT = 46
const KEY_CONTROL = 47
const KEY_OPTION = 48
const KEY_COMMAND = 49
const KEY_F1 = 50
const KEY_F2 = 51
const KEY_F3 = 52
const KEY_F4 = 53
const KEY_F5 = 54
const KEY_F6 = 55
const KEY_F7 = 56
const KEY_F8 = 57
const KEY_F9 = 58
const KEY_F10 = 59
const KEY_F11 = 60
const KEY_F12 = 61

export function keyCode(key: Key): int {
  return case key {
    Key.A -> KEY_A,
    Key.B -> KEY_B,
    Key.C -> KEY_C,
    Key.D -> KEY_D,
    Key.E -> KEY_E,
    Key.F -> KEY_F,
    Key.G -> KEY_G,
    Key.H -> KEY_H,
    Key.I -> KEY_I,
    Key.J -> KEY_J,
    Key.K -> KEY_K,
    Key.L -> KEY_L,
    Key.M -> KEY_M,
    Key.N -> KEY_N,
    Key.O -> KEY_O,
    Key.P -> KEY_P,
    Key.Q -> KEY_Q,
    Key.R -> KEY_R,
    Key.S -> KEY_S,
    Key.T -> KEY_T,
    Key.U -> KEY_U,
    Key.V -> KEY_V,
    Key.W -> KEY_W,
    Key.X -> KEY_X,
    Key.Y -> KEY_Y,
    Key.Z -> KEY_Z,
    Key.Digit0 -> KEY_DIGIT_0,
    Key.Digit1 -> KEY_DIGIT_1,
    Key.Digit2 -> KEY_DIGIT_2,
    Key.Digit3 -> KEY_DIGIT_3,
    Key.Digit4 -> KEY_DIGIT_4,
    Key.Digit5 -> KEY_DIGIT_5,
    Key.Digit6 -> KEY_DIGIT_6,
    Key.Digit7 -> KEY_DIGIT_7,
    Key.Digit8 -> KEY_DIGIT_8,
    Key.Digit9 -> KEY_DIGIT_9,
    Key.ArrowLeft -> KEY_ARROW_LEFT,
    Key.ArrowRight -> KEY_ARROW_RIGHT,
    Key.ArrowUp -> KEY_ARROW_UP,
    Key.ArrowDown -> KEY_ARROW_DOWN,
    Key.Escape -> KEY_ESCAPE,
    Key.Enter -> KEY_ENTER,
    Key.Space -> KEY_SPACE,
    Key.Backspace -> KEY_BACKSPACE,
    Key.Tab -> KEY_TAB,
    Key.Shift -> KEY_SHIFT,
    Key.Control -> KEY_CONTROL,
    Key.Option -> KEY_OPTION,
    Key.Command -> KEY_COMMAND,
    Key.F1 -> KEY_F1,
    Key.F2 -> KEY_F2,
    Key.F3 -> KEY_F3,
    Key.F4 -> KEY_F4,
    Key.F5 -> KEY_F5,
    Key.F6 -> KEY_F6,
    Key.F7 -> KEY_F7,
    Key.F8 -> KEY_F8,
    Key.F9 -> KEY_F9,
    Key.F10 -> KEY_F10,
    Key.F11 -> KEY_F11,
    Key.F12 -> KEY_F12,
    _ -> KEY_UNKNOWN,
  }
}

export function keyFromCode(code: int): Key {
  return case code {
    KEY_A -> Key.A,
    KEY_B -> Key.B,
    KEY_C -> Key.C,
    KEY_D -> Key.D,
    KEY_E -> Key.E,
    KEY_F -> Key.F,
    KEY_G -> Key.G,
    KEY_H -> Key.H,
    KEY_I -> Key.I,
    KEY_J -> Key.J,
    KEY_K -> Key.K,
    KEY_L -> Key.L,
    KEY_M -> Key.M,
    KEY_N -> Key.N,
    KEY_O -> Key.O,
    KEY_P -> Key.P,
    KEY_Q -> Key.Q,
    KEY_R -> Key.R,
    KEY_S -> Key.S,
    KEY_T -> Key.T,
    KEY_U -> Key.U,
    KEY_V -> Key.V,
    KEY_W -> Key.W,
    KEY_X -> Key.X,
    KEY_Y -> Key.Y,
    KEY_Z -> Key.Z,
    KEY_DIGIT_0 -> Key.Digit0,
    KEY_DIGIT_1 -> Key.Digit1,
    KEY_DIGIT_2 -> Key.Digit2,
    KEY_DIGIT_3 -> Key.Digit3,
    KEY_DIGIT_4 -> Key.Digit4,
    KEY_DIGIT_5 -> Key.Digit5,
    KEY_DIGIT_6 -> Key.Digit6,
    KEY_DIGIT_7 -> Key.Digit7,
    KEY_DIGIT_8 -> Key.Digit8,
    KEY_DIGIT_9 -> Key.Digit9,
    KEY_ARROW_LEFT -> Key.ArrowLeft,
    KEY_ARROW_RIGHT -> Key.ArrowRight,
    KEY_ARROW_UP -> Key.ArrowUp,
    KEY_ARROW_DOWN -> Key.ArrowDown,
    KEY_ESCAPE -> Key.Escape,
    KEY_ENTER -> Key.Enter,
    KEY_SPACE -> Key.Space,
    KEY_BACKSPACE -> Key.Backspace,
    KEY_TAB -> Key.Tab,
    KEY_SHIFT -> Key.Shift,
    KEY_CONTROL -> Key.Control,
    KEY_OPTION -> Key.Option,
    KEY_COMMAND -> Key.Command,
    KEY_F1 -> Key.F1,
    KEY_F2 -> Key.F2,
    KEY_F3 -> Key.F3,
    KEY_F4 -> Key.F4,
    KEY_F5 -> Key.F5,
    KEY_F6 -> Key.F6,
    KEY_F7 -> Key.F7,
    KEY_F8 -> Key.F8,
    KEY_F9 -> Key.F9,
    KEY_F10 -> Key.F10,
    KEY_F11 -> Key.F11,
    KEY_F12 -> Key.F12,
    _ -> Key.Unknown,
  }
}
