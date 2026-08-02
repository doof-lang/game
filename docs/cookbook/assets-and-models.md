# Assets And Models

Use the app surface to upload textures and build Metal-backed meshes. Resource
loaders resolve paths relative to your package resources.

## Resource Paths

Sample packages keep images, fonts, models, and shaders next to `doof.json`.

## Load A Texture

```doof
texture := app.loadTextureResource("images/card_atlas.png") else error {
  println(error)
  return 1
}
```

Use `Atlas` when one image contains multiple sprites or cards.

## Build A Simple Mesh

```doof
builder := SimpleMeshBuilder()
builder.quad{
  a: Point3(-1.0, -1.0, 0.0),
  b: Point3(1.0, -1.0, 0.0),
  c: Point3(1.0, 1.0, 0.0),
  d: Point3(-1.0, 1.0, 0.0),
  color: Color.white,
}
mesh := builder.build(app.surface)
model := SimpleModel(mesh)
```

Use `drawSimpleMesh` when you only need the mesh. Use `SimpleModel` when the
object needs a transform.

## Load OBJ Meshes

```doof
spec := loadObjMeshSpecResource("models/marker.obj") else error {
  println(error.message)
  return 1
}
mesh := SimpleMesh(app.surface, spec)
```

OBJ loading is useful for simple static meshes.
Wavefront OBJ texture coordinates are converted from their bottom-origin
convention to std/game's top-origin texture convention during loading.

## Load glTF Or GLB Assets

```doof
asset := loadGlbResource("models/character.glb") else error {
  println(error.message)
  return 1
}

specs := glbAssetToSimpleMeshSpecs(asset)
```

Use `loadGltfResource` for `.gltf` files with a local `.bin` buffer. Use
glTF/GLB when the model pipeline needs materials, nodes, textures, or animation
data. Convert primitives to simple mesh specs when using the built-in simple
renderer.

See [`samples/gltf-walk`](../../samples/gltf-walk) and
[`samples/glb-overview`](../../samples/glb-overview).

## Batch Repeated Models

Use `SimpleModelBatch` when many instances share the same mesh and material,
such as cards, tiles, particles, or map markers.

```doof
batch := SimpleModelBatch {
  surface: app.surface,
  mesh,
  capacity: 128,
}
batch.add{
  transform: Transform.identity().withPosition(Point3(100.0, 100.0, 0.0)),
}
```

See [`samples/cards`](../../samples/cards).
