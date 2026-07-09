# Rendering

Rendering happens inside `app.onRender`. Start one or more passes with
`renderer.pass(...)`, then call draw helpers inside the pass callback.

## Draw Screen-Space Geometry

`Camera.screen()` maps logical coordinates to the surface with `(0, 0)` at the
top-left. It is the right choice for HUDs, 2D boards, menus, and sprites.

```doof
builder := SimpleMeshBuilder()
builder.quad{
  a: Point3(80.0, 80.0, 0.0),
  b: Point3(320.0, 80.0, 0.0),
  c: Point3(320.0, 220.0, 0.0),
  d: Point3(80.0, 220.0, 0.0),
  color: Color(0.9, 0.2, 0.1),
}
mesh := builder.build(app.surface)

app.onRender() {
  renderer.pass({
    camera: Camera.screen(),
    clear: Clear.colorDepth(Color(0.02, 0.03, 0.04), 1.0),
    depth: Depth.disabled(),
    blend: Blend.alpha(),
  }) {
    drawSimpleMesh(pass, mesh)
  }
}
```

See [`samples/minimal`](../../samples/minimal).

## Draw A Moving 3D Model

Use a perspective camera, enable depth, and draw a `SimpleModel` with a
transform.

```doof
model := SimpleModel(mesh)
camera := Camera.perspective(1.0471975512, 0.1, 100.0)
  .withPosition(Point3(0.0, 0.0, 5.0))

app.onRender() {
  model.setTransform(
    Transform.identity()
      .rotatedLocalBy(Rotation.y(angleDegrees))
      .rotatedLocalBy(Rotation.x(angleDegrees * 0.62)),
  )

  renderer.pass({
    camera,
    clear: Clear.colorDepth(Color(0.018, 0.022, 0.030), 1.0),
    depth: Depth.readWrite(),
    blend: Blend.opaque(),
  }) {
    drawSimpleModel(pass, model)
  }
}
```

See [`samples/cube`](../../samples/cube).

## Pick Clear, Depth, And Blend Settings

Use these common combinations:

| Goal | Clear | Depth | Blend |
| --- | --- | --- | --- |
| 2D UI or HUD | `Clear.colorDepth(...)` | `Depth.disabled()` | `Blend.alpha()` |
| Opaque 3D scene | `Clear.colorDepth(...)` | `Depth.readWrite()` | `Blend.opaque()` |
| Overlay pass | `Clear.none()` | `Depth.disabled()` | `Blend.alpha()` |

`Blend` is selected on the pass because built-in helpers choose compatible
Metal pipeline state when drawing.

## Use Surface Dimensions

Use logical dimensions for layout and pointer alignment:

```doof
width := app.surface.width()
height := app.surface.height()
center := Point3(width * 0.5, height * 0.5, 0.0)
```

Use pixel dimensions only when talking to low-level native code or custom Metal
resources:

```doof
pixelWidth := app.surface.pixelWidth()
pixelHeight := app.surface.pixelHeight()
scale := app.surface.scale()
```
