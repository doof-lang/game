import {
  BitmapFont,
  Color,
  Rect,
  TextLayoutOptions,
  UiButton,
  UiButtonStyle,
  UiLabel,
  UiPanel,
  UiStyle,
  measureText,
} from "std/game"
import {
  LayoutConstraints,
  LayoutNode,
  LayoutPlacement,
  LayoutRect,
  LayoutSize,
  LayoutStyle,
} from "std/layout"

export function measuredLabelNode(font: BitmapFont, text: string): LayoutNode {
  return LayoutNode {
    style: LayoutStyle { shrink: 0.0, alignSelf: .Center },
    measure: (constraints: LayoutConstraints): LayoutSize => {
      measured := measureText(font, text, TextLayoutOptions {
        maxWidth: constraints.maxWidth ?? 0.0,
      })
      return LayoutSize { width: measured.width, height: measured.height }
    },
  }
}

export function toGameRect(bounds: LayoutRect): Rect {
  return Rect(bounds.x, bounds.y, bounds.width, bounds.height)
}

export function bindPanel(node: LayoutNode, panel: UiPanel): none {
  node.onPlace = (placement: LayoutPlacement): none => {
    panel.setBounds(toGameRect(placement.bounds))
    panel.setVisible(placement.visibleBounds != none)
  }
}

export function bindClippedPanel(node: LayoutNode, panel: UiPanel): none {
  node.onPlace = (placement: LayoutPlacement): none => {
    if placement.visibleBounds == none {
      panel.setVisible(false)
    } else {
      panel.setBounds(toGameRect(placement.visibleBounds!))
      panel.setVisible(true)
    }
  }
}

export function bindLabel(node: LayoutNode, label: UiLabel, requireFull: bool = false): none {
  node.onPlace = (placement: LayoutPlacement): none => {
    visible := placement.visibleBounds
    fullyVisible := visible != none
      && visible!.width >= placement.bounds.width - 0.01
      && visible!.height >= placement.bounds.height - 0.01
    label.setBounds(toGameRect(placement.bounds))
    label.setVisible(if requireFull then fullyVisible else visible != none)
  }
}

export function bindButton(node: LayoutNode, button: UiButton): none {
  node.onPlace = (placement: LayoutPlacement): none => {
    button.setBounds(toGameRect(placement.bounds))
    button.setVisible(placement.visibleBounds != none)
  }
}

export function labelStyle(color: Color): UiStyle {
  return UiStyle { textColor: color, paddingX: 0.0, paddingY: 0.0 }
}

export function buttonStyle(): UiButtonStyle {
  return UiButtonStyle {
    background: Color(0.13, 0.28, 0.38, 1.0),
    hoverBackground: Color(0.18, 0.42, 0.55, 1.0),
    pressedBackground: Color(0.08, 0.20, 0.28, 1.0),
    textColor: Color(0.92, 0.98, 1.0, 1.0),
  }
}
