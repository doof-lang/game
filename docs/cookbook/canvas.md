# Immediate-Mode 2D With Canvas

Use `Canvas` when the screen is a picture of your game state — a board game,
an editor, a HUD — and it is simpler to draw everything each frame than to keep
a tree of widgets in step with the state. For a few fixed panels and buttons,
[`UiLayer`](ui.md) is enough.

## Set Up

```doof
app := initGameApp{
  title: "Board",
  options: GameAppOptions { windowMode: GameWindowMode.Windowed, windowWidth: 1400, windowHeight: 900 },
}
canvas := Canvas {}
body := canvas.font(app.loadBitmapFontResource("fonts/body.fnt")!, 40.0)
boardArt := canvas.register(app.loadTextureResource("board.png")!)
let at = Point(-1000.0, -1000.0)        // the pointer, in screen points
pointer := app.screenPointer()
pointer.onMoved((p): none => { at = p })
```

`font` takes the size the font was rasterised at (the `size` on the `info` line
of the .fnt file); text can then be drawn at any size.

## Draw A Frame

```doof
app.onRender((renderer): none => {
  surface := renderer.surface()
  renderer.pass(RenderPassDescriptor {
    camera: Camera.screen(),
    clear: Clear.color(Color(0.04, 0.04, 0.05)),
    blend: Blend.alpha(),
  }, (pass): none => {
    canvas.begin(pass)
    drawBoard(Rect(16.0, 16.0, surface.width() * 0.6, surface.height() - 32.0))
    drawPanel()
    canvas.end()
  })
})
```

## Fit A Board Image And Find What Is Under The Pointer

Draw the board in its own pixel coordinates inside a fitted transform:

```doof
readonly BOARD = Point(1343.0, 2000.0)

function drawBoard(area: Rect): none {
  canvas.push(CanvasTransform.fit(BOARD, area))
  canvas.image(boardArt, Rect(0.0, 0.0, BOARD.x, BOARD.y), Rect(0.0, 0.0, 1.0, 1.0))
  hover := canvas.toCanvas(at)          // pointer in board pixels
  for space of spaces {
    if space.rect.contains(hover) {
      canvas.stroke(space.rect, 12.0, 6.0, Color(1.0, 0.8, 0.2))
    }
    canvas.onClick(space.rect, (): none => moveTo(space))
  }
  canvas.pop()
}
```

Line widths and radii inside the transform are in board pixels too.

## Buttons, Dialogs And Clicks

Record a click target as each control is drawn, and use `hovering` (not
`r.contains(at)`) for hover highlights. Later targets are on top:

```doof
function button(r: Rect, label: string, action: (): none): none {
  hot := canvas.hovering(r, at)
  canvas.round(r, 8.0, if hot then Color(0.25, 0.27, 0.30) else Color(0.17, 0.18, 0.20))
  canvas.text(body, label, r.x, r.y + (r.height - 16.0) / 2.0, 16.0, Color.white, r.width, TextAlign.Center)
  canvas.onClick(r, action)
}
```

A dialog starts a modal layer before drawing itself. Nothing under it can be
clicked, clicks outside it are swallowed, and from the next frame `hovering`
is false for everything drawn before it:

```doof
if dialogOpen {
  canvas.modal()
  canvas.rect(Rect(0.0, 0.0, width, height), Color(0.0, 0.0, 0.0, 0.5))
  // ...draw the dialog and its buttons
}

if menuOpen {
  canvas.modal()
  canvas.onClick(Rect(0.0, 0.0, width, height), (): none => { menuOpen = false })  // click outside closes
  // ...draw the menu; its buttons are on top of the catch-all
}

pointer.onReleased((p): none => {
  if !canvas.click(p) {
    // Not on any control, and no dialog is up: handle the board.
  }
})
```

## Tooltips

Collect the tooltip while drawing and draw it last, so it sits on top:

```doof
size := Point(280.0, canvas.measure(body, tipText, 13.0, 260.0).height + 20.0)
box := placeTooltip(at, size, Rect(0.0, 0.0, width, height))
canvas.shadow(box, 8.0, 10.0, 0.6)
canvas.round(box, 8.0, Color(0.12, 0.12, 0.14))
canvas.paragraph(body, tipText, box.x + 10.0, box.y + 10.0, 13.0, Color.white, 260.0)
```

## Scrolling Lists

Draw a list from a row offset and move the offset with a `ScrollStepper`. It
moves one row per wheel notch, doesn't race on a trackpad, and follows the
platform's scroll direction (including natural scrolling). Wheels arrive
through `onScroll` and macOS trackpads through `onPan`, so listen to both:

```doof
stepper := ScrollStepper {}
scrollLog := (point: Point, rows: int): none => {
  if logRect.contains(point) {
    logScroll = scrollBy(logScroll, rows, log.length - visibleRows)
  }
}
app.gestures().onScroll((g): none => scrollLog(g.point, stepper.wheel(g.deltaY, app.seconds())))
app.gestures().onPan((g): none => scrollLog(g.point, stepper.swipe(g.deltaY, app.seconds())))
```

For a log anchored at the bottom, where the offset counts rows back from the
newest, subtract the rows instead.

## Meters And Timers

```doof
// A ring that fills clockwise from 12 o'clock.
canvas.ring(c, 20.0, 4.0, Color(1.0, 1.0, 1.0, 0.15))
canvas.arc(c, 20.0, 4.0, -PI / 2.0, -PI / 2.0 + 2.0 * PI * fraction, Color(0.4, 0.8, 0.5))
```
