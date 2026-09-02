import {
  BitmapFont,
  Color,
  GameApp,
  GameSurface,
  Point,
  Rect,
  UiLabel,
  UiLayer,
  rectContains,
} from "std/game"
import {
  LayoutEdges,
  LayoutNode,
  LayoutRect,
  LayoutStyle,
  Overflow,
  layout,
} from "std/layout"

import {
  bindButton,
  bindLabel,
  bindPanel,
  buttonStyle,
  labelStyle,
  measuredLabelNode,
  toGameRect,
} from "./bindings"
import { CARD_GAP, SCROLL_STEP, createCardNodes } from "./cards"

export class LayoutDemo {
  ui: UiLayer
  root: LayoutNode
  scroller: LayoutNode
  status: UiLabel

  reflow(surface: GameSurface): none {
    layout(root, LayoutRect { width: surface.width(), height: surface.height() })
    updateStatus()
  }

  scrollBy(delta: double): none {
    scroller.scrollTo(0.0, scroller.scrollOffset().y + delta)
    updateStatus()
  }

  scrollPage(direction: double): none {
    scrollBy(direction * SCROLL_STEP)
  }

  containsScroller(point: Point): bool {
    return rectContains(toGameRect(scroller.bounds()), point)
  }

  private updateStatus(): none {
    maximum := scroller.scrollExtent().height - scroller.contentRect().height
    status.setText(`Scroll ${int(scroller.scrollOffset().y)} / ${int(maximum)}`)
  }
}

export function createLayoutDemo(app: GameApp, font: BitmapFont): LayoutDemo {
  ui := UiLayer(app)

  sidebarPanel := ui.addPanel(Rect(0.0, 0.0, 0.0, 0.0), {
    background: Color(0.055, 0.070, 0.095, 0.97),
    border: Color(0.18, 0.24, 0.32, 1.0),
    borderWidth: 1.0,
  })
  mainPanel := ui.addPanel(Rect(0.0, 0.0, 0.0, 0.0), {
    background: Color(0.075, 0.085, 0.105, 0.98),
    border: Color(0.20, 0.25, 0.32, 1.0),
    borderWidth: 1.0,
  })
  viewportPanel := ui.addPanel(Rect(0.0, 0.0, 0.0, 0.0), {
    background: Color(0.035, 0.042, 0.055, 1.0),
    border: Color(0.16, 0.21, 0.28, 1.0),
    borderWidth: 1.0,
  })

  sidebarTitle := ui.addLabel("DOOF / LAYOUT", Rect(0.0, 0.0, 0.0, 0.0), labelStyle(Color(0.42, 0.84, 1.0, 1.0)))
  sidebarBody := ui.addLabel(
    "A renderer-independent flex tree drives every rectangle in this screen.",
    Rect(0.0, 0.0, 0.0, 0.0),
    labelStyle(Color(0.70, 0.76, 0.84, 1.0)),
  )
  navLabels: UiLabel[] := []
  for text of ["Responsive row", "Nested columns", "Intrinsic text", "Live overflow"] {
    navLabels.push(ui.addLabel(text, Rect(0.0, 0.0, 0.0, 0.0), labelStyle(Color(0.84, 0.88, 0.94, 1.0))))
  }

  title := ui.addLabel("Layout activity", Rect(0.0, 0.0, 0.0, 0.0), labelStyle(Color(0.96, 0.97, 1.0, 1.0)))
  badge := ui.addLabel("FLEX", Rect(0.0, 0.0, 0.0, 0.0), labelStyle(Color(0.40, 0.90, 0.68, 1.0)))
  status := ui.addLabel("", Rect(0.0, 0.0, 0.0, 0.0), labelStyle(Color(0.62, 0.70, 0.80, 1.0)))

  cardNodes := createCardNodes(ui, font)

  upButton := ui.addButton("Previous", Rect(0.0, 0.0, 0.0, 0.0), buttonStyle(), (): none => {})
  downButton := ui.addButton("Next", Rect(0.0, 0.0, 0.0, 0.0), buttonStyle(), (): none => {})

  sidebarTitleNode := measuredLabelNode(font, sidebarTitle.text)
  sidebarBodyNode := LayoutNode {
    style: LayoutStyle { height: 80.0, shrink: 0.0 },
  }
  navNodes: LayoutNode[] := []
  for _ of navLabels {
    navNodes.push(LayoutNode { style: LayoutStyle { height: 34.0, shrink: 0.0 } })
  }
  sidebarChildren: LayoutNode[] := [sidebarTitleNode, sidebarBodyNode]
  for node of navNodes { sidebarChildren.push(node) }
  sidebar := LayoutNode {
    style: LayoutStyle {
      width: 230.0,
      shrink: 0.0,
      direction: .Column,
      padding: LayoutEdges.all(20.0),
      gap: 14.0,
    },
    children: sidebarChildren,
  }

  bindPanel(sidebar, sidebarPanel)
  bindLabel(sidebarTitleNode, sidebarTitle)
  bindLabel(sidebarBodyNode, sidebarBody)
  for index of 0..<navNodes.length { bindLabel(navNodes[index], navLabels[index]) }

  titleNode := measuredLabelNode(font, title.text)
  titleNode.style.grow = 1.0
  badgeNode := measuredLabelNode(font, badge.text)
  badgeNode.style.position = .Absolute
  badgeNode.style.right = 0.0
  badgeNode.style.top = 8.0
  header := LayoutNode {
    style: LayoutStyle { height: 36.0, shrink: 0.0, alignItems: .Center },
    children: [titleNode, badgeNode],
  }
  bindLabel(titleNode, title)
  bindLabel(badgeNode, badge)

  content := LayoutNode {
    style: LayoutStyle { direction: .Column, shrink: 0.0, gap: CARD_GAP },
    children: cardNodes,
  }
  scroller := LayoutNode {
    style: LayoutStyle {
      grow: 1.0,
      minHeight: 180.0,
      direction: .Column,
      padding: LayoutEdges.all(10.0),
      overflowX: Overflow.Clip,
      overflowY: Overflow.Scroll,
    },
    children: [content],
  }
  bindPanel(scroller, viewportPanel)

  statusNode := measuredLabelNode(font, "Scroll 000 / 000")
  statusNode.style.grow = 1.0
  upNode := LayoutNode { style: LayoutStyle { width: 112.0 } }
  downNode := LayoutNode { style: LayoutStyle { width: 112.0 } }
  controls := LayoutNode {
    style: LayoutStyle { height: 42.0, shrink: 0.0, gap: 10.0, alignItems: .Stretch },
    children: [statusNode, upNode, downNode],
  }
  bindLabel(statusNode, status)
  bindButton(upNode, upButton)
  bindButton(downNode, downButton)

  main := LayoutNode {
    style: LayoutStyle {
      grow: 1.0,
      minWidth: 360.0,
      direction: .Column,
      padding: LayoutEdges.all(20.0),
      gap: 16.0,
    },
    children: [header, scroller, controls],
  }
  bindPanel(main, mainPanel)

  root := LayoutNode {
    style: LayoutStyle { padding: LayoutEdges.all(24.0), gap: 20.0 },
    children: [sidebar, main],
  }
  demo := LayoutDemo { ui, root, scroller, status }
  upButton.setOnClick((): none => {
    demo.scrollPage(-1.0)
  })
  downButton.setOnClick((): none => {
    demo.scrollPage(1.0)
  })
  return demo
}
