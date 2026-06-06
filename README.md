# std/game

`std/game` provides a macOS-first full-screen game/app host with a Metal-backed
surface, neutral key and mouse events, queryable input state, and a small
native-backed render pass API with static simple meshes and batched texture-quad
drawing.

This first version is intentionally small: it owns the native app surface, input
delivery, frame callbacks, Metal surface lifetime, render pass setup, and basic
static mesh and texture-quad batch primitives. Drawing code can also build on
the Metal handles exposed by `RenderPass` and `GameSurface`.

The native host supports macOS and Doof's built-in `ios-app` target. iOS apps
attach the same Metal-backed surface to the generated UIKit app shell; single
touch input is reported through the existing mouse event and mouse button APIs.
Hardware keyboard events are not exposed on iOS yet.

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
    a: Point3(80.0, 80.0, 0.0),
    b: Point3(300.0, 80.0, 0.0),
    c: Point3(300.0, 220.0, 0.0),
    d: Point3(80.0, 220.0, 0.0),
    color: Color(0.9, 0.2, 0.1),
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
        clear: Clear.colorDepth(Color(0.02, 0.03, 0.04), 1.0),
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

### iOS Builds

Projects that depend on `std/game` can be built for iOS with Doof's existing app
target support. For example, to build the jigsaw sample for the simulator:

```bash
doof build --target ios-app --ios-destination simulator game/samples/jigsaw
```

To install and launch on a booted simulator, use `doof run` with the same target
and destination:

```bash
doof run --target ios-app --ios-destination simulator game/samples/jigsaw
```

Device builds use the same `ios-app` target with `--ios-destination device` and
the standard Doof iOS signing options or environment variables for the signing
identity and provisioning profile.

### `Renderer`

```doof
renderer.pass(
  RenderPassDescriptor {
    camera: Camera.screen(),
    clear: Clear.colorDepth(Color.black(), 1.0),
    depth: Depth.readWrite(),
    blend: Blend.opaque(),
    winding: .CounterClockwise,
    cull: .Back,
  },
  (pass): void => {
    encoder := pass.metalRenderCommandEncoderHandle()
  },
)
```

Each `onRender` callback owns one native Metal frame. `renderer.pass(...)`
creates one render command encoder, applies clear, depth, winding, and cull
state, invokes the callback, ends the encoder, and commits the frame after
`onRender` returns. `Blend` is captured on the pass for draw helpers; Metal
applies blending through render pipeline state, so actual mesh/sprite helpers
will use it when they create pipelines.

`RenderPassDescriptor` defaults to the current window surface,
`Camera.screen()`, `Clear.none`, `Depth.disabled()`, `Blend.opaque()`,
`WindingMode.CounterClockwise`, and `CullMode.None`. Built-in 3D mesh generators use
counter-clockwise front faces. Offscreen render targets are reserved for a later
version.

### Cameras And Matrices

```doof
pixelCamera := Camera.screen()
worldCamera := Camera.orthographic(-400.0, 400.0, -225.0, 225.0, -10.0, 10.0)
projection := Camera.perspective(1.0471975512, 16.0 / 9.0, 0.1, 100.0)
camera := projection.withPosition(Point3(0.0, 0.0, 6.0))
```

`Camera.screen()` keeps the built-in helpers in pixel coordinates with `(0, 0)`
at the top-left of the surface. `Camera.identity()` treats positions as clip
space. `Camera.orthographic(...)` accepts explicit world bounds, and
`Camera.perspective(...)` builds a right-handed perspective projection suitable
for objects in front of the camera on negative Z. Cameras carry a world-space
`Transform`; use `withPosition(...)`, `movedLocalBy(...)`, `rotatedLocalY(...)`,
and related helpers to place the camera. Use `withView(...)` when you need to
combine a projection camera with an explicit view matrix.

`Mat4` includes `identity()`, `translation(...)`, `scale(...)`,
`rotationX(...)`, `rotationY(...)`, `rotationZ(...)`, `orthographic(...)`,
`perspective(...)`, `multiply(...)`, and `transformPoint(...)`. Static mesh
drawing applies the active pass camera and model matrix on the GPU.

### Static Simple Meshes

```doof
builder := SimpleMeshBuilder.create()
i0 := builder.vertex{ position: Point3(-0.5, -0.5, 0.0), color: Color(0.0, 0.7, 1.0) }
i1 := builder.vertex{ position: Point3(0.5, -0.5, 0.0), color: Color(0.0, 0.7, 1.0) }
i2 := builder.vertex{ position: Point3(0.0, 0.5, 0.0), color: Color(0.0, 0.7, 1.0) }
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
Vertices carry position, color, UV, and normal data. Triangles are emitted in
the order you provide; pass them counter-clockwise when viewed from the front to
match the default winding. `quad(...)` emits two counter-clockwise triangles for
the points `a`, `b`, `c`, `d`. `drawSimpleMesh(...)` uses one indexed Metal draw
for the whole mesh with simple built-in directional lighting, while
`drawTexturedSimpleMesh(...)` samples a `Texture` using the mesh UVs before
applying the same lighting.

### Sphere Meshes

```doof
texture := try! app.loadTexture("images/earth.png")
spec := createSphereMeshSpec{ radius: 1.0, tessellation: 32 }
planet := SimpleModel(SimpleMesh(app.surface, spec), texture)
```

`createSphereMeshSpec(...)` creates a UV sphere as a `SimpleMeshSpec`.
`tessellation` controls the number of latitude bands; longitude bands are
twice that count for equirectangular textures. The generated UVs use `(0, 0)`
at the top-left of the texture and duplicate the seam vertices so `u` wraps
cleanly from `1` to `0`.

### OBJ Meshes

```doof
spec := try! loadObjMeshSpec("models/ship.obj")
mesh := SimpleMesh(app.surface, spec)
```

`loadObjMeshSpec(path)` reads a Wavefront `.obj` file and converts its faces to
a `SimpleMeshSpec`. `parseObjMeshSpec(text, source)` provides the same parser
for in-memory OBJ text. The loader supports `v`, `vt`, `vn`, and polygonal `f`
records, including negative relative face indices. Polygons are triangulated
with a fan, and missing UVs or normals fall back to `(0, 0)` and generated face
normals.

### Textures And Atlases

```doof
loadedTexture := try! app.loadTexture("/path/to/card_atlas.png")
atlas := Atlas { texture: loadedTexture, columns: 14, rows: 4 }

cardMesh := SimpleMeshBuilder
  .create()
  .quad{
    a: Point3(0.0, 0.0, 0.0),
    b: Point3(121.0, 0.0, 0.0),
    c: Point3(121.0, 176.0, 0.0),
    d: Point3(0.0, 176.0, 0.0),
    color: Color.white,
    uvA: Point(0.0, 0.0),
    uvB: Point(1.0, 0.0),
    uvC: Point(1.0, 1.0),
    uvD: Point(0.0, 1.0),
  }
  .build(app.surface)

batch := SimpleModelBatch {
  surface: app.surface,
  mesh: cardMesh,
  texture: loadedTexture,
  capacity: 100,
}

tree := batch.add{
  transform: Transform.identity().withPosition(Point3(80.0, 90.0, 0.0)),
  tint: Color.white,
  uvOffset: Vec2.zero,
  uvScale: Vec2.xy(1.0 / 14.0, 1.0 / 4.0),
}
tree.moveWorldBy(Vec3.xyz(0.0, 1.0, 0.0))

renderer.pass(
  RenderPassDescriptor {
    clear: Clear.colorDepth(Color.black(), 1.0),
    blend: Blend.alpha(),
  },
  (pass): void => {
    drawSimpleModelBatch(pass, batch)
  },
)
```

`initGameApp` creates the Metal device up front, so `app.loadTexture(path)` can
load textures during setup before `run()`. `Renderer.loadTexture(path)` remains
available as the same cached lookup for render-time convenience. Both decode and
upload only when the texture is not already alive for the current device.
`SimpleModelBatch` stores repeated instances of one mesh and optional shared
texture, then `drawSimpleModelBatch(...)` draws the live instances with one Metal
instanced draw call. Instance handles update their batch slot through ergonomic
transform, tint, and UV helpers. Removing an instance keeps the live slots packed,
and later use of the removed handle is a programmer error.

### Equirectangular Sky Maps

```doof
texture := try! app.loadTexture("images/panorama.png")
skyMap := SkyMap { texture: texture }

renderer.pass(
  RenderPassDescriptor {
    camera: Camera
      .identity()
      .withRotation(Rotation.euler(yawDegrees, pitchDegrees, 0.0)),
    clear: Clear.color(Color.black),
    depth: Depth.disabled(),
    blend: Blend.opaque(),
  },
  (pass): void => {
    drawEquirectangularSkyMap(pass, skyMap, 1.0471975512, 1.0)
  },
)
```

`SkyMap` wraps a loaded 2D panorama texture and
`drawEquirectangularSkyMap(...)` draws it as a full-screen equirectangular
environment. The draw helper uses the active pass camera's rotation while
ignoring its position, because the sky is treated as infinitely far away. It
accepts vertical field of view and exposure. It is intended for sky/background
rendering, so draw it before opaque scene geometry when sharing a depth-enabled
pass. `app.loadTexture(...)` accepts Radiance `.hdr` RGBE files and uploads them
as float Metal textures, so HDRI panoramas can be used directly.

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
- `samples/cards` draws textured atlas cards with one simple-model batch draw.
- `samples/cube` draws a timer-driven spinning cube with one static simple mesh.
- `samples/skymap` draws an equirectangular panorama, a textured sphere planet,
  and a loaded OBJ mesh while mouse movement steers the camera.
