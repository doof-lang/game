# Retained UI

Use `UiLayer` for panels, labels, and buttons that should keep their own
layout and hit testing. This is useful for tools, menus, settings screens, and
HUD overlays.

## Create A Layer

```doof
app := initGameApp{ title: "UI", renderMode: GameRenderMode.Requested }
ui := UiLayer(app)

ui.addPanel(Rect(0.0, 0.0, 420.0, 240.0), {
  background: Color(0.05, 0.06, 0.08, 0.94),
  border: Color(0.58, 0.70, 0.82, 1.0),
  borderWidth: 2.0,
})

label := ui.addLabel("Ready", Rect(24.0, 24.0, 300.0, 36.0), {
  textColor: Color.white,
  paddingX: 0.0,
  paddingY: 0.0,
})
```

## Add A Button

```doof
buttonStyle := UiButtonStyle{
  background: Color(0.18, 0.25, 0.30, 1.0),
  hoverBackground: Color(0.24, 0.36, 0.42, 1.0),
  pressedBackground: Color(0.10, 0.18, 0.23, 1.0),
  textColor: Color.white,
}

ui.addButton("Click", Rect(24.0, 168.0, 160.0, 42.0), buttonStyle) {
  label.setText("Clicked")
  app.requestRender()
}
```

In requested render mode, request a render after UI callbacks mutate visible
state.

## Draw The UI

```doof
app.onRender() {
  renderer.pass({
    camera: Camera.screen(),
    clear: Clear.colorDepth(Color(0.012, 0.015, 0.019), 1.0),
    depth: Depth.disabled(),
    blend: Blend.alpha(),
  }) {
    ui.draw(pass)
  }
}
```

## Responsive Panels

Build panels in local coordinates, then transform the whole layer based on the
surface size.

```doof
scale := app.surface.height() * 0.5 / 540.0
x := (app.surface.width() - 640.0 * scale) * 0.5
y := (app.surface.height() - 540.0 * scale) * 0.5

ui.setTransform(
  Transform.identity()
    .withPosition(Point3(x, y, 0.0))
    .withScale(Vec3.xyz(scale, scale, 1.0)),
)
```

See [`samples/ui`](../../samples/ui).
