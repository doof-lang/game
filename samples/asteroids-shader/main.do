import { clamp, cos, exp, round, sin } from "std/math"
import { Instant } from "std/time"

import {
  BitmapFont,
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  GameApp,
  GameSurface,
  Point,
  Point3,
  RenderPass,
  RenderPassDescriptor,
  SimpleMesh,
  SimpleMeshBuilder,
  SimpleModel,
  SpaceDust,
  SpaceDustConfig,
  TextLayoutOptions,
  Vec3,
  createTextModel,
  drawSimpleMesh,
  drawSimpleModel,
  drawSpaceDust,
  initGameApp,
} from "std/game"

import {
  AsteroidShaderResources,
  BELT_RADIUS,
  CAMERA_HEIGHT,
  Sun,
  createAsteroidShaderResources,
  drawAsteroidField,
} from "./asteroid_shader"

// Radians per second along the belt at 1x speed.
readonly FLIGHT_SPEED = 0.035

readonly SUN = Sun {
  // Unit vector toward the sun.
  direction: Vec3 { x: -0.3811, y: 0.2006, z: 0.9025 },
  color: Color(1.0, 0.92, 0.80),
  exposure: 1.5,
}

// ---------------------------------------------------------------------------
// Flight camera: glides along the middle of the belt. Dragging looks around;
// when left alone it drifts back to a slow scripted sway.

class FlightCamera {
  let angle: double = 0.0
  let speed: double = 1.0
  let lookYaw: double = 0.0
  let lookPitch: double = 0.0
  let idleSeconds: double = 10.0

  update(app: GameApp, deltaSeconds: double, paused: bool): none {
    if app.input.isMouseButtonDown(.Left) {
      lookYaw += app.input.mouseDeltaX() * 0.005
      lookPitch = clamp(lookPitch - app.input.mouseDeltaY() * 0.005, -1.2, 1.2)
      idleSeconds = 0.0
    } else {
      idleSeconds += deltaSeconds
    }

    scroll := app.input.scrollDeltaY()
    if scroll != 0.0 {
      speed = clamp(speed + scroll * 0.04, 0.0, 6.0)
    }

    if idleSeconds > 4.0 {
      settle := exp(-deltaSeconds * 0.6)
      lookYaw *= settle
      lookPitch *= settle
    }

    if !paused {
      angle += deltaSeconds * FLIGHT_SPEED * speed
    }
  }

  reset(): none {
    speed = 1.0
    lookYaw = 0.0
    lookPitch = 0.0
  }

  position(time: double): Point3 {
    return Point3(cos(angle) * BELT_RADIUS, CAMERA_HEIGHT + sin(time * 0.11) * 0.5, sin(angle) * BELT_RADIUS)
  }

  camera(time: double): Camera {
    forward := Vec3.xyz(-sin(angle), 0.0, cos(angle))
    inward := Vec3.xyz(-cos(angle), 0.0, -sin(angle))

    // Swing between looking down the belt and looking at the planet.
    yaw := 0.2 + (sin(time * 0.06 - 1.2) * 0.5 + 0.5) * 1.2 + lookYaw
    pitch := sin(time * 0.045) * 0.08 + lookPitch
    flat := forward.times(cos(yaw)).plus(inward.times(sin(yaw)))
    direction := flat.times(cos(pitch)).plus(Vec3.up.times(sin(pitch)))

    eye := position(time)
    return Camera
      .perspective(1.05, 0.05, 400.0)
      .withPosition(eye)
      .lookAt(Vec3.fromPoint(eye).plus(direction).toPoint3(), Vec3.up)
  }
}

// ---------------------------------------------------------------------------
// HUD

class Hud {
  font: BitmapFont
  panel: SimpleMesh
  title: SimpleModel
  help: SimpleModel
  let status: SimpleModel
}

function hudStatus(surface: GameSurface, font: BitmapFont, speed: double, paused: bool, fps: double): SimpleModel {
  speedText := if paused then "paused" else "${round(speed * 10.0) / 10.0}x"
  return createTextModel(
    surface,
    font,
    "Speed: ${speedText}   ${round(fps)} fps",
    TextLayoutOptions { position: Point(32.0, 54.0), color: Color(1.0, 0.80, 0.52) },
  )
}

function createHud(app: GameApp): Hud {
  font := try! app.loadIntrinsicFont()
  panel := SimpleMeshBuilder()
    .quad{
      a: Point3(16.0, 16.0, 0.0),
      b: Point3(440.0, 16.0, 0.0),
      c: Point3(440.0, 124.0, 0.0),
      d: Point3(16.0, 124.0, 0.0),
      color: Color(0.02, 0.03, 0.06, 0.6),
    }
    .build(app.surface)
  return Hud {
    font,
    panel,
    title: createTextModel(
      app.surface,
      font,
      "Asteroid Belt",
      TextLayoutOptions { position: Point(32.0, 30.0), color: Color(0.95, 0.96, 0.98) },
    ),
    help: createTextModel(
      app.surface,
      font,
      "Drag to look around, scroll to change speed\nSpace pause  R reset",
      TextLayoutOptions { position: Point(32.0, 80.0), lineSpacing: 4.0, color: Color(0.70, 0.76, 0.86) },
    ),
    status: hudStatus(app.surface, font, 1.0, false, 0.0),
  }
}

function drawHud(pass: RenderPass, hud: Hud): none {
  drawSimpleMesh(pass, hud.panel)
  drawSimpleModel(pass, hud.title)
  drawSimpleModel(pass, hud.status)
  drawSimpleModel(pass, hud.help)
}

// ---------------------------------------------------------------------------

function main(): int {
  app := initGameApp{ title: "Doof Game Custom Shader Asteroids" }
  let resources: AsteroidShaderResources | none = none
  flight := FlightCamera {}
  hud := createHud(app)
  dust := SpaceDust(
    app.surface,
    SpaceDustConfig {
      particleCount: 1800,
      seed: 7.0,
      fieldSize: 30.0,
      particleSize: 1.6,
      fadeStart: 3.0,
      fadeEnd: 14.0,
      opacity: 0.45,
      color: Color(0.85, 0.80, 0.72),
    },
  )

  let paused = false
  let time = 0.0
  let lastFrameAt = Instant.now()
  let statusAge = 1.0

  app.key(.Escape).onPressed() {
    app.stop()
  }
  app.key(.Space).onPressed() {
    paused = !paused
    statusAge = 1.0
  }
  app.key(.R).onPressed() {
    flight.reset()
    statusAge = 1.0
  }

  app.onRender() {
    surface := app.surface
    if resources == none {
      resources = createAsteroidShaderResources(surface)
    }

    now := Instant.now()
    deltaSeconds := clamp(lastFrameAt.durationUntil(now).toSeconds(), 0.0, 0.1)
    lastFrameAt = now
    if !paused {
      time += deltaSeconds
    }
    flight.update(app, deltaSeconds, paused)

    statusAge += deltaSeconds
    if statusAge > 0.5 {
      statusAge = 0.0
      hud.status = hudStatus(surface, hud.font, flight.speed, paused, app.fps())
    }

    camera := flight.camera(time)
    renderer.pass(
      RenderPassDescriptor {
        camera,
        clear: Clear.colorDepth(Color(0.0, 0.0, 0.0), 1.0),
        depth: Depth.readWrite(),
        blend: Blend.opaque(),
      },
    ) {
      drawAsteroidField(pass, resources!, camera.matrix(surface), flight.position(time), time, SUN)
    }

    renderer.pass(
      RenderPassDescriptor {
        camera,
        depth: Depth.readOnly(),
        blend: Blend.alpha(),
      },
    ) {
      drawSpaceDust(pass, dust)
    }

    renderer.pass(
      RenderPassDescriptor {
        camera: Camera.screen(),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      },
    ) {
      drawHud(pass, hud)
    }
  }

  app.run() else error {
    println(error)
    return 1
  }

  return 0
}
