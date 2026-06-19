# std/game

`std/game` provides a macOS-first full-screen game/app host with a Metal-backed
surface, neutral key and mouse events, queryable input state, and a small
native-backed render pass API with static simple meshes and batched texture-quad
drawing. It also includes a reusable native-backed `Sound` object for file and
generated audio playback, plus a compact sfxr/bfxr-inspired synth for game sound
effects.

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

  app.key(Key.Escape).onPressed() {
    app.stop()
  }

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
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

### Sound Effects

```doof
import { SfxrSoundConfig, SoundPlayOptions, synthSound } from "std/game"

pickup := try! synthSound(SfxrSoundConfig.pickup())
laser := try! synthSound(SfxrSoundConfig.laser())
musicSting := try! app.loadSound("audio/sting.wav")

try! pickup.play()
try! laser.play(SoundPlayOptions { volume: 0.35, pan: -0.25 })
try! musicSting.play(SoundPlayOptions { volume: 0.8 })
```

`Sound.load(path)` and `loadSound(path)` decode platform-supported audio files
such as WAV, MP3, AAC, and CAF into a reusable sound object. `Sound.play(...)`
starts playback immediately; repeated calls can overlap, which keeps one-shot
effects simple. `Sound.stop()` stops active voices for that sound, `duration()`
reports seconds, and `isPlaying()` reports whether any voices are still active.

`SfxrSoundConfig` generates short mono effects in Doof and feeds them through
the same `Sound` playback path. Use the presets (`pickup`, `laser`,
`explosion`, `jump`, and `hit`) as starting points, or adjust waveform,
frequency slide, envelope, vibrato, duty sweep, and simple low/high-pass filter
settings directly before calling `synthSound(config)` or
`generateSoundSamples(config)`.

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
screenCamera := Camera.screen()
worldCamera := Camera.orthographic(-400.0, 400.0, -225.0, 225.0, -10.0, 10.0)
projection := Camera.perspective(1.0471975512, 16.0 / 9.0, 0.1, 100.0)
camera := projection.withPosition(Point3(0.0, 0.0, 6.0))
```

`Camera.screen()` keeps the built-in helpers in logical screen coordinates with
`(0, 0)` at the top-left of the surface and `(surface.width(), surface.height())`
at the bottom-right. `Camera.identity()` treats positions as clip space.
`Camera.orthographic(...)` accepts explicit world bounds, and
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

### Bitmap Font Text

```doof
font := try! app.loadIntrinsicFont()
label := createTextModel(
  app.surface,
  font,
  "Score 1200",
  TextLayoutOptions {
    position: Point(24.0, 32.0),
    maxWidth: 320.0,
    align: TextAlign.Left,
  },
)

renderer.pass(
  RenderPassDescriptor {
    camera: Camera.screen(),
    blend: Blend.alpha(),
  },
  (pass): void => {
    drawSimpleModel(pass, label)
  },
)
```

`app.loadIntrinsicFont()` creates the small font embedded in `std/game`, so
basic text and UI need no external font assets. Its compressed BMFont metrics
and packed 4-bit alpha atlas add about 15 KB to the module.

For a custom font, use `app.loadBitmapFont("fonts/hud.fnt")`. It reads AngelCode
BMFont text `.fnt` metrics and loads its referenced single-page bitmap atlas
relative to the font file.

The returned `BitmapFont` owns that texture. `createTextMeshSpec(...)`, `createTextMesh(...)`, and
`createTextModel(...)` lay out text in logical screen coordinates for
`Camera.screen()`, including newlines, kerning, optional word wrapping, letter
spacing, left/center/right alignment, and UTF-8 text. Unicode codepoints use the
matching BMFont glyph when present and otherwise use `fallbackCodepoint`. Spaces
advance the cursor but do not emit glyph quads, and the generated UVs target the
supplied font texture.

### Retained UI

```doof
ui := UiLayer(app)

ui.addPanel(
  Rect(16.0, 16.0, 300.0, 128.0),
  UiPanelStyle {
    background: Color(0.05, 0.06, 0.08, 0.92),
    border: Color(0.45, 0.55, 0.65, 1.0),
  },
)

status := ui.addLabel(
  "Ready",
  Rect(24.0, 24.0, 260.0, 40.0),
  UiStyle {
    textColor: Color(0.95, 0.88, 0.35, 1.0),
  },
)

ui.addButton(
  "Start",
  Rect(24.0, 80.0, 160.0, 44.0),
  UiButtonStyle {},
  (): void => {
    status.setText("Started")
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
      depth: Depth.disabled(),
      blend: Blend.alpha(),
    },
    (pass): void => {
      ui.draw(pass)
    },
  )
})
```

`UiLayer` is a small retained UI container for panels, labels, and buttons.
Bounds are in UI-local top-left coordinates, and `setTransform(...)` maps that
UI space into the screen-space render pass. Constructing `UiLayer(app)`
lets the layer create the primary screen pointer and request renders when
pointer interaction changes visual state. Pointer positions are mapped back
through the inverse transform for hit testing, so hover, press, and click
behavior stays aligned with rendering. Hit
testing walks last-added elements first, making later elements topmost. Label
and button styles default `font` to `null`, which uses the embedded intrinsic
font. Set `font` to a loaded `BitmapFont` for custom typography; one layer can
mix text atlases when needed.

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
width(): double
height(): double
pixelWidth(): int
pixelHeight(): int
scale(): double
metalDeviceHandle(): long
metalCommandQueueHandle(): long
metalLayerHandle(): long
```

`width()` and `height()` report logical screen dimensions, adjusted by the
surface scale, and are the natural units for `Camera.screen()`, text, UI, mouse,
and touch coordinates. `pixelWidth()` and `pixelHeight()` report the physical
drawable dimensions for native interop and pixel-sized render resources.

The `long` Metal handles are pointer values for native renderer code. They are
macOS/Metal-specific in this version.

### `GameEvent`

Events expose `kind()`, `key()`, `mouseButton()`, `controller()`, position,
movement, pan, scroll, magnify, and resize data.

On macOS, two-finger trackpad movement is reported as `Pan` with `panDeltaX()`
and `panDeltaY()`. Mouse-wheel movement is reported separately as `Scroll` with
`scrollDeltaX()` and `scrollDeltaY()`, so apps can give it different semantics.
Trackpad pinch and iOS pinch are reported as `Magnify` events with relative zoom
in `magnificationDelta()`. Magnify events may also carry pan deltas when the
gesture midpoint moves.

### `InputState`

```doof
isKeyDown(key: Key): bool
isMouseButtonDown(button: MouseButton): bool
mouseX(): double
mouseY(): double
mouseDeltaX(): double
mouseDeltaY(): double
panDeltaX(): double
panDeltaY(): double
scrollDeltaX(): double
scrollDeltaY(): double
magnificationDelta(): double
controllers(): ControllerQuery
isControllerConnected(slot: ControllerSlot): bool
isControllerButtonDown(slot: ControllerSlot, button: ControllerButton): bool
controllerAxis(slot: ControllerSlot, axis: ControllerAxis): double
```

Mouse, pan, scroll, and magnification deltas are frame-relative. Key and button
state persists while the key/button is held. Controller slots are stable while a
controller remains connected and are named `One` through `Four`.

### `InputButton`

```doof
jump := app.key(Key.Space)
jump.onPressed((): void => playJumpSound())

shoot := app.mouseButton(MouseButton.Left)
shoot.onPressed((): void => fireLaser())

if jump.pressed() {
  println("jump held")
}
```

`InputButton` represents a binary input source. `pressed()` reports whether the
button is currently held, and `released()` reports whether it is currently up.
`onPressed(...)` and `onReleased(...)` fire only on edge transitions. Use
`InputButton.any(...)` to combine multiple source buttons into one logical
action; the composite is pressed while any source is pressed and releases only
after all sources are up. Use `app.mouseButton(...)` for specific mouse-button
behavior such as firing, alternate mouse modes, or device-specific
interactions. Use `app.screenPointer()` for primary screen pointer
interactions that should work across mouse and touch.

### Controllers

```doof
move := app.controllerStick(.One, .Left).withDeadzone(0.2)
jump := app.controllerButton(.One, .South)
lookX := app.controllerAxis(.One, .RightX).withDeadzone(0.15)

jump.onPressed((): void => playJumpSound())

app.onEvent((event): void => {
  if event.kind() == GameEventKind.ControllerConnected {
    println("controller ${event.controller().name()} connected")
  }
})
```

Controller face buttons use compass-position names so code is not tied to a
specific controller label set: `South`, `East`, `West`, and `North`.
`InputAxis` and `InputStick` expose raw values by default and provide opt-in
helpers such as `withDeadzone(...)`, `inverted()`, `clamped(...)`, and
`invertedY()`. Use `app.input.controllers().connected(slot)` or
`app.input.isControllerConnected(slot)` to check availability.

### `ScreenPointer`

```doof
pointer := app.screenPointer()
pointer.onPressed((point): void => beginDrag(point.x, point.y))
pointer.onMoved((point): void => updateHover(point.x, point.y))
pointer.onReleased((point): void => endDrag(point.x, point.y))

if pointer.pressed() {
  println("pointer at ${pointer.x()}, ${pointer.y()}")
}
```

`ScreenPointer` represents the primary screen pointer. On macOS it is backed by
the primary mouse button, and on iOS it is backed by the current single-touch
translation used by the native game host. It exposes screen-space coordinates,
held/released state, and edge/move callbacks. `UiLayer.registerPointer(...)`
wires a retained UI layer directly to a pointer for custom setups. The usual UI
path is `UiLayer(app)`, which creates the pointer and requests renders for
pointer-driven visual changes.

`GameApp.onEvent(...)` does not deliver key down/up or mouse button down/up
events. Use `app.key(...)`, `app.mouseButton(...)`, and
`app.controllerButton(...)` for binary input events, use `app.screenPointer()`
for primary screen pointer movement and edges, use `app.gestures()` for pan,
scroll, magnify, and double tap, and keep `onEvent(...)` for close, resize,
controller availability, compatibility, and other app events.

### `ScreenGestures`

```doof
gestures := app.gestures()
gestures.onPan((gesture): void => panCamera(gesture.deltaX, gesture.deltaY))
gestures.onScroll((gesture): void => zoomAt(gesture.point, gesture.deltaY))
gestures.onMagnify((gesture): void => pinchZoom(gesture.point, gesture.magnificationDelta))
gestures.onDoubleTap((gesture): void => toggleZoomAt(gesture.point))
```

`ScreenGestures` represents non-binary viewport interactions. Pan and scroll
gestures expose screen-space `point`, `deltaX`, and `deltaY`. Magnify gestures
also expose `magnificationDelta`, and may carry pan deltas when the pinch
midpoint moves. Double tap is routed here as an app-level gesture rather than a
primary pointer click.

### App-Declared Pan Gestures

Applications can opt a pointer drag into pan semantics when hit-testing shows
the drag belongs to the background, map, board, or other pannable surface:

```doof
app.beginPanGesture(x, y)
app.updatePanGesture(x, y)
app.endPanGesture()
app.cancelPanGesture()
```

`updatePanGesture` emits ordinary `Pan` events with `panDeltaX()` and
`panDeltaY()`. `endPanGesture` starts damped inertial pan events when the release
velocity is high enough. Use `cancelPanGesture` when the interaction changes to
something non-panning, such as dragging an object or starting a pinch.

## Notes

- V1 is macOS-only.
- The surface is explicitly Metal-backed.
- `std/game` depends on `std/event` for host-loop integration.

## Samples

- `samples/minimal` draws a screen-space simple mesh.
- `samples/cards` draws textured atlas cards with one simple-model batch draw.
- `samples/cube` draws a timer-driven spinning cube with one static simple mesh.
- `samples/sound` plays five generated game effects with keyboard-triggered
  volume and stereo pan options.
- `samples/controller` demonstrates connection events, face buttons, a
  deadzoned movement stick, and an analog trigger.
- `samples/text` contrasts the intrinsic font with a loaded handwriting BMFont,
  and demonstrates wrapping, line spacing, and alignment.
- `samples/skymap` draws an equirectangular panorama, a textured sphere planet,
  and a loaded OBJ mesh while mouse movement steers the camera.
