import { TextAlign } from "./text"
import { Color, Rect } from "./render"
import { UiButtonStyle, UiCallback, UiElementKind, UiPanelStyle, UiStyle } from "./ui_types"

export class UiElement {
  id: int
  kind: UiElementKind
  bounds: Rect
  visible: bool = true
}

export class UiPanel {
  element: UiElement
  style: UiPanelStyle

  id(): int => element.id
  bounds(): Rect => element.bounds
  isVisible(): bool => element.visible

  setBounds(bounds: Rect): UiPanel {
    element.bounds = bounds
    return this
  }

  setVisible(visible: bool): UiPanel {
    element.visible = visible
    return this
  }
}

export class UiLabel {
  element: UiElement
  text: string
  style: UiStyle

  id(): int => element.id
  bounds(): Rect => element.bounds
  isVisible(): bool => element.visible

  setText(text: string): UiLabel {
    this.text = text
    return this
  }

  setBounds(bounds: Rect): UiLabel {
    element.bounds = bounds
    return this
  }

  setVisible(visible: bool): UiLabel {
    element.visible = visible
    return this
  }

  setColor(color: Color): UiLabel {
    style.textColor = color
    return this
  }

  setAlign(align: TextAlign): UiLabel {
    style.align = align
    return this
  }
}

export class UiButton {
  element: UiElement
  text: string
  style: UiButtonStyle
  enabled: bool = true
  hovered: bool = false
  pressed: bool = false
  pressedInside: bool = false
  onClick: UiCallback

  id(): int => element.id
  bounds(): Rect => element.bounds
  isVisible(): bool => element.visible
  isHovered(): bool => hovered
  isPressed(): bool => pressed

  setText(text: string): UiButton {
    this.text = text
    return this
  }

  setBounds(bounds: Rect): UiButton {
    element.bounds = bounds
    return this
  }

  setVisible(visible: bool): UiButton {
    element.visible = visible
    return this
  }

  setEnabled(enabled: bool): UiButton {
    this.enabled = enabled
    if !enabled {
      hovered = false
      pressed = false
      pressedInside = false
    }
    return this
  }

  setOnClick(onClick: UiCallback): UiButton {
    this.onClick = onClick
    return this
  }
}

export class UiPanelEntry {
  element: UiElement
  panel: UiPanel
}

export class UiLabelEntry {
  element: UiElement
  label: UiLabel
}

export class UiButtonEntry {
  element: UiElement
  button: UiButton
}
