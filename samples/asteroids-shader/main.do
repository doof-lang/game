import { sin } from "std/math"
import { Instant } from "std/time"

import {
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  Point3,
  RenderPassDescriptor,
  initGameApp,
} from "std/game"

import { AsteroidShaderResources, createAsteroidShaderResources, drawAsteroids } from "./asteroid_shader"

function main(): int {
  app := initGameApp{ title: "Doof Game Custom Shader Asteroids" }
  let resources: AsteroidShaderResources | null = null
  start := Instant.now()
  let cameraYaw = 0.0

  app.key(.Escape).onPressed() {
    app.stop()
  }

  app.onRender() {
    now := Instant.now()
    time := double(start.durationUntil(now).toNanos()) / 1000000000.0
    cameraYaw = sin(time * 0.22) * 6.0
    surface := app.surface
    if resources == null {
      resources = createAsteroidShaderResources(surface)
    }

    aspect := double(surface.pixelWidth()) / double(surface.pixelHeight())
    camera := Camera.perspective(1.0471975512, aspect, 0.1, 80.0)
      .withPosition(Point3(0.0, 0.4, 2.6))
      .rotateLocalY(cameraYaw)

    passDescriptor := RenderPassDescriptor {
      camera,
      clear: Clear.colorDepth(Color(0.006, 0.009, 0.014), 1.0),
      depth: Depth.readWrite(),
      blend: Blend.opaque(),
    }

    renderer.pass(passDescriptor) {
      drawAsteroids(pass, resources!, pass.camera().matrix(surface), time)
    }
  }

  app.run() else error {
    println(error)
    return 1
  }

  return 0
}
