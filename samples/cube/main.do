import { setInterval } from "std/event"
import { cos, sin } from "std/math"
import { Duration } from "std/time"

import {
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  GameEventKind,
  Key,
  Mat4,
  Point3,
  RenderPass,
  RenderPassDescriptor,
  drawTriangle3,
  initGameApp,
} from "std/game"

function rotateCubePoint(x: double, y: double, z: double, angle: double): Point3 {
  yCos := cos(angle)
  ySin := sin(angle)
  xCos := cos(angle * 0.62)
  xSin := sin(angle * 0.62)

  rotatedX := x * yCos + z * ySin
  rotatedZ := z * yCos - x * ySin
  rotatedY := y * xCos - rotatedZ * xSin
  finalZ := rotatedZ * xCos + y * xSin

  return Point3.xyz(rotatedX, rotatedY, finalZ)
}

function drawCubeFace(
  pass: RenderPass,
  a: Point3,
  b: Point3,
  c: Point3,
  d: Point3,
  color: Color,
): void {
  drawTriangle3(pass, a, b, c, color)
  drawTriangle3(pass, a, c, d, color)
}

function drawCube(pass: RenderPass, angle: double): void {
  p000 := rotateCubePoint(-1.0, -1.0, -1.0, angle)
  p001 := rotateCubePoint(-1.0, -1.0, 1.0, angle)
  p010 := rotateCubePoint(-1.0, 1.0, -1.0, angle)
  p011 := rotateCubePoint(-1.0, 1.0, 1.0, angle)
  p100 := rotateCubePoint(1.0, -1.0, -1.0, angle)
  p101 := rotateCubePoint(1.0, -1.0, 1.0, angle)
  p110 := rotateCubePoint(1.0, 1.0, -1.0, angle)
  p111 := rotateCubePoint(1.0, 1.0, 1.0, angle)

  drawCubeFace(pass, p001, p101, p111, p011, Color.rgb(0.95, 0.20, 0.16))
  drawCubeFace(pass, p100, p000, p010, p110, Color.rgb(0.12, 0.42, 0.95))
  drawCubeFace(pass, p000, p001, p011, p010, Color.rgb(0.15, 0.78, 0.42))
  drawCubeFace(pass, p101, p100, p110, p111, Color.rgb(0.98, 0.72, 0.18))
  drawCubeFace(pass, p010, p011, p111, p110, Color.rgb(0.72, 0.32, 0.92))
  drawCubeFace(pass, p000, p100, p101, p001, Color.rgb(0.10, 0.82, 0.86))
}

function main(): int {
  app := initGameApp{ title: "Doof Game Spinning Cube" }
  let angle = 0.0

  frameTimer := setInterval{
    interval: Duration.ofMillis(15L),
    handler: (): void => {
      angle += 0.025
      app.requestRender()
    },
  }

  fpsTimer := setInterval{
    interval: Duration.ofSeconds(1L),
    handler: (): void => {
      println("fps ${app.fps()}")
    },
  }

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }

    if event.kind() == GameEventKind.KeyDown && event.key() == Key.Escape {
      app.stop()
    }
  })

  app.onRender((renderer): void => {
    surface := renderer.surface()
    aspect := double(surface.pixelWidth()) / double(surface.pixelHeight())
    camera := Camera.perspective(1.0471975512, aspect, 0.1, 100.0).withView(Mat4.translation(0.0, 0.0, -5.0))

    renderer.pass(
      RenderPassDescriptor {
        camera: camera,
        clear: Clear.colorDepth(Color.rgb(0.018, 0.022, 0.030), 1.0),
        depth: Depth.readWrite(),
        blend: Blend.opaque(),
      },
      (pass): void => {
        drawCube(pass, angle)
      },
    )

  })

  result := app.run()
  case result {
    s: Success -> return 0
    f: Failure -> {
      println(f.error)
      return 1
    }
  }
}
