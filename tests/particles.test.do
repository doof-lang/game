import { Assert } from "std/assert"
import { approxEqual } from "std/math"

import {
  Fireworks,
  FireworksConfig,
  ParticleConfig,
  ParticleLayer,
  ParticleLayerConfig,
  initGameApp,
} from "../index"

function assertApprox(actual: double, expected: double, tolerance: double = 0.000001): void {
  Assert.isTrue(approxEqual(actual, expected, tolerance), "expected ${actual} to approximately equal ${expected}")
}

function testLayer(capacity: int = 16): ParticleLayer {
  app := initGameApp{ title: "Doof Game Particle Tests" }
  return ParticleLayer(app.surface, ParticleLayerConfig { capacity })
}

export function testEmitIncreasesActiveCount(): void {
  layer := testLayer()
  layer.emit(ParticleConfig { count: 3, lifetime: 1.0, size: 4.0 })
  Assert.equal(layer.activeCount(), 3)
  Assert.isTrue(layer.isActive())
}

export function testUpdateExpiresParticlesAfterLifetime(): void {
  layer := testLayer()
  layer.emit(ParticleConfig { count: 4, lifetime: 0.25, size: 4.0 })

  Assert.isTrue(layer.update(0.1))
  Assert.equal(layer.activeCount(), 4)

  Assert.isFalse(layer.update(0.2))
  Assert.equal(layer.activeCount(), 0)
  Assert.isFalse(layer.isActive())
}

export function testClearRemovesLiveParticles(): void {
  layer := testLayer()
  layer.emit(ParticleConfig { count: 5, lifetime: 2.0, size: 4.0 })
  layer.clear()

  Assert.equal(layer.activeCount(), 0)
  Assert.isFalse(layer.isActive())
}

export function testSeededEmissionIsDeterministic(): void {
  first := testLayer()
  second := testLayer()
  config := ParticleConfig {
    count: 4,
    seed: 99,
    x: 120.0,
    y: 80.0,
    positionJitterX: 24.0,
    positionJitterY: 18.0,
    minSpeed: 10.0,
    maxSpeed: 40.0,
    lifetime: 1.0,
    size: 4.0,
  }

  first.emit(config)
  second.emit(config)

  p0 := first.debugParticlePosition(0)
  p1 := second.debugParticlePosition(0)
  assertApprox(p0.x, p1.x)
  assertApprox(p0.y, p1.y)
  assertApprox(p0.z, p1.z)
}

export function testFireworksStartCreatesParticlesAndEventuallyFinishes(): void {
  app := initGameApp{ title: "Doof Game Fireworks Tests" }
  fireworks := Fireworks(
    app.surface,
    FireworksConfig {
      burstCount: 2,
      particlesPerBurst: 8,
      duration: 0.4,
      sparkleCount: 0,
      finaleBurstCount: 0,
      seed: 5,
    },
  )

  fireworks.start(800.0, 600.0)
  Assert.equal(fireworks.activeCount(), 18)
  Assert.isTrue(fireworks.isActive())

  fireworks.update(0.4)
  Assert.isTrue(fireworks.activeCount() > 0)

  fireworks.update(1.0)
  Assert.equal(fireworks.activeCount(), 0)
  Assert.isFalse(fireworks.isActive())
}

export function testFireworksStaggersBurstsAndAddsFinale(): void {
  app := initGameApp{ title: "Doof Game Fireworks More Tests" }
  fireworks := Fireworks(
    app.surface,
    FireworksConfig {
      burstCount: 3,
      particlesPerBurst: 6,
      duration: 1.0,
      sparkleCount: 0,
      finaleBurstCount: 2,
      finaleParticlesPerBurst: 5,
      seed: 7,
    },
  )

  fireworks.start(800.0, 600.0)
  firstCount := fireworks.activeCount()
  Assert.equal(firstCount, 16)

  fireworks.update(0.4)
  Assert.isTrue(fireworks.activeCount() > firstCount)

  fireworks.update(0.45)
  Assert.isTrue(fireworks.activeCount() > 28)
}
