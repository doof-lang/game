import { GameEvent } from "./event"
import { InputState } from "./input"
import { BitmapFont } from "./text"
import { GameEventKind, MouseButton } from "./types"
import { Point, Point3, Rect, RenderPass } from "./render"
import { GameSurface } from "./surface"
import { Transform } from "./transform"
import {
  UiButton,
  UiButtonEntry,
  UiElement,
  UiLabel,
  UiLabelEntry,
  UiPanel,
  UiPanelEntry,
} from "./ui_controls"
import { drawUiButton, drawUiLabel, drawUiPanel } from "./ui_draw"
import {
  UiButtonStyle,
  UiCallback,
  UiElementKind,
  UiHit,
  UiPanelStyle,
  UiStyle,
  rectContains,
} from "./ui_types"

export {
  UiButtonStyle,
  UiCallback,
  UiElementKind,
  UiHit,
  UiPanelStyle,
  UiStyle,
  rectContains,
} from "./ui_types"
export { UiButton, UiLabel, UiPanel } from "./ui_controls"

export class UiLayer {
  surface: GameSurface | null
  font: BitmapFont
  transform: Transform = Transform.identity()

  private elements: UiElement[] = []
  private panels: UiPanelEntry[] = []
  private labels: UiLabelEntry[] = []
  private buttons: UiButtonEntry[] = []
  private nextId: int = 1
  private pressedButtonId: int = 0

  setTransform(transform: Transform): UiLayer {
    this.transform = transform
    return this
  }

  addPanel(bounds: Rect, style: UiPanelStyle): UiPanel {
    element := addElement(UiElementKind.Panel, bounds)
    panel := UiPanel {
      element,
      style,
    }
    panels.push(UiPanelEntry { element, panel })
    return panel
  }

  addLabel(text: string, bounds: Rect, style: UiStyle): UiLabel {
    element := addElement(UiElementKind.Label, bounds)
    label := UiLabel {
      element,
      text,
      style,
    }
    labels.push(UiLabelEntry { element, label })
    return label
  }

  addButton(
    text: string,
    bounds: Rect,
    style: UiButtonStyle,
    onClick: UiCallback,
  ): UiButton {
    element := addElement(UiElementKind.Button, bounds)
    button := UiButton {
      element,
      text,
      style,
      onClick,
    }
    buttons.push(UiButtonEntry { element, button })
    return button
  }

  hitTest(point: Point): UiHit | null {
    local := screenToUi(point)
    for index of 0..<elements.length {
      element := elements[elements.length - index - 1]
      if element.visible && rectContains(element.bounds, local) {
        return UiHit {
          id: element.id,
          kind: element.kind,
          point: local,
          bounds: element.bounds,
        }
      }
    }
    return null
  }

  updatePointer(input: InputState): void {
    handlePointerMove(Point(input.mouseX(), input.mouseY()))
  }

  handleEvent(event: GameEvent): void {
    kind := event.kind()
    point := Point(event.x(), event.y())

    if kind == GameEventKind.MouseMove {
      handlePointerMove(point)
      return
    }

    if kind == GameEventKind.MouseDown && isPrimaryButton(event.mouseButton()) {
      handlePointerDown(point)
      return
    }

    if kind == GameEventKind.MouseUp && isPrimaryButton(event.mouseButton()) {
      handlePointerUp(point)
      return
    }

    if kind == GameEventKind.DoubleTap {
      handlePointerTap(point)
    }
  }

  handlePointerMove(point: Point): void {
    local := screenToUi(point)
    for entry of buttons {
      button := entry.button
      inside := entry.element.visible && button.enabled && rectContains(entry.element.bounds, local)
      button.hovered = inside
      if button.pressed {
        button.pressedInside = inside
      }
    }
  }

  handlePointerDown(point: Point): void {
    local := screenToUi(point)
    pressedButtonId = 0
    clearPressed()

    button := topmostButtonAt(local)
    if button == null {
      handlePointerMove(point)
      return
    }

    target := button!
    target.hovered = true
    target.pressed = true
    target.pressedInside = true
    pressedButtonId = target.id()
  }

  handlePointerUp(point: Point): void {
    local := screenToUi(point)
    clicked := topmostButtonAt(local)
    let clickedButton: UiButton | null = null

    if clicked != null && pressedButtonId != 0 && clicked!.id() == pressedButtonId && clicked!.pressedInside {
      clickedButton = clicked
    }

    clearPressed()
    pressedButtonId = 0
    updateHoverFromLocal(local)

    if clickedButton != null {
      clickedButton!.onClick.call()
    }
  }

  handlePointerTap(point: Point): void {
    local := screenToUi(point)
    button := topmostButtonAt(local)
    if button != null {
      button!.onClick.call()
    }
    updateHoverFromLocal(local)
  }

  draw(pass: RenderPass): void {
    localSurface := surface else {
      panic("UiLayer.draw requires a GameSurface")
    }
    model := transform.toMat4()

    for element of elements {
      if !element.visible {
        continue
      }

      if element.kind == UiElementKind.Panel {
        panel := panelForElement(element.id) else {
          continue
        }
        drawUiPanel(localSurface, pass, panel, model)
        continue
      }

      if element.kind == UiElementKind.Button {
        button := buttonForElement(element.id) else {
          continue
        }
        drawUiButton(localSurface, font, pass, button, model)
        continue
      }

      label := labelForElement(element.id) else {
        continue
      }
      drawUiLabel(localSurface, font, pass, label, model)
    }
  }

  private addElement(kind: UiElementKind, bounds: Rect): UiElement {
    element := UiElement {
      id: nextId,
      kind,
      bounds,
    }
    nextId += 1
    elements.push(element)
    return element
  }

  private screenToUi(point: Point): Point {
    transformed := transform.toInverseMat4().transformPoint(Point3(point.x, point.y, 0.0))
    return Point(transformed.x, transformed.y)
  }

  private updateHoverFromLocal(local: Point): void {
    for entry of buttons {
      button := entry.button
      button.hovered = entry.element.visible && button.enabled && rectContains(entry.element.bounds, local)
    }
  }

  private clearPressed(): void {
    for entry of buttons {
      entry.button.pressed = false
      entry.button.pressedInside = false
    }
  }

  private topmostButtonAt(local: Point): UiButton | null {
    for index of 0..<elements.length {
      element := elements[elements.length - index - 1]
      if element.kind != UiElementKind.Button || !element.visible || !rectContains(element.bounds, local) {
        continue
      }

      button := buttonForElement(element.id) else {
        continue
      }
      if button.enabled {
        return button
      }
    }
    return null
  }

  private panelForElement(id: int): UiPanel | null {
    for entry of panels {
      if entry.element.id == id {
        return entry.panel
      }
    }
    return null
  }

  private labelForElement(id: int): UiLabel | null {
    for entry of labels {
      if entry.element.id == id {
        return entry.label
      }
    }
    return null
  }

  private buttonForElement(id: int): UiButton | null {
    for entry of buttons {
      if entry.element.id == id {
        return entry.button
      }
    }
    return null
  }
}

export function createTestUiLayer(font: BitmapFont): UiLayer {
  return UiLayer {
    surface: null,
    font,
  }
}

function isPrimaryButton(button: MouseButton): bool {
  return button == MouseButton.Left || button == MouseButton.Other
}
