# Text

`std/game` renders text with bitmap fonts. Use the embedded intrinsic font for
quick labels, or load an AngelCode BMFont file for custom typography.

## Intrinsic Font

```doof
font := app.loadIntrinsicFont() else error {
  println(error)
  return 1
}

title := createTextModel(
  app.surface,
  font,
  "Score 000120",
  TextLayoutOptions {
    position: Point(48.0, 44.0),
    color: Color(0.96, 0.88, 0.35),
  },
)
```

Draw text models like other simple models:

```doof
renderer.pass({
  camera: Camera.screen(),
  depth: Depth.disabled(),
  blend: Blend.alpha(),
}) {
  drawSimpleModel(pass, title)
}
```

## Custom Bitmap Font

Put the `.fnt` file and page image in your package resources, then load it from
the package resource path.

```doof
font := app.loadBitmapFontResource("fonts/handwriting.fnt") else error {
  println(error)
  return 1
}
```

See [`samples/text`](../../samples/text).

## Wrapping And Alignment

```doof
label := createTextModel(
  app.surface,
  font,
  "Center aligned wrapping for menus and HUD labels.",
  TextLayoutOptions {
    position: Point(560.0, 128.0),
    maxWidth: 420.0,
    align: TextAlign.Center,
    lineSpacing: 10.0,
    color: Color(0.64, 1.0, 0.74),
  },
)
```

Use `TextAlign.Left`, `TextAlign.Center`, or `TextAlign.Right`.

## Measuring Text

Use `measureText` before creating a model when layout needs the final bounds.

```doof
bounds := measureText(
  font,
  "Play",
  TextLayoutOptions { maxWidth: 240.0 },
)
```
