import {
  Blend,
  Clear,
  Color,
  ControllerButton,
  ControllerSlot,
  ControllerStick,
  Depth,
  GameEventKind,
  GameSurface,
  Key,
  Point3,
  RenderPassDescriptor,
  SimpleMesh,
  SimpleMeshBuilder,
  SimpleModel,
  Transform,
  Vec3,
  drawSimpleModel,
  initGameApp,
} from "std/game"

function createPlayerMesh(surface: GameSurface): SimpleMesh {
  return SimpleMeshBuilder
    .create()
    .quad{
      a: Point3(-32.0, -32.0, 0.0),
      b: Point3(32.0, -32.0, 0.0),
      c: Point3(32.0, 32.0, 0.0),
      d: Point3(-32.0, 32.0, 0.0),
      color: Color(0.20, 0.72, 1.0),
    }
    .build(surface)
}

function main(): int {
  app := initGameApp{ title: "Doof Game Controller" }
  player := SimpleModel(createPlayerMesh(app.surface))
  move := app.controllerStick(ControllerSlot.One, ControllerStick.Left).withDeadzone(0.18).invertedY()
  rightTrigger := app.controllerAxis(.One, .RightTrigger).clamped(0.0, 1.0)

  let x = 400.0
  let y = 240.0

  println("Connect a controller. Move with the left stick, squeeze the right trigger, and press face buttons.")

  app.controllerButton(.One, ControllerButton.South).onPressed((): void => println("South pressed"))
  app.controllerButton(.One, ControllerButton.East).onPressed((): void => println("East pressed"))
  app.controllerButton(.One, ControllerButton.West).onPressed((): void => println("West pressed"))
  app.controllerButton(.One, ControllerButton.North).onPressed((): void => println("North pressed"))
  app.key(Key.Escape).onPressed((): void => app.stop())

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    } else if event.kind() == GameEventKind.ControllerConnected {
      println("Connected: " + event.controller().name())
    } else if event.kind() == GameEventKind.ControllerDisconnected {
      println("Disconnected: " + event.controller().name())
    }
  })

  app.onRender((renderer): void => {
    x += move.x() * 6.0
    y += move.y() * 6.0
    scale := 1.0 + rightTrigger.value() * 0.75
    player.setTransform(
      Transform.identity()
        .withPosition(Point3(x, y, 0.0))
        .withScale(Vec3.xyz(scale, scale, 1.0)),
    )

    renderer.pass(
      RenderPassDescriptor {
        clear: Clear.colorDepth(Color(0.02, 0.03, 0.05), 1.0),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      },
      (pass): void => drawSimpleModel(pass, player),
    )
    app.requestRender()
  })

  app.run() else error {
    println(error)
    return 1
  }
  return 0
}
