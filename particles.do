import { clamp, cos, floor, sin } from "std/math"
import { GameSurface } from "./surface"
import { Color, Point3, RenderPass } from "./render"
import { SimpleMesh, SimpleMeshBuilder, SimpleMeshLighting } from "./mesh"
import { SimpleModelBatch, SimpleModelInstance, drawSimpleModelBatch } from "./model_batch"
import { Transform, Vec3 } from "./transform"

export class ParticleLayerConfig {
  capacity: int = 512
}

export class ParticleConfig {
  count: int = 1
  seed: int = 1
  x: double = 0.0
  y: double = 0.0
  z: double = 0.0
  positionJitterX: double = 0.0
  positionJitterY: double = 0.0
  minAngle: double = 0.0
  maxAngle: double = 6.283185307179586
  minSpeed: double = 0.0
  maxSpeed: double = 0.0
  accelerationX: double = 0.0
  accelerationY: double = 0.0
  lifetime: double = 1.0
  lifetimeJitter: double = 0.0
  size: double = 5.0
  sizeJitter: double = 0.0
  color: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }
  fade: bool = true
}

class ParticleState {
  active: bool = false
  x: double = 0.0
  y: double = 0.0
  z: double = 0.0
  vx: double = 0.0
  vy: double = 0.0
  ax: double = 0.0
  ay: double = 0.0
  age: double = 0.0
  lifetime: double = 1.0
  size: double = 1.0
  color: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }
  fade: bool = true
}

function createParticleMesh(surface: GameSurface): SimpleMesh {
  builder := SimpleMeshBuilder.create()
  builder.quad{
    a: Point3(-0.5, -0.5, 0.0),
    b: Point3(0.5, -0.5, 0.0),
    c: Point3(0.5, 0.5, 0.0),
    d: Point3(-0.5, 0.5, 0.0),
    color: Color.white,
  }
  return builder.build(surface)
}

function randomUnit(index: int, seed: int, salt: double): double {
  value := sin((double(index) + 1.0) * 12.9898 + double(seed) * 78.233 + salt * 37.719) * 43758.5453123
  return value - floor(value)
}

function randomSigned(index: int, seed: int, salt: double): double {
  return randomUnit(index, seed, salt) * 2.0 - 1.0
}

function maxDouble(a: double, b: double): double {
  return if a > b then a else b
}

function particleTransform(particle: ParticleState): Transform {
  return Transform.identity()
    .withPosition(Point3(particle.x, particle.y, particle.z))
    .withScale(Vec3.xyz(particle.size, particle.size, 1.0))
}

function hiddenTransform(): Transform {
  return Transform.identity().withScale(Vec3.zero)
}

export class ParticleLayer {
  readonly surface: GameSurface
  readonly capacity: int
  private states: ParticleState[] = []
  private instances: SimpleModelInstance[] = []
  private batch: SimpleModelBatch
  private active: int = 0
  private cursor: int = 0

  static constructor(surface: GameSurface, config: ParticleLayerConfig = ParticleLayerConfig {}): ParticleLayer {
    if config.capacity <= 0 {
      panic("ParticleLayer capacity must be positive")
    }

    mesh := createParticleMesh(surface)
    batch := SimpleModelBatch {
      surface: surface,
      mesh: mesh,
      capacity: config.capacity,
    }
    layer := ParticleLayer { surface: surface, capacity: config.capacity, batch: batch }
    for index of 0..<config.capacity {
      state := ParticleState {}
      layer.states.push(state)
      layer.instances.push(batch.add{ transform: hiddenTransform(), tint: Color.transparent })
    }
    return layer
  }

  activeCount(): int => active

  isActive(): bool => active > 0

  clear(): void {
    for index of 0..<states.length {
      if states[index].active {
        states[index].active = false
        instances[index].setTransform(hiddenTransform())
        instances[index].setTint(Color.transparent)
      }
    }
    active = 0
    cursor = 0
  }

  emit(config: ParticleConfig): void {
    if config.count <= 0 {
      return
    }
    if config.lifetime <= 0.0 {
      panic("Particle lifetime must be positive")
    }
    if config.size <= 0.0 {
      panic("Particle size must be positive")
    }

    angleSpan := config.maxAngle - config.minAngle
    speedSpan := config.maxSpeed - config.minSpeed
    for index of 0..<config.count {
      slot := nextSlot()
      particle := states[slot]
      if !particle.active {
        active += 1
      }

      angle := config.minAngle + randomUnit(index, config.seed, 1.1) * angleSpan
      speed := config.minSpeed + randomUnit(index, config.seed, 2.2) * speedSpan
      lifetime := maxDouble(0.001, config.lifetime + randomSigned(index, config.seed, 3.3) * config.lifetimeJitter)
      size := maxDouble(0.001, config.size + randomSigned(index, config.seed, 4.4) * config.sizeJitter)

      particle.active = true
      particle.x = config.x + randomSigned(index, config.seed, 5.5) * config.positionJitterX
      particle.y = config.y + randomSigned(index, config.seed, 6.6) * config.positionJitterY
      particle.z = config.z
      particle.vx = cos(angle) * speed
      particle.vy = sin(angle) * speed
      particle.ax = config.accelerationX
      particle.ay = config.accelerationY
      particle.age = 0.0
      particle.lifetime = lifetime
      particle.size = size
      particle.color = config.color
      particle.fade = config.fade
      syncSlot(slot)
    }
  }

  private nextSlot(): int {
    slot := cursor
    cursor = (cursor + 1) % capacity
    return slot
  }

  private syncSlot(index: int): void {
    particle := states[index]
    if !particle.active {
      instances[index].setTransform(hiddenTransform())
      instances[index].setTint(Color.transparent)
      return
    }

    let alpha = particle.color.a
    if particle.fade {
      t := clamp(particle.age / particle.lifetime, 0.0, 1.0)
      alpha = alpha * (1.0 - t)
    }

    instances[index].setTransform(particleTransform(particle))
    instances[index].setTint(Color(particle.color.r, particle.color.g, particle.color.b, alpha))
  }

  update(deltaTime: double): bool {
    if deltaTime < 0.0 {
      panic("Particle update deltaTime must be non-negative")
    }

    for index of 0..<states.length {
      particle := states[index]
      if particle.active {
        particle.age += deltaTime
        if particle.age >= particle.lifetime {
          particle.active = false
          active -= 1
        } else {
          particle.vx += particle.ax * deltaTime
          particle.vy += particle.ay * deltaTime
          particle.x += particle.vx * deltaTime
          particle.y += particle.vy * deltaTime
        }
        syncSlot(index)
      }
    }
    return isActive()
  }

  draw(pass: RenderPass): void {
    drawSimpleModelBatch(
      pass,
      batch,
      SimpleMeshLighting {
        ambient: 1.0,
        directional: 0.0,
        direction: Point3(0.0, 0.0, 1.0),
      },
    )
  }

  debugParticlePosition(index: int): Point3 {
    particle := states[index]
    return Point3(particle.x, particle.y, particle.z)
  }
}
