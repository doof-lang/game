import {
  Blend, Camera, Clear, Color, Depth, GameEventKind, Key, MouseButton, Point3,
  RenderPassDescriptor, SimpleMesh, SimpleModel, SpaceDust, SpaceDustConfig, SkyMap,
  Transform, Vec3, createSphereMeshSpec, drawEquirectangularSkyMap, drawSimpleModel,
  drawSpaceDust, initGameApp, parseObjMeshSpec,
} from "std/game"
import { Instant } from "std/time"

export function start(markerObj: string): none {
  app := initGameApp("Doof Game Equirectangular Sky Map")
  panorama := try! app.loadTexture("images/panorama.jpg")
  earthTexture := try! app.loadTexture("images/earth_daymap.jpg")
  skyMap := SkyMap { texture: panorama }
  markerSpec := try! parseObjMeshSpec(markerObj, "models/marker.obj", Color(0.98, 0.78, 0.28))
  marker := SimpleModel(SimpleMesh(app.surface, markerSpec))
  marker.setTransform(
    Transform.identity().withPosition(Point3(0.0, -0.18, -3.0)).withScale(Vec3.xyz(0.62, 0.62, 0.62)),
  )
  planet := SimpleModel(SimpleMesh(app.surface, createSphereMeshSpec{ radius: 1.0, tessellation: 32 }), earthTexture)
  planet.setTransform(
    Transform.identity().withPosition(Point3(0.0, 0.0, -8.0)).withScale(Vec3.xyz(2.4, 2.4, 2.4)),
  )
  dust := SpaceDust(
    app.surface,
    SpaceDustConfig {
      particleCount: 2600, seed: 29.0, fieldSize: 42.0, particleSize: 2.1,
      fadeStart: 5.0, fadeEnd: 19.0, opacity: 0.55, color: Color(0.70, 0.82, 1.0),
    },
  )

  fovY := 1.0471975512
  let playerCamera = Camera.identity()
  let lastFrameAt = Instant.now()

  app.onEvent((event): none => {
    if event.kind() == GameEventKind.MouseMove && app.input.isMouseButtonDown(MouseButton.Left) {
      playerCamera.rotateLocalX(-event.deltaY() * 0.15).rotateLocalY(-event.deltaX() * 0.15)
    }
  })

  app.onRender((renderer): none => {
    now := Instant.now()
    elapsed := lastFrameAt.durationUntil(now)
    lastFrameAt = now
    let frameSeconds = elapsed.toSeconds()
    if frameSeconds > 0.1 { frameSeconds = 0.016 }
    if app.input.isKeyDown(Key.Space) {
      playerCamera.moveLocalBy(Vec3.forward.times(frameSeconds * 4.0))
    }

    sceneCamera := Camera.perspective(fovY, 0.1, 100.0).withTransform(playerCamera.transform)
    renderer.pass(
      RenderPassDescriptor {
        camera: sceneCamera,
        clear: Clear.colorDepth(Color.black, 1.0),
        depth: Depth.readWrite(),
        blend: Blend.opaque(),
        cull: .Back,
      },
      (pass): none => {
        planet.rotateLocalY(frameSeconds * 9.0)
        marker.rotateLocalY(frameSeconds * 60.0)
        drawEquirectangularSkyMap(pass, skyMap, fovY, 1.0)
        drawSimpleModel(pass, planet)
        drawSimpleModel(pass, marker)
      },
    )
    renderer.pass(
      RenderPassDescriptor {
        camera: sceneCamera,
        clear: Clear.disabled(),
        depth: Depth.readOnly(),
        blend: Blend.alpha(),
      },
      (pass): none => drawSpaceDust(pass, dust),
    )
  })

  _ := app.run() else error { panic(error) }
}
