# WebGL/Wasm sky map sample

This browser sample uses the ordinary `std/game` API. Its Wasm target selects a
WebGL implementation behind the same native game window, surface, render-pass,
texture, mesh, sky-map, and space-dust boundary used by the macOS, iOS, and
Windows backends. There is no browser-specific game object model.

Drag with the primary mouse button to look around and hold Space to move forward
through the world-space scene. The player camera uses the shared quaternion-backed
`Camera`, `Transform`, and `Rotation` implementation.

```sh
doof build game/samples/skymap-web
cd game/samples/skymap-web/build
python3 -m http.server 8080
```

Open `http://localhost:8080/web/`.

The demonstration uses 1024×512 browser copies downsampled from the native
sample's 8192×4096 HDR panorama and 2048×1024 Earth map. It also loads the same
marker OBJ. The browser host preloads image data before starting Wasm, then the
Doof sample accesses it through the normal synchronous `app.loadTexture(...)`
backend boundary.
