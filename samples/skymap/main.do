import {
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  GameEventKind,
  Key,
  Point3,
  RenderPassDescriptor,
  SimpleMesh,
  SimpleModel,
  SpaceDust,
  SpaceDustConfig,
  SkyMap,
  Transform,
  Vec3,
  createSphereMeshSpec,
  drawSpaceDust,
  drawSimpleModel,
  drawEquirectangularSkyMap,
  initGameApp,
  loadObjMeshSpec,
} from "std/game"
import { Instant } from "std/time"

function clampPitch(value: double): double {
  limit := 83.0
  if value < -limit {
    return -limit
  }
  if value > limit {
    return limit
  }
  return value
}

function main(): int {
  app := initGameApp{ title: "Doof Game Equirectangular Sky Map" }
  texture := try! app.loadTexture("images/panorama.hdr")
  earthTexture := try! app.loadTexture("images/earth_daymap.jpg")
  skyMap := SkyMap { texture: texture }
  markerSpec := try! loadObjMeshSpec("models/marker.obj", Color(0.98, 0.78, 0.28))
  marker := SimpleModel(SimpleMesh(app.surface, markerSpec))
  marker.setTransform(
    Transform
      .identity()
      .withPosition(Point3(0.0, -0.18, -3.0))
      .withScale(Vec3.xyz(0.62, 0.62, 0.62)),
  )
  planetSpec := createSphereMeshSpec{ radius: 1.0, tessellation: 32 }
  planet := SimpleModel(SimpleMesh(app.surface, planetSpec), earthTexture)
  planet.setTransform(
    Transform
      .identity()
      .withPosition(Point3(0.0, 0.0, -8.0))
      .withScale(Vec3.xyz(2.4, 2.4, 2.4)),
  )
  dust := SpaceDust(
    app.surface,
    SpaceDustConfig {
      particleCount: 2600,
      seed: 29.0,
      fieldSize: 42.0,
      particleSize: 2.1,
      fadeStart: 5.0,
      fadeEnd: 19.0,
      opacity: 0.55,
      color: Color(0.70, 0.82, 1.0),
    },
  )

  let fovY = 1.0471975512

  let camera = Camera.identity()
  let lastFrameAt = Instant.now()

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }

    if event.kind() == GameEventKind.KeyDown && event.key() == Key.Escape {
      app.stop()
    }

    if event.kind() == GameEventKind.MouseMove {
      camera.rotateLocalX(-event.deltaY() * 0.15).rotateLocalY(-event.deltaX() * 0.15)
      app.requestRender()
    }

    if event.kind() == GameEventKind.Resized {
      app.requestRender()
    }
  })

  app.onRender((renderer): void => {
    now := Instant.now()
    elapsed := lastFrameAt.durationUntil(now)
    lastFrameAt = now
    let frameSeconds = double(elapsed.toNanos()) / 1000000000.0
    if frameSeconds > 0.1 {
      frameSeconds = 0.016
    }

    surface := renderer.surface()
    spaceHeld := app.input.isKeyDown(Key.Space)
    if spaceHeld {
      camera = camera.moveLocalBy(Vec3.forward.times(frameSeconds * 4.0))
    }

    aspect := double(surface.pixelWidth()) / double(surface.pixelHeight())
    sceneCamera := Camera
      .perspective(fovY, aspect, 0.1, 100.0)
      .withTransform(camera.transform)

    renderer.pass(
      RenderPassDescriptor {
        camera: sceneCamera,
        clear: Clear.colorDepth(Color.black, 1.0),
        depth: Depth.readWrite(),
        blend: Blend.opaque(),
        cull: .Back,
      },
      (pass): void => {
        marker.rotateLocalY(1)
        planet.rotateLocalY(0.15)
        drawEquirectangularSkyMap(pass, skyMap, fovY, 1.0)
        drawSimpleModel(pass, planet)
        drawSimpleModel(pass, marker)
      },
    )

    renderer.pass(
      RenderPassDescriptor {
        camera: sceneCamera,
        clear: Clear.none(),
        depth: Depth.readOnly(),
        blend: Blend.alpha(),
      },
      (pass): void => {
        drawSpaceDust(pass, dust)
      },
    )

    app.requestRender()
  })

  app.requestRender()
  result := app.run()
  case result {
    s: Success -> return 0
    f: Failure -> {
      println(f.error)
      return 1
    }
  }
}
