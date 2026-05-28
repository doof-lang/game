# std/game

`std/game` provides a macOS-first full-screen game/app host with a Metal-backed
surface, neutral key and mouse events, queryable input state, and a small
native-backed render pass API.

This first version is intentionally small: it owns the AppKit window, input
delivery, frame callbacks, Metal surface lifetime, and render pass setup, but it
does not provide portable drawing primitives. Drawing code can build on the
Metal handles exposed by `RenderPass` and `GameSurface`.

## Usage

```doof
import { setInterval } from "std/event"
import {
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  GameEventKind,
  Key,
  Mat4,
  Point3,
  Rect,
  RenderPassDescriptor,
  drawAtlasCell,
  drawRect,
  drawTriangle3,
  initGameApp,
} from "std/game"
import { Duration } from "std/time"

function main(): int {
  app := initGameApp{ title: "Doof Game" }

  simulationTimer := setInterval{
    interval: Duration.ofMillis(16L),
    handler: (): void => {
      input := app.input
      if input.isKeyDown(Key.Space) {
        println("space held")
      }
      app.requestRender()
    },
  }

  heartbeatTimer := setInterval{
    interval: Duration.ofMillis(250L),
    handler: (): void => {
      println("heartbeat")
    },
  }

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.KeyDown && event.key() == Key.Escape {
      app.stop()
    }
  })

  app.onRender((renderer): void => {
    renderer.pass(
      RenderPassDescriptor {
        camera: Camera.screen(),
        clear: Clear.colorDepth(Color.rgb(0.02, 0.03, 0.04), 1.0),
        depth: Depth.readWrite(),
        blend: Blend.opaque(),
      },
      (pass): void => {
        drawRect(pass, Rect.xywh(80.0, 80.0, 220.0, 140.0), Color.rgb(0.9, 0.2, 0.1))
      },
    )
  })

  result := app.run()

  case result {
    s: Success -> return 0,
    f: Failure -> {
      println(f.error)
      return 1
    },
  }
}
```

## Exports

### `initGameApp{ ... }`

```doof
app := initGameApp{ title: "Game" }

app.onEvent((event: GameEvent): void => {})
app.onRender((renderer: Renderer): void => {})

result := app.run()
```

Creates a full-screen macOS app host. Register event and render callbacks, set
up any `std/event` timers or channels, then call `run()`. The host drains
`std/event` work during wakeups, so `setInterval` can drive simulation or
slower heartbeat loops while rendering remains owned by the game host.

Use `app.input` to query the latest input state from timer callbacks. Call
`app.requestRender()` after simulation or state changes to schedule `onRender`
on the next display tick. During render callbacks, `app.surface` holds the
current Metal-backed surface and the callback receives a `Renderer` for issuing
render passes. `app.fps()` reports the recent completed render callback rate.
Call `app.stop()` to exit the native app loop.

### `Renderer`

```doof
renderer.pass(
  RenderPassDescriptor {
    camera: Camera.screen(),
    clear: Clear.colorDepth(Color.black(), 1.0),
    depth: Depth.readWrite(),
    blend: Blend.opaque(),
  },
  (pass): void => {
    encoder := pass.metalRenderCommandEncoderHandle()
  },
)
```

Each `onRender` callback owns one native Metal frame. `renderer.pass(...)`
creates one render command encoder, applies clear and depth state, invokes the
callback, ends the encoder, and commits the frame after `onRender` returns.
`Blend` is captured on the pass for draw helpers; Metal applies blending through
render pipeline state, so actual mesh/sprite helpers will use it when they
create pipelines.

`RenderPassDescriptor` defaults to the current window surface,
`Camera.screen()`, `Clear.none()`, `Depth.disabled()`, and `Blend.opaque()`.
Offscreen render targets are reserved for a later version.

### Cameras And Matrices

```doof
pixelCamera := Camera.screen()
worldCamera := Camera.orthographic(-400.0, 400.0, -225.0, 225.0, -10.0, 10.0)
projection := Camera.perspective(1.0471975512, 16.0 / 9.0, 0.1, 100.0)
camera := projection.withView(Mat4.translation(0.0, 0.0, -6.0))
```

`Camera.screen()` keeps the built-in helpers in pixel coordinates with `(0, 0)`
at the top-left of the surface. `Camera.identity()` treats positions as clip
space. `Camera.orthographic(...)` accepts explicit world bounds, and
`Camera.perspective(...)` builds a right-handed perspective projection suitable
for objects in front of the camera on negative Z. Use `withView(...)` to combine
a projection camera with a view matrix.

`Mat4` includes `identity()`, `translation(...)`, `scale(...)`,
`orthographic(...)`, `perspective(...)`, `multiply(...)`, and
`transformPoint(...)`. The draw helpers apply the active pass camera before
sending vertices to Metal.

### Simple Drawing

```doof
drawRect(pass, Rect.xywh(80.0, 80.0, 220.0, 140.0), Color.rgb(0.9, 0.2, 0.1))

drawTriangle(
  pass,
  Point.xy(360.0, 80.0),
  Point.xy(500.0, 260.0),
  Point.xy(220.0, 260.0),
  Color.rgba(0.2, 0.7, 1.0, 0.65),
)

drawTriangle3(
  pass,
  Point3.xyz(-0.5, -0.5, -2.0),
  Point3.xyz(0.5, -0.5, -2.0),
  Point3.xyz(0.0, 0.5, -2.0),
  Color.white(),
)
```

The built-in helpers draw filled screen-space shapes in pixels, with `(0, 0)` at
the top-left of the surface when using `Camera.screen()`. With orthographic or
perspective cameras, the same helpers draw in camera world space. They are
intended as an immediate end-to-end smoke path and a foundation for richer
free-function draw helpers.

### Textures And Atlases

```doof
loaded := app.loadTexture("/path/to/card_atlas.png")
case loaded {
  s: Success -> {
    atlas := Atlas { texture: s.value, columns: 14, rows: 4 }
    drawAtlasCell(pass, atlas, 0, 0, Rect.xywh(80.0, 90.0, 121.0, 176.0))
  }
  f: Failure -> println(f.error)
}
```

`initGameApp` creates the Metal device up front, so `app.loadTexture(path)` can
load textures during setup before `run()`. `Renderer.loadTexture(path)` remains
available as the same cached lookup for render-time convenience. Both decode and
upload only when the texture is not already alive for the current device.
`drawTexture(...)` draws a source rectangle from a texture, and
`drawAtlasCell(...)` addresses a fixed-grid atlas by column and row.

### `GameSurface`

```doof
pixelWidth(): int
pixelHeight(): int
scale(): double
metalDeviceHandle(): long
metalCommandQueueHandle(): long
metalLayerHandle(): long
```

The `long` Metal handles are pointer values for native renderer code. They are
macOS/Metal-specific in this version.

### `GameEvent`

Events expose `kind()`, `key()`, `mouseButton()`, position, movement, wheel, and
resize data.

### `InputState`

```doof
isKeyDown(key: Key): bool
isMouseButtonDown(button: MouseButton): bool
mouseX(): double
mouseY(): double
mouseDeltaX(): double
mouseDeltaY(): double
wheelDeltaX(): double
wheelDeltaY(): double
```

Mouse and wheel deltas are frame-relative. Key and button state persists while
the key/button is held.

## Notes

- V1 is macOS-only.
- The surface is explicitly Metal-backed.
- `std/game` depends on `std/event` for host-loop integration.

## Samples

- `samples/minimal` draws a screen-space rectangle.
- `samples/cards` draws textured atlas sprites.
- `samples/cube` draws a timer-driven spinning cube with `Camera.perspective(...)`.
