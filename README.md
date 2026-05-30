# std/game

`std/game` provides a macOS-first full-screen game/app host with a Metal-backed
surface, neutral key and mouse events, queryable input state, and a small
native-backed render pass API with static simple meshes and batched texture-quad
drawing.

This first version is intentionally small: it owns the AppKit window, input
delivery, frame callbacks, Metal surface lifetime, render pass setup, and a
basic static mesh and texture-quad batch primitives. Drawing code can also build
on the Metal handles exposed by `RenderPass` and `GameSurface`.

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
  GameSurface,
  Key,
  Point3,
  RenderPassDescriptor,
  SimpleMesh,
  SimpleMeshBuilder,
  drawSimpleMesh,
  initGameApp,
} from "std/game"
import { Duration } from "std/time"

function createMesh(surface: GameSurface): SimpleMesh {
  builder := SimpleMeshBuilder.create()
  builder.quad{
    a: Point3.xyz(80.0, 80.0, 0.0),
    b: Point3.xyz(300.0, 80.0, 0.0),
    c: Point3.xyz(300.0, 220.0, 0.0),
    d: Point3.xyz(80.0, 220.0, 0.0),
    color: Color.rgb(0.9, 0.2, 0.1),
  }
  return builder.build(surface)
}

function main(): int {
  app := initGameApp{ title: "Doof Game" }
  mesh := createMesh(app.surface)

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
        drawSimpleMesh(pass, mesh)
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
`rotationX(...)`, `rotationY(...)`, `rotationZ(...)`, `orthographic(...)`,
`perspective(...)`, `multiply(...)`, and `transformPoint(...)`. Static mesh
drawing applies the active pass camera and model matrix on the GPU.

### Static Simple Meshes

```doof
builder := SimpleMeshBuilder.create()
i0 := builder.vertex{ position: Point3.xyz(-0.5, -0.5, 0.0), color: Color.rgb(0.0, 0.7, 1.0) }
i1 := builder.vertex{ position: Point3.xyz(0.5, -0.5, 0.0), color: Color.rgb(0.0, 0.7, 1.0) }
i2 := builder.vertex{ position: Point3.xyz(0.0, 0.5, 0.0), color: Color.rgb(0.0, 0.7, 1.0) }
builder.triangle(i0, i1, i2)

mesh := builder.build(app.surface)

renderer.pass(
  RenderPassDescriptor {
    camera: Camera.perspective(1.0471975512, 16.0 / 9.0, 0.1, 100.0),
    clear: Clear.colorDepth(Color.black(), 1.0),
    depth: Depth.readWrite(),
    blend: Blend.opaque(),
  },
  (pass): void => {
    drawSimpleMesh(pass, mesh, Mat4.rotationY(angle))
  },
)
```

`SimpleMeshBuilder` collects vertices, triangles, and quads during setup, then
`build(surface)` uploads them into Metal buffers for that surface's device.
Vertices carry position, color, UV, and normal data. `drawSimpleMesh(...)` uses
one indexed Metal draw for the whole mesh with simple built-in directional
lighting, while `drawTexturedSimpleMesh(...)` samples a `Texture` using the
mesh UVs before applying the same lighting.

### Textures And Atlases

```doof
loadedTexture := try! app.loadTexture("/path/to/card_atlas.png")
atlas := Atlas { texture: loadedTexture, columns: 14, rows: 4 }

builder := TextureQuadBatchBuilder.forAtlas(atlas)
builder.addAtlasCell(atlas, 0, 0, Rect.xywh(80.0, 90.0, 121.0, 176.0))
builder.addAtlasCell(atlas, 10, 1, Rect.xywh(220.0, 90.0, 121.0, 176.0))
batch := try! builder.build(app.surface)

renderer.pass(
  RenderPassDescriptor {
    clear: Clear.colorDepth(Color.black(), 1.0),
    blend: Blend.alpha(),
  },
  (pass): void => {
    drawTextureQuadBatch(pass, batch)
  },
)
```

`initGameApp` creates the Metal device up front, so `app.loadTexture(path)` can
load textures during setup before `run()`. `Renderer.loadTexture(path)` remains
available as the same cached lookup for render-time convenience. Both decode and
upload only when the texture is not already alive for the current device.
`TextureQuadBatchBuilder` records destination/source rectangles during setup,
then `drawTextureQuadBatch(...)` draws every quad in that batch with one Metal
draw call. Use it for sprites, cards, tile strips, and other repeated quads that
share one texture.

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

- `samples/minimal` draws a screen-space simple mesh.
- `samples/cards` draws textured atlas sprites with one texture-quad batch draw.
- `samples/cube` draws a timer-driven spinning cube with one static simple mesh.
