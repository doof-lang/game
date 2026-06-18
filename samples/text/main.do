import {
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  GameEventKind,
  Key,
  Point,
  RenderPassDescriptor,
  TextAlign,
  TextLayoutOptions,
  createTextModel,
  drawSimpleModel,
  initGameApp,
} from "std/game"

function main(): int {
  app := initGameApp{ title: "Doof Game Text" }

  font := app.loadBitmapFont("fonts/DejaVuSans.fnt") else error {
    println(error)
    return 1
  }

  title := createTextModel(
    app.surface,
    font,
    "Bitmap Font Text",
    TextLayoutOptions {
      position: Point(48.0, 44.0),
      color: Color(0.96, 0.88, 0.35),
    },
  )

  leftLabel := createTextModel(
    app.surface,
    font,
    "Left aligned text uses the font atlas glyphs and kerning: AVA WAVE.",
    TextLayoutOptions {
      position: Point(48.0, 120.0),
      maxWidth: 460.0,
      lineSpacing: 8.0,
      color: Color(0.88, 0.95, 1.0),
    },
  )

  centerLabel := createTextModel(
    app.surface,
    font,
    "Center aligned wrapping\nfor HUD labels and menus",
    TextLayoutOptions {
      position: Point(560.0, 128.0),
      maxWidth: 420.0,
      align: TextAlign.Center,
      lineSpacing: 10.0,
      color: Color(0.64, 1.0, 0.74),
    },
  )

  rightLabel := createTextModel(
    app.surface,
    font,
    "Right aligned score\n0123456789",
    TextLayoutOptions {
      position: Point(560.0, 286.0),
      maxWidth: 420.0,
      align: TextAlign.Right,
      lineSpacing: 8.0,
      color: Color(1.0, 0.70, 0.58),
    },
  )

  app.key(Key.Escape).onPressed((): void => app.stop())

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }
  })

  app.onRender((renderer): void => {
    renderer.pass(
      RenderPassDescriptor {
        camera: Camera.screen(),
        clear: Clear.colorDepth(Color(0.012, 0.016, 0.024), 1.0),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      },
      (pass): void => {
        drawSimpleModel(pass, title)
        drawSimpleModel(pass, leftLabel)
        drawSimpleModel(pass, centerLabel)
        drawSimpleModel(pass, rightLabel)
      },
    )
  })

  result := app.run()
  case result {
    s: Success -> return 0
    f: Failure -> {
      println(f.error)
      return 1
    }
  }
}
