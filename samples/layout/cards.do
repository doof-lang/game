import { BitmapFont, Color, Rect, UiLayer } from "std/game"
import { LayoutEdges, LayoutNode, LayoutStyle } from "std/layout"

import { bindClippedPanel, bindLabel, labelStyle, measuredLabelNode } from "./bindings"

export readonly CARD_HEIGHT = 72.0
export readonly CARD_GAP = 12.0
export readonly SCROLL_STEP = CARD_HEIGHT + CARD_GAP

export function createCardNodes(ui: UiLayer, font: BitmapFont): LayoutNode[] {
  titles := [
    "Measure intrinsic content",
    "Distribute free space",
    "Freeze at min / max",
    "Align on the cross axis",
    "Accumulate nested offsets",
    "Intersect axis clips",
    "Update final bounds",
    "Notify retained controls",
  ]
  details := [
    "Text callbacks receive content constraints.",
    "Grow factors share the remaining main axis.",
    "Constrained items freeze before redistribution.",
    "Containers stretch, center, start, or end children.",
    "Scroll transforms compose through the tree.",
    "Horizontal and vertical overflow stay independent.",
    "Scrolling places descendants immediately.",
    "Optional callbacks bridge existing UI objects.",
  ]
  nodes: LayoutNode[] := []

  for index of 0..<titles.length {
    panel := ui.addPanel(Rect(0.0, 0.0, 0.0, 0.0), {
      background: if index % 2 == 0
        then Color(0.105, 0.135, 0.175, 1.0)
        else Color(0.090, 0.115, 0.150, 1.0),
      border: Color(0.20, 0.31, 0.42, 1.0),
      borderWidth: 1.0,
    })
    title := ui.addLabel(titles[index], Rect(0.0, 0.0, 0.0, 0.0), labelStyle(Color(0.90, 0.95, 1.0, 1.0)))
    detail := ui.addLabel(details[index], Rect(0.0, 0.0, 0.0, 0.0), labelStyle(Color(0.62, 0.72, 0.82, 1.0)))
    titleNode := measuredLabelNode(font, titles[index])
    detailNode := measuredLabelNode(font, details[index])
    card := LayoutNode {
      style: LayoutStyle {
        height: CARD_HEIGHT,
        shrink: 0.0,
        direction: .Column,
        padding: LayoutEdges.symmetric{ horizontal: 14.0, vertical: 10.0 },
        gap: 3.0,
      },
      children: [titleNode, detailNode],
    }
    bindClippedPanel(card, panel)
    bindLabel(titleNode, title, true)
    bindLabel(detailNode, detail, true)
    nodes.push(card)
  }
  return nodes
}
