# Custom WebGL 2 shader sample

This Wasm sample passes separate GLSL ES vertex and fragment sources from the
browser consumer into `ShaderProgram`. It draws a procedural full-screen
backdrop, uploads an interleaved position/barycentric buffer, and renders a
384-prism field in one instanced draw. The sample maps attributes with explicit
WebGL 2 `layout(location = ...)` locations and draws through the shared
`ShaderPipeline` and `drawShader` API.

```sh
doof build game/samples/custom-shader-web
cd game/samples/custom-shader-web/build
python3 -m http.server 8080
```

Open `http://localhost:8080/web/`.

The current WebGL 2 custom path supports vertex buffers, `uint32` index buffers,
non-indexed draws, and instancing. Uniform-byte and texture bindings report an
explicit not-implemented error.

The Wasm host also supplies optional `doofTime`, `doofViewport`, and
`doofPointer` GLSL uniforms when a custom program declares them. Time is in
seconds, viewport is in physical pixels, and pointer coordinates are normalized
from the bottom-left corner.
