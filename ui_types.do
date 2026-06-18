import { BitmapFont, TextAlign } from "./text"
import { Color, Point, Rect } from "./render"

export type UiCallback = (): void

export enum UiElementKind {
  Panel,
  Label,
  Button,
}

export class UiPanelStyle {
  background: Color = Color(0.055, 0.065, 0.080, 0.90)
  border: Color = Color(0.42, 0.50, 0.60, 1.0)
  borderWidth: double = 2.0
  z: double = 0.0
}

export class UiStyle {
  font: BitmapFont
  textColor: Color = Color(1.0, 1.0, 1.0, 1.0)
  paddingX: double = 12.0
  paddingY: double = 8.0
  z: double = 0.0
  align: TextAlign = TextAlign.Left
  lineSpacing: double = 0.0
}

export class UiButtonStyle {
  font: BitmapFont
  background: Color = Color(0.16, 0.18, 0.22, 1.0)
  hoverBackground: Color = Color(0.22, 0.25, 0.30, 1.0)
  pressedBackground: Color = Color(0.10, 0.12, 0.16, 1.0)
  disabledBackground: Color = Color(0.10, 0.10, 0.11, 0.72)
  textColor: Color = Color(1.0, 1.0, 1.0, 1.0)
  disabledTextColor: Color = Color(0.62, 0.64, 0.68, 1.0)
  paddingX: double = 14.0
  paddingY: double = 8.0
  z: double = 0.0
  align: TextAlign = TextAlign.Center
}

export class UiHit {
  readonly id: int
  readonly kind: UiElementKind
  readonly point: Point
  readonly bounds: Rect
}

export function rectContains(rect: Rect, point: Point): bool {
  return point.x >= rect.x &&
    point.y >= rect.y &&
    point.x <= rect.x + rect.width &&
    point.y <= rect.y + rect.height
}
