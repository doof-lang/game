import { Instant } from "std/time"

import {
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  GameEventKind,
  GameSurface,
  GltfAsset,
  GltfSimpleMeshSpec,
  Key,
  Mat4,
  Point3,
  RenderPassDescriptor,
  RenderPass,
  SimpleMesh,
  SimpleMeshBuilder,
  SimpleMeshLighting,
  Texture,
  Transform,
  Vec3,
  drawSimpleMesh,
  drawTexturedSimpleMesh,
  glbAssetToSimpleMeshSpecs,
  initGameApp,
  loadGlbResource,
} from "std/game"

class AnimatedPart {
  meshIndex: int = 0
  nodeIndex: int = -1
  mesh: SimpleMesh
}

function findNodeForMesh(asset: GltfAsset, meshIndex: int): int {
  for nodeIndex of 0..<asset.nodes.length {
    if asset.nodes[nodeIndex].mesh == meshIndex {
      return nodeIndex
    }
  }
  return -1
}

function createAnimatedParts(
  surface: GameSurface,
  asset: GltfAsset,
  specs: GltfSimpleMeshSpec[],
): AnimatedPart[] {
  parts: AnimatedPart[] := []
  for spec of specs {
    parts.push(AnimatedPart {
      meshIndex: spec.meshIndex,
      nodeIndex: findNodeForMesh(asset, spec.meshIndex),
      mesh: SimpleMesh(surface, spec.spec),
    })
  }
  return parts
}

function createGroundMesh(surface: GameSurface): SimpleMesh {
  builder := SimpleMeshBuilder.create()
  color := Color(0.22, 0.75, 0.22)
  normal := Point3(0.0, 1.0, 0.0)
  builder.quad{
    a: Point3(-40.0, -0.02, -20.2),
    b: Point3(-40.0, -0.02, 20.2),
    c: Point3(40.0, -0.02, 20.2),
    d: Point3(40.0, -0.02, -20.2),
    color,
    normal,
  }
  return builder.build(surface)
}

function drawAnimatedPart(
  pass: RenderPass,
  part: AnimatedPart,
  texture: Texture,
  poseWorld: Mat4[],
  sceneTransform: Transform,
  lighting: SimpleMeshLighting,
): void {
  let model = sceneTransform.toMat4()
  if part.nodeIndex >= 0 && part.nodeIndex < poseWorld.length {
    model = model.multiply(poseWorld[part.nodeIndex])
  }
  drawTexturedSimpleMesh(pass, part.mesh, texture, model, lighting)
}

function main(): int {
  app := initGameApp{ title: "Doof GLTF Walking Character" }

  app.key(.Escape).onPressed() {
    app.stop()
  }

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }
  })

  asset := loadGlbResource("models/character-a.glb") else error {
    println("Failed to load GLB: " + error.message)
    return 1
  }
  animation := asset.findAnimation("walk") else error {
    println("Failed to find walk animation: " + error.message)
    return 1
  }
  specs := glbAssetToSimpleMeshSpecs(asset) else error {
    println("Failed to convert GLB meshes: " + error.message)
    return 1
  }

  texture := app.loadTextureResource("models/Textures/texture-a.png") else error {
    println("Failed to load character texture: " + error)
    return 1
  }

  parts := createAnimatedParts(app.surface, asset, specs)
  ground := createGroundMesh(app.surface)
  pose := asset.createPose()

  let elapsedSeconds = 0.0
  let strideDistance = 2.8
  let lastFrameAt = Instant.now()

  camera := Camera
    .perspective(0.82, 0.1, 100.0)
    .withPosition(Point3(10.0, 30.0, 19.0))
    .lookAt(Point3(0.0, 0.0, 0.0), Vec3.up)

  renderPassDescriptor := RenderPassDescriptor {
    camera,
    clear: Clear.colorDepth(Color(0.05, 0.07, 0.085), 1.0),
    depth: Depth.readWrite(),
    blend: Blend.opaque(),
    cull: .Back,
  }
  lighting := SimpleMeshLighting {
    ambient: 0.38,
    directional: 0.82,
    direction: Point3(-0.35, 0.72, 0.45),
  }

  app.onRender((renderer): void => {
    now := Instant.now()
    elapsed := lastFrameAt.durationUntil(now)
    lastFrameAt = now

    let frameSeconds = elapsed.toSeconds()
    if frameSeconds > 0.1 {
      frameSeconds = 0.016
    }
    elapsedSeconds += frameSeconds

    pose.reset()
    pose.applyLooping(animation, elapsedSeconds) else error {
      println("Failed to sample animation: " + error.message)
      app.stop()
      return
    }
    pose.resolveWorldTransforms() else error {
      println("Failed to resolve pose: " + error.message)
      app.stop()
      return
    }

    walkCycle := elapsedSeconds / animation.duration
    trackOffset := walkCycle * strideDistance - strideDistance * 0.5
    sceneTransform := Transform
      .identity()
      .withPosition(Point3(-1.15, 0.0, trackOffset))
      .withScale(Vec3.xyz(0.72, 0.72, 0.72))

    renderer.pass(renderPassDescriptor, (pass): void => {
      drawSimpleMesh(pass, ground, Mat4.identity, lighting)
      for part of parts {
        drawAnimatedPart(pass, part, texture, pose.world, sceneTransform, lighting)
      }
    })
  })

  app.run() else error {
    println(error)
    return 1
  }

  return 0
}
