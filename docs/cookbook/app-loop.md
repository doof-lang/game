# App Loop

Use this pattern when starting a new `std/game` program.

## Minimal Continuous App

Continuous rendering is the default. It calls `onRender` on each display tick.

```doof
import {
  Clear,
  Color,
  GameEventKind,
  Key,
  RenderPassDescriptor,
  initGameApp,
} from "std/game"

function main(): int {
  app := initGameApp{ title: "My Game" }

  app.key(Key.Escape).onPressed() {
    app.stop()
  }

  app.onEvent() {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }
  }

  app.onRender() {
    renderer.pass({
      clear: Clear.colorDepth(Color(0.02, 0.03, 0.04), 1.0),
    }) {
      // Draw here.
    }
  }

  app.run() else error {
    println(error)
    return 1
  }
  return 0
}
```

See [`samples/minimal`](../../samples/minimal).

## Requested Rendering

Requested rendering is a better fit for retained UI, editors, board games, and
menus. It only redraws when the app asks for another frame.

```doof
import {
  GameEventKind,
  GameRenderMode,
  initGameApp,
} from "std/game"

function main(): int {
  app := initGameApp{ title: "Tool", renderMode: GameRenderMode.Requested }

  app.onEvent() {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    } else if event.kind() == GameEventKind.Resized {
      app.requestRender()
    }
  }

  app.onRender() {
    // Redraw the current state.
  }

  app.requestRender()
  app.run() else error {
    println(error)
    return 1
  }
  return 0
}
```

Call `app.requestRender()` after input handlers, timers, network messages, or
state transitions that should become visible.

## Windowed macOS Apps

The macOS host defaults to full-screen. Use `GameWindowMode.Windowed` for a
normal resizable window.

```doof
app := initGameApp{
  title: "Board Game",
  renderMode: GameRenderMode.Requested,
  options: GameAppOptions {
    windowMode: GameWindowMode.Windowed,
    windowWidth: 1280,
    windowHeight: 900,
  },
}
```

## Resource Lifetime

Create Metal-backed resources with `app.surface`. Meshes, textures, bitmap
fonts, shader pipelines, and generated text models are tied to the current
surface/device.

Most small apps create those resources before `app.run()`. If your app needs to
rebuild size-dependent resources after a resize, listen for
`GameEventKind.Resized`, rebuild the resources, then request a render.
