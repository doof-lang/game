import { GameApp } from "./app"
import { GameEvent } from "./event"
import { InputState } from "./input"
import { loadIntrinsicBitmapFontForSurface } from "./intrinsic_font"
import { ScreenPointer } from "./screen_pointer"
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
  surface: GameSurface | none
  let transform: Transform = Transform.identity()

  private elements: UiElement[] = []
  private panels: UiPanelEntry[] = []
  private labels: UiLabelEntry[] = []
  private buttons: UiButtonEntry[] = []
  private let nextId: int = 1
  private let pressedButtonId: int = 0
  private let pointerRenderVersion: int = 0
  private let intrinsicFont: BitmapFont | none = none

  static constructor(target: GameApp | GameSurface | none): UiLayer {
    app := target as GameApp else {
      surface := target as GameSurface else {
        return UiLayer {
          surface: none,
        }
      }
      return UiLayer {
        surface,
      }
    }

    layer := UiLayer {
      surface: app.surface,
    }
    layer.registerApp(app)
    return layer
  }

  setTransform(transform: Transform): UiLayer {
    this.transform = transform
    return this
  }

  registerPointer(pointer: ScreenPointer): UiLayer {
    pointer.onMoved((point): none => handlePointerMove(point))
    pointer.onPressed((point): none => handlePointerDown(point))
    pointer.onReleased((point): none => handlePointerUp(point))
    return this
  }

  registerApp(app: GameApp): UiLayer {
    pointer := app.screenPointer()
    pointer.onMoved((point): none => {
      before := pointerRenderVersion
      handlePointerMove(point)
      requestAppRenderIfPointerChanged(app, before)
    })
    pointer.onPressed((point): none => {
      before := pointerRenderVersion
      handlePointerDown(point)
      requestAppRenderIfPointerChanged(app, before)
    })
    pointer.onReleased((point): none => {
      before := pointerRenderVersion
      handlePointerUp(point)
      requestAppRenderIfPointerChanged(app, before)
    })
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

  hitTest(point: Point): UiHit | none {
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
    return none
  }

  updatePointer(input: InputState): none {
    handlePointerMove(Point(input.mouseX(), input.mouseY()))
  }

  handleEvent(event: GameEvent): none {
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

  handlePointerMove(point: Point): none {
    local := screenToUi(point)
    for entry of buttons {
      button := entry.button
      inside := entry.element.visible && button.enabled && rectContains(entry.element.bounds, local)
      setButtonHovered(button, inside)
      if button.pressed {
        setButtonPressedInside(button, inside)
      }
    }
  }

  handlePointerDown(point: Point): none {
    local := screenToUi(point)
    pressedButtonId = 0
    clearPressed()

    button := topmostButtonAt(local)
    if button == none {
      handlePointerMove(point)
      return
    }

    target := button!
    setButtonHovered(target, true)
    setButtonPressed(target, true)
    setButtonPressedInside(target, true)
    pressedButtonId = target.id()
  }

  handlePointerUp(point: Point): none {
    local := screenToUi(point)
    clicked := topmostButtonAt(local)
    let clickedButton: UiButton | none = none

    if clicked != none && pressedButtonId != 0 && clicked!.id() == pressedButtonId && clicked!.pressedInside {
      clickedButton = clicked
    }

    clearPressed()
    pressedButtonId = 0
    updateHoverFromLocal(local)

    if clickedButton != none {
      clickedButton!.onClick.call()
    }
  }

  handlePointerTap(point: Point): none {
    local := screenToUi(point)
    button := topmostButtonAt(local)
    if button != none {
      button!.onClick.call()
    }
    updateHoverFromLocal(local)
  }

  draw(pass: RenderPass): none {
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
        font := resolveFont(localSurface, button.style.font)
        drawUiButton(localSurface, pass, button, font, model)
        continue
      }

      label := labelForElement(element.id) else {
        continue
      }
      font := resolveFont(localSurface, label.style.font)
      drawUiLabel(localSurface, pass, label, font, model)
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

  private resolveFont(surface: GameSurface, font: BitmapFont | none): BitmapFont {
    if font != none {
      return font!
    }
    if intrinsicFont != none {
      return intrinsicFont!
    }

    loaded := loadIntrinsicBitmapFontForSurface(surface) else error {
      panic("failed to load intrinsic UI font: ${error}")
    }
    intrinsicFont = loaded
    return loaded
  }

  private screenToUi(point: Point): Point {
    transformed := transform.toInverseMat4().transformPoint(Point3(point.x, point.y, 0.0))
    return Point(transformed.x, transformed.y)
  }

  private updateHoverFromLocal(local: Point): none {
    for entry of buttons {
      button := entry.button
      setButtonHovered(button, entry.element.visible && button.enabled && rectContains(entry.element.bounds, local))
    }
  }

  private clearPressed(): none {
    for entry of buttons {
      setButtonPressed(entry.button, false)
      setButtonPressedInside(entry.button, false)
    }
  }

  private setButtonHovered(button: UiButton, hovered: bool): none {
    if button.hovered == hovered {
      return
    }
    button.hovered = hovered
    pointerRenderVersion += 1
  }

  private setButtonPressed(button: UiButton, pressed: bool): none {
    if button.pressed == pressed {
      return
    }
    button.pressed = pressed
    pointerRenderVersion += 1
  }

  private setButtonPressedInside(button: UiButton, pressedInside: bool): none {
    if button.pressedInside == pressedInside {
      return
    }
    button.pressedInside = pressedInside
    pointerRenderVersion += 1
  }

  private requestAppRenderIfPointerChanged(app: GameApp, before: int): none {
    if pointerRenderVersion != before {
      app.requestRender()
    }
  }

  private topmostButtonAt(local: Point): UiButton | none {
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
    return none
  }

  private panelForElement(id: int): UiPanel | none {
    for entry of panels {
      if entry.element.id == id {
        return entry.panel
      }
    }
    return none
  }

  private labelForElement(id: int): UiLabel | none {
    for entry of labels {
      if entry.element.id == id {
        return entry.label
      }
    }
    return none
  }

  private buttonForElement(id: int): UiButton | none {
    for entry of buttons {
      if entry.element.id == id {
        return entry.button
      }
    }
    return none
  }
}

export function createTestUiLayer(): UiLayer {
  return UiLayer(none)
}

function isPrimaryButton(button: MouseButton): bool {
  return button == MouseButton.Left || button == MouseButton.Other
}
