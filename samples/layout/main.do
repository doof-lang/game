import {
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  GameAppOptions,
  GameEventKind,
  GameRenderMode,
  GameWindowMode,
  Key,
  Point,
  RenderPassDescriptor,
  initGameApp,
  loadIntrinsicBitmapFontForSurface,
} from "std/game"

import { createLayoutDemo } from "./layout_demo"

function main(): int {
  app := initGameApp{
    title: "Doof Flex Layout",
    renderMode: GameRenderMode.Continuous,
    options: GameAppOptions {
      windowMode: GameWindowMode.Windowed,
      windowWidth: 1100,
      windowHeight: 720,
    },
  }
  font := try! loadIntrinsicBitmapFontForSurface(app.surface)
  demo := createLayoutDemo(app, font)
  demo.reflow(app.surface)

  app.key(Key.Escape).onPressed() { app.stop() }
  app.key(Key.ArrowUp).onPressed() {
    demo.scrollPage(-1.0)
  }
  app.key(Key.ArrowDown).onPressed() {
    demo.scrollPage(1.0)
  }

  app.onEvent() {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    } else if event.kind() == GameEventKind.Resized {
      demo.reflow(app.surface)
    }
  }

  app.onRender() {
    scrollDelta := app.input.scrollDeltaY()
    pointer := Point(app.input.mouseX(), app.input.mouseY())
    if scrollDelta != 0.0 && demo.containsScroller(pointer) {
      demo.scrollBy(scrollDelta)
    }

    renderer.pass(RenderPassDescriptor {
      camera: Camera.screen(),
      clear: Clear.colorDepth(Color(0.018, 0.022, 0.030, 1.0), 1.0),
      depth: Depth.disabled(),
      blend: Blend.alpha(),
    }) {
      demo.ui.draw(pass)
    }
  }

  app.run() else error {
    println(error)
    return 1
  }
  return 0
}
