import { floor, sin } from "std/math"
import { Color, RenderPass } from "./render"
import { GameSurface } from "./surface"
import { ParticleConfig, ParticleLayer, ParticleLayerConfig } from "./particles"

readonly TAU_VALUE = 6.283185307179586

function maxDouble(a: double, b: double): double {
  return if a > b then a else b
}

function randomUnit(index: int, seed: int, salt: double): double {
  value := sin((double(index) + 1.0) * 12.9898 + double(seed) * 78.233 + salt * 37.719) * 43758.5453123
  return value - floor(value)
}

export class FireworksConfig {
  burstCount: int = 8
  particlesPerBurst: int = 96
  duration: double = 3.4
  gravity: double = 220.0
  minRadius: double = 120.0
  maxRadius: double = 330.0
  sparkleInterval: double = 0.075
  sparkleCount: int = 18
  finaleBurstCount: int = 5
  finaleParticlesPerBurst: int = 88
  seed: int = 41
  palette: Color[] = [
    Color(1.0, 0.24, 0.18, 1.0),
    Color(1.0, 0.78, 0.20, 1.0),
    Color(0.28, 0.86, 1.0, 1.0),
    Color(0.38, 1.0, 0.48, 1.0),
    Color(0.95, 0.42, 1.0, 1.0),
    Color(1.0, 1.0, 0.88, 1.0),
  ]
}

export class Fireworks {
  private layer: ParticleLayer
  config: FireworksConfig
  private elapsed: double = 0.0
  private active: bool = false
  private width: double = 1.0
  private height: double = 1.0
  private emittedBursts: int = 0
  private sparkleTime: double = 0.0
  private finaleEmitted: bool = false

  static constructor(surface: GameSurface, config: FireworksConfig = FireworksConfig {}): Fireworks {
    if config.burstCount <= 0 {
      panic("Fireworks burst count must be positive")
    }
    if config.particlesPerBurst <= 0 {
      panic("Fireworks particles per burst must be positive")
    }
    if config.sparkleInterval <= 0.0 {
      panic("Fireworks sparkle interval must be positive")
    }
    if config.sparkleCount < 0 {
      panic("Fireworks sparkle count must be non-negative")
    }
    if config.finaleBurstCount < 0 {
      panic("Fireworks finale burst count must be non-negative")
    }
    if config.finaleParticlesPerBurst <= 0 {
      panic("Fireworks finale particles per burst must be positive")
    }
    if config.palette.length == 0 {
      panic("Fireworks palette must contain at least one color")
    }

    capacity := config.burstCount * (config.particlesPerBurst + 10) +
      config.finaleBurstCount * (config.finaleParticlesPerBurst + 10) +
      config.sparkleCount * 96
    layer := ParticleLayer(surface, ParticleLayerConfig { capacity: capacity })
    return Fireworks { layer: layer, config: config }
  }

  activeCount(): int => layer.activeCount()

  isActive(): bool => active || layer.isActive()

  clear(): void {
    layer.clear()
    elapsed = 0.0
    active = false
    emittedBursts = 0
    sparkleTime = 0.0
    finaleEmitted = false
  }

  start(width: double, height: double): void {
    clear()
    this.width = maxDouble(width, 1.0)
    this.height = maxDouble(height, 1.0)
    active = true
    emitDueBursts()
  }

  private burstProgress(index: int): double {
    if config.burstCount <= 1 {
      return 0.0
    }
    return double(index) / double(config.burstCount - 1)
  }

  private emitDueBursts(): void {
    while emittedBursts < config.burstCount && elapsed >= burstProgress(emittedBursts) * config.duration * 0.78 {
      emitBurst(emittedBursts, config.particlesPerBurst, 1.0, 1.0)
      emittedBursts += 1
    }
  }

  private emitBurst(index: int, count: int, radiusScale: double, lifetimeScale: double): void {
    burstSeed := config.seed + index * 101
    centerX := width * (0.12 + randomUnit(index, config.seed, 11.0) * 0.76)
    centerY := height * (0.12 + randomUnit(index, config.seed, 12.0) * 0.46)
    radius := (config.minRadius + randomUnit(index, config.seed, 13.0) * (config.maxRadius - config.minRadius)) * radiusScale
    color := config.palette[index % config.palette.length]
    layer.emit(
      ParticleConfig {
        count: count,
        seed: burstSeed,
        x: centerX,
        y: centerY,
        minAngle: 0.0,
        maxAngle: TAU_VALUE,
        minSpeed: radius * 0.45,
        maxSpeed: radius,
        accelerationY: config.gravity,
        lifetime: config.duration * lifetimeScale * (0.45 + randomUnit(index, config.seed, 14.0) * 0.16),
        lifetimeJitter: config.duration * 0.12,
        size: 6.5,
        sizeJitter: 3.5,
        color: color,
        fade: true,
      },
    )
    emitFlash(index, centerX, centerY, color)
  }

  private emitFlash(index: int, x: double, y: double, color: Color): void {
    layer.emit(
      ParticleConfig {
        count: 10,
        seed: config.seed + index * 509,
        x: x,
        y: y,
        positionJitterX: 10.0,
        positionJitterY: 10.0,
        minSpeed: 0.0,
        maxSpeed: 22.0,
        accelerationY: config.gravity * 0.15,
        lifetime: 0.22,
        lifetimeJitter: 0.08,
        size: 13.0,
        sizeJitter: 5.0,
        color: color,
        fade: true,
      },
    )
  }

  private emitSparkles(): void {
    sparkleSeed := config.seed + int(elapsed * 1000.0) + emittedBursts * 37
    x := width * (0.08 + randomUnit(sparkleSeed, config.seed, 21.0) * 0.84)
    y := height * (0.08 + randomUnit(sparkleSeed, config.seed, 22.0) * 0.20)
    color := config.palette[sparkleSeed % config.palette.length]
    layer.emit(
      ParticleConfig {
        count: config.sparkleCount,
        seed: sparkleSeed,
        x: x,
        y: y,
        positionJitterX: width * 0.035,
        positionJitterY: 8.0,
        minAngle: 1.15,
        maxAngle: 1.99,
        minSpeed: 70.0,
        maxSpeed: 185.0,
        accelerationY: config.gravity * 0.55,
        lifetime: 0.85,
        lifetimeJitter: 0.28,
        size: 3.5,
        sizeJitter: 1.8,
        color: color,
        fade: true,
      },
    )
  }

  private emitFinale(): void {
    for index of 0..<config.finaleBurstCount {
      emitBurst(config.burstCount + index, config.finaleParticlesPerBurst, 1.18, 0.72)
    }
  }

  update(deltaTime: double): bool {
    layer.update(deltaTime)

    if active {
      elapsed += deltaTime
      emitDueBursts()

      sparkleTime += deltaTime
      while sparkleTime >= config.sparkleInterval {
        sparkleTime -= config.sparkleInterval
        if config.sparkleCount > 0 {
          emitSparkles()
        }
      }

      if !finaleEmitted && elapsed >= config.duration * 0.82 {
        emitFinale()
        finaleEmitted = true
      }

      if elapsed >= config.duration {
        active = false
      }
    }
    return isActive()
  }

  draw(pass: RenderPass): void {
    layer.draw(pass)
  }
}
