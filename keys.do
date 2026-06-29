import { Key } from "./types"

readonly KEY_UNKNOWN = 0
readonly KEY_A = 1
readonly KEY_B = 2
readonly KEY_C = 3
readonly KEY_D = 4
readonly KEY_E = 5
readonly KEY_F = 6
readonly KEY_G = 7
readonly KEY_H = 8
readonly KEY_I = 9
readonly KEY_J = 10
readonly KEY_K = 11
readonly KEY_L = 12
readonly KEY_M = 13
readonly KEY_N = 14
readonly KEY_O = 15
readonly KEY_P = 16
readonly KEY_Q = 17
readonly KEY_R = 18
readonly KEY_S = 19
readonly KEY_T = 20
readonly KEY_U = 21
readonly KEY_V = 22
readonly KEY_W = 23
readonly KEY_X = 24
readonly KEY_Y = 25
readonly KEY_Z = 26
readonly KEY_DIGIT_0 = 27
readonly KEY_DIGIT_1 = 28
readonly KEY_DIGIT_2 = 29
readonly KEY_DIGIT_3 = 30
readonly KEY_DIGIT_4 = 31
readonly KEY_DIGIT_5 = 32
readonly KEY_DIGIT_6 = 33
readonly KEY_DIGIT_7 = 34
readonly KEY_DIGIT_8 = 35
readonly KEY_DIGIT_9 = 36
readonly KEY_ARROW_LEFT = 37
readonly KEY_ARROW_RIGHT = 38
readonly KEY_ARROW_UP = 39
readonly KEY_ARROW_DOWN = 40
readonly KEY_ESCAPE = 41
readonly KEY_ENTER = 42
readonly KEY_SPACE = 43
readonly KEY_BACKSPACE = 44
readonly KEY_TAB = 45
readonly KEY_SHIFT = 46
readonly KEY_CONTROL = 47
readonly KEY_OPTION = 48
readonly KEY_COMMAND = 49
readonly KEY_F1 = 50
readonly KEY_F2 = 51
readonly KEY_F3 = 52
readonly KEY_F4 = 53
readonly KEY_F5 = 54
readonly KEY_F6 = 55
readonly KEY_F7 = 56
readonly KEY_F8 = 57
readonly KEY_F9 = 58
readonly KEY_F10 = 59
readonly KEY_F11 = 60
readonly KEY_F12 = 61

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
