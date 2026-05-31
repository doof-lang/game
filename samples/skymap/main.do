import {
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  GameEventKind,
  Key,
  RenderPassDescriptor,
  Rotation,
  SkyMap,
  drawEquirectangularSkyMap,
  initGameApp,
} from "std/game"

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
  skyMap := SkyMap { texture: texture }

  let fovY = 1.0471975512

  camera := Camera.identity()

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
    renderer.pass(
      RenderPassDescriptor {
        camera,
        clear: Clear.color(Color.black),
        depth: Depth.disabled(),
        blend: Blend.opaque(),
      },
      (pass): void => {
        drawEquirectangularSkyMap(pass, skyMap, fovY, 1.0)
      },
    )
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
