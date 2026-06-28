# std/game Guide And API Reference

`std/game` provides a Metal-backed game and app host for macOS, with support
for Doof's `ios-app` target. It owns the native app loop, surface lifetime,
frame callbacks, input state, rendering passes, basic meshes, textures, bitmap
text, retained UI controls, controller input, screen gestures, and reusable
sound playback.

The public API is exported from [`index.do`](../index.do). Complete programs
are available in [`samples/`](../samples/).

Run the module tests with:

```bash
doof test game
```

## Quick Start

Create the app, build resources for `app.surface`, register callbacks, and call
`run()`.

```doof
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
        clear: Clear.colorDepth(Color(0.02, 0.03, 0.04), 1.0),
        depth: Depth.readWrite(),
        blend: Blend.opaque(),
      },
      (pass): void => drawSimpleMesh(pass, mesh),
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

## Mental Model

- The `GameApp` owns the native app loop and a current `GameSurface`.
- Resources that depend on the Metal device, such as textures, meshes, fonts,
  shader buffers, and shader pipelines, are created for a `GameSurface`.
- `onRender` receives a `Renderer`. Use it to begin one or more render passes.
- Built-in draw helpers use the active pass camera and blend/depth state.
- Event callbacks deliver app-level events. Binary input edges are modeled with
  `InputButton`, and current state is queried through `app.input`.
- `GameRenderMode.Continuous` redraws each display tick. `Requested` redraws
  after `app.requestRender()`.

## Samples

| Sample | Shows |
| --- | --- |
| [`samples/minimal`](../samples/minimal) | App startup and a screen-space mesh |
| [`samples/cube`](../samples/cube) | A timer-driven 3D cube |
| [`samples/text`](../samples/text) | Intrinsic and custom bitmap fonts |
| [`samples/ui`](../samples/ui) | Retained UI panels, labels, and buttons |
| [`samples/sound`](../samples/sound) | Generated sound effects and playback options |
| [`samples/controller`](../samples/controller) | Gamepad connection, buttons, sticks, and triggers |
| [`samples/cards`](../samples/cards) | Texture atlases and instanced model batches |
| [`samples/skymap`](../samples/skymap) | Sky maps, spheres, OBJ meshes, and camera steering |
| [`samples/asteroids-shader`](../samples/asteroids-shader) | Custom Metal shaders and instanced buffers |
| [`samples/jigsaw`](../samples/jigsaw) | A larger app with UI, input, rendering, and storage |

## App Host

### `initGameApp`

```doof
app := initGameApp{ title: "Game" }
tools := initGameApp{ title: "Tools", renderMode: GameRenderMode.Requested }
windowed := initGameApp{
  title: "Board Game",
  renderMode: GameRenderMode.Requested,
  options: GameAppOptions {
    windowMode: GameWindowMode.Windowed,
    windowWidth: 1280,
    windowHeight: 900,
  },
}
```

Creates a `GameApp`. The default render mode is
`GameRenderMode.Continuous`. In requested mode, call `app.requestRender()` after
state changes. The macOS host defaults to full-screen. Use
`GameWindowMode.Windowed` with `windowWidth` and `windowHeight` to create a
normal resizable window.

### `GameApp`

| Member | Description |
| --- | --- |
| `title: string` | Native app title. |
| `renderMode: GameRenderMode` | Continuous or requested rendering. |
| `options: GameAppOptions` | Host options such as macOS window mode and requested window size. |
| `input: InputState` | Current queryable input state. Updated before event and render callbacks. |
| `surface: GameSurface` | Current Metal-backed surface. Updated before render callbacks. |

| Method | Return | Description |
| --- | --- | --- |
| `onEvent(handler)` | `GameApp` | Register app-level event callback. Key and mouse button edges are routed to input helpers instead. |
| `onRender(handler)` | `GameApp` | Register render callback. |
| `run()` | `Result<void, string>` | Enter the native app loop. |
| `stop()` | `void` | Request app shutdown. |
| `requestRender()` | `void` | Schedule a render in requested mode. |
| `fps()` | `double` | Recent completed render callback rate. |
| `key(key)` | `InputButton` | Create a binary input helper for a keyboard key. |
| `mouseButton(button)` | `InputButton` | Create a binary input helper for a mouse button. |
| `controllerButton(slot, button)` | `InputButton` | Create a binary input helper for a controller button. |
| `controllerAxis(slot, axis)` | `InputAxis` | Create an analog axis reader. |
| `controllerStick(slot, stick)` | `InputStick` | Create a two-axis stick reader. |
| `screenPointer()` | `ScreenPointer` | Create a primary screen pointer helper. |
| `gestures()` | `ScreenGestures` | Create a screen gesture dispatcher. |
| `loadTexture(path)` | `Result<Texture, string>` | Decode and upload an image file. |
| `createTexture(image)` | `Result<Texture, string>` | Upload a `std/image` image. |
| `createTextureFromPixels(pixels)` | `Result<Texture, string>` | Upload `PixelBytes` directly. |
| `loadBitmapFont(path)` | `Result<BitmapFont, string>` | Load AngelCode BMFont text metrics and its texture page. |
| `loadIntrinsicFont()` | `Result<BitmapFont, string>` | Load the small embedded bitmap font. |
| `loadSound(path)` | `Result<Sound, string>` | Load platform-supported audio. |
| `beginPanGesture(x, y)` | `void` | Begin an app-declared pan gesture. |
| `updatePanGesture(x, y)` | `void` | Emit pan deltas from an app-declared pan gesture. |
| `endPanGesture()` | `void` | End a pan gesture, possibly starting inertia. |
| `cancelPanGesture()` | `void` | Cancel the active app-declared pan gesture. |
| `cancelPanInertia()` | `void` | Stop inertial pan events. |

`onEvent` receives close, resize, scroll, pan, magnify, double tap, and
controller connection events. It does not deliver key down/up or mouse
down/up events; use `InputButton`, `ScreenPointer`, and `ScreenGestures` for
those interactions.

### `GameSurface`

| Method | Return | Description |
| --- | --- | --- |
| `width()` / `height()` | `double` | Logical size. This matches `Camera.screen()`, text, UI, pointer, and touch coordinates. |
| `pixelWidth()` / `pixelHeight()` | `int` | Physical drawable size. |
| `scale()` | `double` | Native backing scale. |
| `metalDeviceHandle()` | `long` | Metal device pointer for native interop. |
| `metalCommandQueueHandle()` | `long` | Metal command queue pointer. |
| `metalLayerHandle()` | `long` | Metal layer pointer. |

## Events And Input

### Event Types

`GameEventKind` members are `CloseRequested`, `Resized`, `KeyDown`, `KeyUp`,
`MouseDown`, `MouseUp`, `MouseMove`, `Scroll`, `DoubleTap`, `Magnify`, `Pan`,
`ControllerConnected`, and `ControllerDisconnected`.

`GameRenderMode` members are `Continuous` and `Requested`.

`Key` includes letters `A` through `Z`, digits `Digit0` through `Digit9`,
arrows, `Escape`, `Enter`, `Space`, `Backspace`, `Tab`, `Shift`, `Control`,
`Option`, `Command`, and `F1` through `F12`.

`MouseButton` members are `Left`, `Right`, `Middle`, and `Other`.

Controller enums:

- `ControllerSlot`: `One`, `Two`, `Three`, `Four`
- `ControllerButton`: `South`, `East`, `West`, `North`, shoulders, triggers,
  menu/options, stick buttons, and D-pad directions
- `ControllerAxis`: `LeftX`, `LeftY`, `RightX`, `RightY`, `LeftTrigger`,
  `RightTrigger`
- `ControllerStick`: `Left`, `Right`, `DPad`

### `GameEvent`

| Method | Return | Description |
| --- | --- | --- |
| `kind()` | `GameEventKind` | Event kind. |
| `controller()` | `ControllerEvent` | Controller event details. |
| `key()` | `Key` | Key for key events. |
| `mouseButton()` | `MouseButton` | Button for mouse button events. |
| `x()` / `y()` | `double` | Screen-space event position. |
| `deltaX()` / `deltaY()` | `double` | Generic movement delta. |
| `panDeltaX()` / `panDeltaY()` | `double` | Pan delta. |
| `scrollDeltaX()` / `scrollDeltaY()` | `double` | Wheel or scroll delta. |
| `magnificationDelta()` | `double` | Relative pinch/zoom delta. |
| `pixelWidth()` / `pixelHeight()` | `int` | Size on resize events. |

`ControllerEvent` exposes `slot()`, `connected()`, and `name()`.

### `InputState`

| Method | Return | Description |
| --- | --- | --- |
| `isKeyDown(key)` | `bool` | Current key state. |
| `isMouseButtonDown(button)` | `bool` | Current mouse button state. |
| `mouseX()` / `mouseY()` | `double` | Current pointer position. |
| `mouseDeltaX()` / `mouseDeltaY()` | `double` | Frame-relative mouse movement. |
| `panDeltaX()` / `panDeltaY()` | `double` | Frame-relative pan movement. |
| `scrollDeltaX()` / `scrollDeltaY()` | `double` | Frame-relative scroll movement. |
| `magnificationDelta()` | `double` | Frame-relative magnify value. |
| `controllers()` | `ControllerQuery` | Query controller availability and names. |
| `isControllerConnected(slot)` | `bool` | Current controller connection state. |
| `isControllerButtonDown(slot, button)` | `bool` | Current controller button state. |
| `controllerAxis(slot, axis)` | `double` | Current analog axis value. |

`ControllerQuery` exposes `connected(slot)` and `name(slot)`.

### `InputButton`

```doof
jump := InputButton.any([
  app.key(Key.Space),
  app.controllerButton(.One, .South),
])

jump.onPressed((): void => println("jump"))
if jump.pressed() {
  // held this frame
}
```

| Method | Return | Description |
| --- | --- | --- |
| `InputButton.source(reader)` | `InputButton` | Create a button from a boolean reader. |
| `InputButton.any(buttons)` | `InputButton` | Pressed while any source button is pressed. |
| `pressed()` / `released()` | `bool` | Current held/up state. |
| `onPressed(handler)` | `InputButton` | Register rising-edge handler. |
| `onReleased(handler)` | `InputButton` | Register falling-edge handler. |

### `InputAxis` And `InputStick`

`InputAxis` exposes `value()`, `withDeadzone(deadzone)`, `inverted()`, and
`clamped(min, max)`.

`InputStick` exposes `x()`, `y()`, `length()`, `withDeadzone(deadzone)`, and
`invertedY()`.

### `ScreenPointer`

The primary screen pointer is backed by the primary mouse button on macOS and
single-touch translation on iOS.

| Method | Return | Description |
| --- | --- | --- |
| `x()` / `y()` | `double` | Screen-space pointer position. |
| `pressed()` / `released()` | `bool` | Current primary pointer state. |
| `onPressed(handler)` | `ScreenPointer` | Register pointer-down handler. |
| `onReleased(handler)` | `ScreenPointer` | Register pointer-up handler. |
| `onMoved(handler)` | `ScreenPointer` | Register move handler. |

### `ScreenGestures`

```doof
gestures := app.gestures()
gestures.onPan((g): void => panCamera(g.deltaX, g.deltaY))
gestures.onScroll((g): void => zoomAt(g.point, g.deltaY))
gestures.onMagnify((g): void => pinchZoom(g.point, g.magnificationDelta))
gestures.onDoubleTap((g): void => toggleZoomAt(g.point))
```

`ScreenGesture` has `point`, `deltaX`, `deltaY`, and `magnificationDelta`.
`ScreenGestures` exposes `onPan`, `onScroll`, `onMagnify`, and `onDoubleTap`.

## Rendering

Rendering happens inside `app.onRender`. A `Renderer` owns one native frame.
Create passes with `renderer.pass(desc, draw)`. The frame is committed after
the render callback returns.

### Core Types

| Type | Purpose |
| --- | --- |
| `Color` | RGBA color. Static values include `black`, `white`, `red`, `green`, `blue`, and `transparent`. |
| `Point` / `Point3` / `ClipPoint` | 2D, 3D, and homogeneous projected points. |
| `Rect` | `x`, `y`, `width`, and `height`. |
| `Texture` | Uploaded Metal texture with pixel dimensions and native handle. |
| `Atlas` | Texture grid helper with `cellRect(column, row)`. |

### `Renderer`

| Method | Return | Description |
| --- | --- | --- |
| `surface()` | `GameSurface` | Active surface. |
| `pass(desc, draw)` | `void` | Begin a render pass and invoke `draw(pass)`. |
| `loadTexture(path)` | `Result<Texture, string>` | Load a texture for the active surface. |
| `createTexture(image)` | `Result<Texture, string>` | Upload a `std/image` image. |
| `createTextureFromPixels(pixels)` | `Result<Texture, string>` | Upload raw pixel bytes. |

### `RenderPassDescriptor`

Defaults: `Camera.screen()`, `Clear.none()`, `Depth.disabled()`,
`Blend.opaque()`, `WindingMode.CounterClockwise`, and `CullMode.None`.

| Field | Type | Description |
| --- | --- | --- |
| `camera` | `Camera` | Camera used by built-in draw helpers. |
| `clear` | `Clear` | Color/depth clear behavior. |
| `depth` | `Depth` | Depth attachment and write behavior. |
| `blend` | `Blend` | Pipeline blend mode for helpers. |
| `winding` | `WindingMode` | Front-face winding. |
| `cull` | `CullMode` | Face culling mode. |

`Clear` factories are `none()`, `color(color)`, `depth(depthValue)`, and
`colorDepth(color, depthValue)`. `Depth` factories are `disabled()`,
`readOnly()`, and `readWrite()`. `Blend` factories are `opaque()` and
`alpha()`.

### `RenderPass`

| Method | Return | Description |
| --- | --- | --- |
| `surface()` | `GameSurface` | Pass surface. |
| `camera()` | `Camera` | Pass camera. |
| `metalRenderCommandEncoderHandle()` | `long` | Native encoder pointer. |
| `metalCommandBufferHandle()` | `long` | Native command buffer pointer. |
| `metalDeviceHandle()` | `long` | Native device pointer. |
| `hasDepthAttachment()` | `bool` | Whether the pass has a depth attachment. |

### Cameras And Matrices

```doof
screen := Camera.screen()
world := Camera.orthographic(-400.0, 400.0, -225.0, 225.0, -10.0, 10.0)
camera := Camera.perspective(1.0471975512, 0.1, 100.0)
  .withPosition(Point3(0.0, 0.0, 6.0))
  .lookAt(Point3(0.0, 0.0, 0.0))
```

`Camera.screen()` uses logical screen coordinates with `(0, 0)` at the top
left. `Camera.identity()` uses clip space. `Camera.orthographic(...)` accepts
explicit world bounds. `Camera.perspective(...)` derives aspect ratio from the
surface and uses a right-handed view where objects in front of the camera are
on negative Z.

Camera transform helpers mirror `Transform`: `withPosition`, `withRotation`,
`withScale`, `lookAt`, `moveWorldBy`, `moveLocalBy`, `rotateLocalX/Y/Z`,
`rotateWorldX/Y/Z`, `scaleBy`, and `scaleByVec`. Use `project(surface, point)`
to project a point through the camera.

`Mat4` exposes `identity`, `translation`, `scale`, `rotationX`, `rotationY`,
`rotationZ`, `orthographic`, `perspective`, `multiply`, and `transformPoint`.

## Transforms

`Vec3` provides common constants (`zero`, `one`, axes, `forward`, `back`,
`up`, `down`, `left`, `right`), constructors (`xyz`, `fromPoint`,
`toNormalized`), and vector math (`plus`, `minus`, `times`, `dividedBy`,
`dot`, `cross`, `length`, `lengthSquared`, `normalized`).

`Rotation` is quaternion-backed. Use `Rotation.identity`, `x`, `y`, `z`,
`axisAngle`, `euler`, `lookAt`, `slerp`, `multiply`, `andThen`, `inverse`,
`apply`, `toMat3`, and `toMat4`.

`Transform` combines `position`, `rotation`, and `scale`. Use `identity`,
`withPosition`, `withRotation`, `withScale`, `movedWorldBy`, `movedLocalBy`,
`rotatedLocalX/Y/Z`, `rotatedWorldX/Y/Z`, `scaledBy`, `scaledByVec`,
`applyPoint`, `applyVector`, `toMat4`, `toInverseMat4`, and `toNormalMat3`.

## Meshes, Models, And Batches

### `SimpleMeshSpec`

Raw mesh data:

- `positions: Point3[]`
- `indices: int[]`
- `colors: Color[]`
- `uvs: Point[]`
- `normals: Point3[]`

`vertexCount()` and `indexCount()` report array sizes. `SimpleMesh(surface,
spec)` validates the spec and uploads it to the surface device.

### `SimpleMeshBuilder`

| Method | Return | Description |
| --- | --- | --- |
| `SimpleMeshBuilder.create()` | `SimpleMeshBuilder` | Create an empty builder. |
| `vertex{ position, color, uv, normal }` | `int` | Add one vertex and return its index. |
| `triangle(a, b, c)` | `SimpleMeshBuilder` | Add an indexed triangle. |
| `quad{ a, b, c, d, color, normal, uvA, uvB, uvC, uvD }` | `SimpleMeshBuilder` | Add two triangles for a quad. |
| `buildSpec()` | `SimpleMeshSpec` | Return a copy of the raw spec. |
| `build(surface)` | `SimpleMesh` | Upload to the surface device. |

Triangles are emitted in the order supplied. Use counter-clockwise vertices
when viewed from the front to match the default pass winding.

### Drawing Helpers

| Function | Description |
| --- | --- |
| `drawSimpleMesh(pass, mesh, model = Mat4.identity, lighting = SimpleMeshLighting {})` | Draw an untextured mesh with built-in lighting. |
| `drawTexturedSimpleMesh(pass, mesh, texture, model = Mat4.identity, lighting = SimpleMeshLighting {})` | Draw a mesh using UVs and a texture. |
| `drawSimpleModel(pass, model, lighting = SimpleMeshLighting {})` | Draw a `SimpleModel`, using its texture when present. |

`SimpleMeshLighting` controls the built-in mesh lighting. `ambient` defaults
to `0.25`, `directional` defaults to `0.75`, and `direction` defaults to
`Point3(0.35, 0.60, 0.72)`. Negative light levels are clamped to zero by the
renderer; values above `1.0` are allowed.

### `SimpleModel`

`SimpleModel` wraps a mesh, optional texture, and `Transform`. It exposes
`setTransform`, `setTexture`, `clearTexture`, `setPosition`, `setRotation`,
`setScale`, movement, rotation, and scale helpers.

### `SimpleModelBatch`

Use a batch for many instances of one mesh and optional shared texture. The
batch keeps live instances packed and draws them with one instanced draw call.
`drawSimpleModelBatch(pass, batch, lighting = SimpleMeshLighting {})` applies
one lighting value to the whole batch.

```doof
batch := SimpleModelBatch {
  surface: app.surface,
  mesh: cardMesh,
  texture: atlas.texture,
  capacity: 100,
}

card := batch.add{
  transform: Transform.identity().withPosition(Point3(64.0, 64.0, 0.0)),
  uvOffset: Vec2.xy(0.0, 0.0),
  uvScale: Vec2.xy(1.0 / 14.0, 1.0 / 4.0),
}
```

`SimpleModelBatch` fields are `surface`, `mesh`, optional `texture`, and
`capacity`. Methods are `count()` and `add(...)`. `SimpleModelInstance` exposes
`isLive`, getters and setters for `transform`, `tint`, `whiteBlend`,
`uvOffset`, `uvScale`, transform helpers, and `remove()`.

`Vec2` provides `zero`, `one`, and `xy(x, y)`.

### Screen-Space Particles

`ParticleLayer(surface, ParticleLayerConfig { capacity })` manages a reusable
screen-space particle batch. Emit particles with `emit(ParticleConfig { ... })`,
advance them with `update(deltaTime)`, draw them with `draw(pass)`, and use
`isActive()` or `activeCount()` to decide whether requested-mode apps should
schedule another frame.

```doof
particles := ParticleLayer(app.surface, ParticleLayerConfig { capacity: 128 })
particles.emit(
  ParticleConfig {
    count: 48,
    x: 320.0,
    y: 180.0,
    minSpeed: 60.0,
    maxSpeed: 180.0,
    accelerationY: 180.0,
    lifetime: 1.2,
    size: 6.0,
    color: Color(1.0, 0.75, 0.25, 1.0),
  },
)
```

`ParticleConfig` includes position, optional position jitter, speed and angle
ranges, acceleration, lifetime, size, color, fade, seed, and count. Emission is
deterministic for a given seed.

`Fireworks(surface, FireworksConfig {})` builds on `ParticleLayer` for
celebration effects with staggered bursts, sparkles, and a closing finale. Call
`start(width, height)`, then `update(deltaTime)` and `draw(pass)` from
`onRender`.

```doof
fireworks := Fireworks(app.surface)

app.onRender((renderer): void => {
  active := fireworks.update(1.0 / 60.0)
  renderer.pass(
    RenderPassDescriptor {
      camera: Camera.screen(),
      depth: Depth.disabled(),
      blend: Blend.alpha(),
    },
    (pass): void => fireworks.draw(pass),
  )
  if active {
    app.requestRender()
  }
})
```

## Geometry And Assets

| API | Description |
| --- | --- |
| `createSphereMeshSpec{ radius = 1.0, tessellation = 24, color = Color.white }` | Create a UV sphere. Longitude segments are twice the latitude tessellation. |
| `createIcosphereMeshSpec{ radius = 1.0, subdivisions = 2, color = Color.white }` | Create an icosphere with evenly distributed triangles. |
| `parseObjMeshSpec(text, source = "input", color = Color.white)` | Parse Wavefront OBJ text into a `SimpleMeshSpec`. |
| `loadObjMeshSpec(path, color = Color.white)` | Load and parse a Wavefront OBJ file. |
| `parseGlb(data, source = "input")` | Parse an embedded GLB v2 file into a `GltfAsset`. |
| `loadGlb(path)` | Load and parse an embedded GLB v2 file. |
| `GltfAsset.createPose()` | Create an asset-bound `GltfPose` initialized from node defaults. |
| `GltfAnimation.apply(time, pose)` | Sample node TRS and morph weights into a pose. |
| `glbAssetToSimpleMeshSpecs(asset, color = Color.white)` | Extract supported static triangle primitives into `GltfSimpleMeshSpec[]`. |

The OBJ parser supports `v`, `vt`, `vn`, and polygonal `f` records, including
negative relative face indices. Polygons are triangulated with a fan. Missing
UVs use `(0, 0)`, and missing normals use generated face normals.

The GLB loader supports embedded GLB v2 files. `GltfAsset` preserves the parsed
JSON root, BIN chunk, buffers, buffer views, accessors, meshes, nodes, scenes,
samplers, images, textures, materials, animations, skin counts, and warnings.
Material records include common PBR factors and texture links. Animation
records include sampler input/output accessors, interpolation, channel targets,
and computed duration. `GltfPose` samples `STEP` and `LINEAR` translation,
rotation, scale, and morph weight channels, then resolves local transforms into
world matrices. The `SimpleMeshSpec`
conversion path supports static triangle primitives with float `POSITION`,
optional float `NORMAL`, optional float `TEXCOORD_0`, optional float `COLOR_0`,
and optional unsigned byte/short/int indices. Unsupported future-facing features
such as skins, external buffers, sparse accessors, and non-triangle primitives
are reported through warnings where possible.

## Textures And Atlases

`Texture` exposes `pixelWidth()`, `pixelHeight()`, and
`metalTextureHandle()`.

Load textures with `app.loadTexture(path)` or `renderer.loadTexture(path)`.
Create generated textures with `app.createTexture(image)`,
`renderer.createTexture(image)`, `app.createTextureFromPixels(pixels)`, or
`renderer.createTextureFromPixels(pixels)`.

`Atlas { texture, columns, rows }` divides a texture into a grid.
`cellRect(column, row)` returns the pixel rectangle for a cell.

## Text

`std/game` supports AngelCode BMFont text files with one texture page, plus a
small embedded intrinsic font.

```doof
font := try! app.loadIntrinsicFont()
model := createTextModel(
  app.surface,
  font,
  "Score 1200",
  TextLayoutOptions {
    position: Point(24.0, 32.0),
    maxWidth: 320.0,
    align: TextAlign.Left,
  },
)
```

| Type Or Function | Description |
| --- | --- |
| `TextAlign` | `Left`, `Center`, or `Right`. |
| `BitmapGlyph` | BMFont glyph metrics and atlas rectangle. |
| `BitmapKerning` | Kerning pair. |
| `BitmapFontMetrics` | Interface with metrics plus `glyph` and `kerning`. |
| `BitmapFontData` | Parsed metrics before texture loading. |
| `BitmapFont` | Metrics plus uploaded texture. |
| `TextLayoutOptions` | Color, position, z, wrapping width, alignment, letter/line spacing, fallback codepoint. |
| `TextBounds` | Measured width, height, and line count. |
| `parseBitmapFontData(text, source)` | Parse BMFont text metrics. |
| `measureText(font, text, options)` | Measure laid-out text. |
| `createTextMeshSpec(font, text, options)` | Build a text mesh spec. |
| `createTextMesh(surface, font, text, options)` | Upload a text mesh. |
| `createTextModel(surface, font, text, options)` | Create a textured `SimpleModel` for text. |
| `intrinsicBitmapFontData()` | Parse embedded intrinsic font metrics. |
| `loadIntrinsicBitmapFontForSurface(surface)` | Load embedded font texture for a surface. |

Text layout handles newlines, UTF-8 codepoints, kerning, optional word wrapping,
letter spacing, line spacing, and left/center/right alignment. Missing glyphs
fall back to `fallbackCodepoint`, which defaults to `?`.

## Retained UI

`UiLayer` is a small retained UI system for panels, labels, and buttons. Bounds
are in UI-local top-left coordinates; `setTransform` maps that UI space into the
screen-space render pass and is also inverted for hit testing.

```doof
ui := UiLayer(app)
status := ui.addLabel("Ready", Rect(24.0, 24.0, 260.0, 40.0), UiStyle {})
ui.addButton("Start", Rect(24.0, 80.0, 160.0, 44.0), UiButtonStyle {}, (): void => {
  status.setText("Started")
})
```

| `UiLayer` Method | Return | Description |
| --- | --- | --- |
| `UiLayer(appOrSurfaceOrNull)` | `UiLayer` | Construct for a `GameApp`, `GameSurface`, or tests. |
| `setTransform(transform)` | `UiLayer` | Set UI-to-screen transform. |
| `registerPointer(pointer)` | `UiLayer` | Wire a pointer into the layer. |
| `registerApp(app)` | `UiLayer` | Create/register an app pointer and request renders when hover/press state changes. |
| `addPanel(bounds, style)` | `UiPanel` | Add a panel. |
| `addLabel(text, bounds, style)` | `UiLabel` | Add a label. |
| `addButton(text, bounds, style, onClick)` | `UiButton` | Add a button. |
| `hitTest(point)` | `UiHit \| null` | Find the topmost visible element at a screen-space point. |
| `handleEvent(event)` | `void` | Feed mouse and double-tap events manually. |
| `draw(pass)` | `void` | Draw visible elements. |

Later-added elements are topmost. Styles default to the intrinsic font when
`font` is `null`.

`UiPanel`, `UiLabel`, and `UiButton` expose `id()`, `bounds()`, `isVisible()`,
`setBounds`, and `setVisible`. Labels also expose `setText`, `setColor`, and
`setAlign`. Buttons also expose `isHovered`, `isPressed`, `setText`,
`setEnabled`, and `setOnClick`.

`UiPanelStyle`, `UiStyle`, and `UiButtonStyle` hold colors, padding, z, font,
and alignment fields. `rectContains(rect, point)` is exported for hit testing.

## Custom Shaders

Custom shaders compile Metal source and draw with explicit buffer, byte, and
texture bindings. Use this path for custom vertex formats, indexed draws,
instancing, normal maps, and material effects beyond `SimpleMesh`.

```doof
pipeline := try! ShaderPipeline.create(
  app.surface,
  ShaderPipelineDescriptor {
    source,
    vertexFunction: "vertex_main",
    fragmentFunction: "fragment_main",
    attributes: [
      ShaderVertexAttribute { attribute: 0, offset: 0, format: ShaderVertexFormat.Float2 },
      ShaderVertexAttribute { attribute: 1, offset: 8, format: ShaderVertexFormat.Float4 },
    ],
    layouts: [ShaderVertexLayout { stride: 24 }],
  },
)
```

| API | Description |
| --- | --- |
| `ShaderVertexFormat` | `Float`, `Float2`, `Float3`, `Float4`, `UInt`, `UChar4Normalized`. |
| `ShaderVertexStepFunction` | `PerVertex` or `PerInstance`. |
| `ShaderVertexAttribute` | Attribute index, buffer index, byte offset, and format. |
| `ShaderVertexLayout` | Buffer index, stride, step function, and step rate. |
| `ShaderPipelineDescriptor` | Metal source, entry point names, attributes, and layouts. |
| `ShaderPipeline.create(surface, desc)` | Compile a pipeline. |
| `ShaderBuffer.create(surface, data)` | Upload bytes to a Metal buffer. |
| `ShaderBufferBinding` | Bind a vertex buffer at an index and offset. |
| `ShaderBytesBinding.create(surface, index, bytes)` | Create a temporary-style bytes binding backed by a buffer. |
| `ShaderTextureBinding` | Bind a fragment texture at an index. |
| `ShaderDraw` | Pipeline, vertex buffers, counts, optional index buffer, bytes, textures, and instance count. |
| `drawShader(pass, draw)` | Validate and issue the draw. |

Indexed draws use a `uint32` index buffer. Non-indexed draws use `vertexCount`.
`instanceCount` defaults to `1`.

## Sky And Space Effects

`SkyMap { texture }` wraps an equirectangular panorama texture. Draw it with
`drawEquirectangularSkyMap(pass, skyMap, fovYRadians = 1.0471975512,
exposure = 1.0)`. The helper uses the active camera rotation and ignores camera
position, treating the sky as infinitely far away.

`SpaceDustConfig` controls particle count, seed, field size, particle size,
fade range, opacity, and color. `SpaceDust(surface, config)` creates the
native particle field. Draw it with `drawSpaceDust(pass, dust)`.

## Sound

```doof
pickup := try! pickupSound()
laser := try! synthSound(SfxrSoundConfig.laser())
musicSting := try! app.loadSound("audio/sting.wav")

try! pickup.play()
try! laser.play(SoundPlayOptions { volume: 0.35, pan: -0.25 })
try! musicSting.play(SoundPlayOptions { volume: 0.8 })
```

| API | Description |
| --- | --- |
| `Sound.load(path)` / `loadSound(path)` | Decode a platform-supported audio file. |
| `Sound.fromSamples(samples)` | Create a reusable sound from mono samples. |
| `Sound.play(options = SoundPlayOptions {})` | Start playback. Repeated calls can overlap. |
| `Sound.stop()` | Stop active voices for this sound. |
| `Sound.duration()` | Duration in seconds. |
| `Sound.isPlaying()` | Whether any voice for this sound is active. |
| `SoundPlayOptions` | `volume` defaults to `1.0`; `pan` defaults to `0.0`. |
| `SoundSamples` | `sampleRate`, `samples`, and `duration()`. |

`SfxrSoundConfig` generates short game effects. Use presets
`pickup()`, `laser()`, `explosion()`, `jump()`, and `hit()`, or edit fields for
waveform, frequency slide, vibrato, square duty, envelope, and filters.

Helper functions:

- `generateSoundSamples(config)`
- `synthSound(config)`
- `pickupSound()`
- `laserSound()`
- `explosionSound()`
- `jumpSound()`
- `hitSound()`

`SoundWave` members are `Square`, `Saw`, `Sine`, `Noise`, and `Triangle`.

## Platform Notes

- macOS is the primary host.
- Doof's `ios-app` target attaches the same Metal-backed surface to the
  generated UIKit shell.
- iOS single-touch input is reported through the mouse/screen pointer APIs.
- Hardware keyboard events are not exposed on iOS yet.
- Offscreen render targets and additional platform backends are future work.

Build and run an iOS simulator sample with:

```bash
doof build --target ios-app --ios-destination simulator game/samples/jigsaw
doof run --target ios-app --ios-destination simulator game/samples/jigsaw
```

## Source Map

| Area | Files |
| --- | --- |
| App, surface, events | [`app.do`](../app.do), [`surface.do`](../surface.do), [`event.do`](../event.do), [`types.do`](../types.do) |
| Rendering and transforms | [`render.do`](../render.do), [`transform.do`](../transform.do) |
| Meshes and models | [`mesh.do`](../mesh.do), [`model.do`](../model.do), [`model_batch.do`](../model_batch.do) |
| Geometry and assets | [`sphere.do`](../sphere.do), [`icosphere.do`](../icosphere.do), [`obj.do`](../obj.do), [`sky.do`](../sky.do), [`dust.do`](../dust.do) |
| Text and UI | [`text.do`](../text.do), [`intrinsic_font.do`](../intrinsic_font.do), [`ui.do`](../ui.do), [`ui_controls.do`](../ui_controls.do), [`ui_types.do`](../ui_types.do), [`ui_draw.do`](../ui_draw.do) |
| Input | [`input.do`](../input.do), [`input_button.do`](../input_button.do), [`input_axis.do`](../input_axis.do), [`screen_pointer.do`](../screen_pointer.do), [`screen_gestures.do`](../screen_gestures.do), [`controller.do`](../controller.do), [`keys.do`](../keys.do), [`mouse.do`](../mouse.do) |
| Shaders | [`shader.do`](../shader.do) |
| Sound | [`sound.do`](../sound.do), [`sound_synth.do`](../sound_synth.do), [`sound_synth_types.do`](../sound_synth_types.do), [`sound_native.do`](../sound_native.do) |
| Native bridge | [`native.do`](../native.do) |
