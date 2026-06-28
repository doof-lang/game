mock import for "../scene" {
  "./model" => "./scene_model.mock",
  "./model_batch" => "./scene_model_batch.mock",
  "./render" => "./scene_render.mock"
}

import { Assert } from "std/assert"
import { approxEqual } from "std/math"

import { Scene, SceneNode, SceneTick, SceneUpdate } from "../scene"
import { SimpleModel } from "./scene_model.mock"

function assertApprox(actual: double, expected: double, message: string | null = null): void {
  Assert.isTrue(approxEqual(actual, expected), message)
}

export function testSceneWithoutFixedTicksRunsOnlyUpdates(): void {
  scene := Scene { ticksPerSecond: null, maxDeltaSeconds: 10.0 }
  let tickCount = 0
  let updateCount = 0
  let updateDelta = 0.0
  let elapsed = 0.0
  let sawNullAlpha = false

  scene.addSimpleModel{
    model: SimpleModel(),
    onTick: (tick: SceneTick): void => {
      tickCount += 1
    },
    onUpdate: (update: SceneUpdate): void => {
      updateCount += 1
      updateDelta = update.deltaSeconds
      elapsed = update.elapsedSeconds
      sawNullAlpha = update.tickAlpha == null
    },
  }

  scene.update(1.5)

  Assert.equal(tickCount, 0)
  Assert.equal(updateCount, 1)
  assertApprox(updateDelta, 1.5)
  assertApprox(elapsed, 1.5)
  Assert.isTrue(sawNullAlpha)
}

export function testSceneFixedTicksAndAlpha(): void {
  scene := Scene { ticksPerSecond: 4.0, maxDeltaSeconds: 10.0 }
  tickDeltas: double[] := []
  tickIndices: long[] := []
  updateAlphas: double[] := []
  updateElapsed: double[] := []

  scene.addSimpleModel{
    model: SimpleModel(),
    onTick: (tick: SceneTick): void => {
      tickDeltas.push(tick.deltaSeconds)
      tickIndices.push(tick.tickIndex)
    },
    onUpdate: (update: SceneUpdate): void => {
      alpha := update.tickAlpha as double else {
        Assert.fail("expected tick alpha")
        return
      }
      updateAlphas.push(alpha)
      updateElapsed.push(update.elapsedSeconds)
    },
  }

  scene.update(0.125)
  scene.update(0.125)

  Assert.equal(tickDeltas.length, 1)
  assertApprox(tickDeltas[0], 0.25)
  Assert.equal(tickIndices[0], 1L)
  assertApprox(updateAlphas[0], 0.5)
  assertApprox(updateAlphas[1], 0.0)
  assertApprox(updateElapsed[1], 0.25)
}

export function testSceneMaxDeltaSecondsCapsSceneTime(): void {
  scene := Scene { ticksPerSecond: 10.0, maxDeltaSeconds: 0.15 }
  let tickCount = 0
  let updateDelta = 0.0
  let elapsed = 0.0
  let alpha = 0.0

  scene.addSimpleModel{
    model: SimpleModel(),
    onTick: (tick: SceneTick): void => {
      tickCount += 1
    },
    onUpdate: (update: SceneUpdate): void => {
      updateDelta = update.deltaSeconds
      elapsed = update.elapsedSeconds
      alpha = update.tickAlpha!
    },
  }

  scene.update(1.0)

  Assert.equal(tickCount, 1)
  assertApprox(updateDelta, 0.15)
  assertApprox(elapsed, 0.15)
  assertApprox(alpha, 0.5)
}

export function testSceneUpdateCallbacksRunInInsertionOrder(): void {
  scene := Scene { maxDeltaSeconds: 10.0 }
  order: int[] := []

  scene.addSimpleModel{ model: SimpleModel(), onUpdate: (update: SceneUpdate): void => order.push(1) }
  scene.addSimpleModel{ model: SimpleModel(), onUpdate: (update: SceneUpdate): void => order.push(2) }
  scene.addSimpleModel{ model: SimpleModel(), onUpdate: (update: SceneUpdate): void => order.push(3) }

  scene.update(0.5)

  Assert.equal(order.length, 3)
  Assert.equal(order[0], 1)
  Assert.equal(order[1], 2)
  Assert.equal(order[2], 3)
}

export function testSceneRemoveIsIdempotent(): void {
  scene := Scene {}
  node := scene.addSimpleModel{ model: SimpleModel(), name: "ship" }

  Assert.equal(node.name, "ship")
  Assert.isFalse(node.isRemoved())
  Assert.isTrue(scene.remove(node))
  Assert.isTrue(node.isRemoved())
  Assert.isFalse(scene.remove(node))

  node.remove()
  Assert.isTrue(node.isRemoved())
}

export function testSceneMutationDuringCallbacksUsesSnapshotSemantics(): void {
  scene := Scene { ticksPerSecond: 10.0, maxDeltaSeconds: 10.0 }
  let lateTicks = 0
  let lateUpdates = 0
  let first: SceneNode | null = null

  first = scene.addSimpleModel{
    model: SimpleModel(),
    onTick: (tick: SceneTick): void => {
      scene.addSimpleModel{
        model: SimpleModel(),
        onTick: (lateTick: SceneTick): void => {
          lateTicks += 1
        },
        onUpdate: (lateUpdate: SceneUpdate): void => {
          lateUpdates += 1
        },
      }
      first!.remove()
    },
    onUpdate: (update: SceneUpdate): void => {
      Assert.fail("removed node should not receive update")
    },
  }

  scene.update(0.1)
  Assert.equal(lateTicks, 0)
  Assert.equal(lateUpdates, 0)

  scene.update(0.1)
  Assert.equal(lateTicks, 1)
  Assert.equal(lateUpdates, 1)
}

export function testSceneRemovalDuringCallbackSuppressesLaterCallbacks(): void {
  scene := Scene { ticksPerSecond: 10.0, maxDeltaSeconds: 10.0 }
  let firstTicks = 0
  let secondTicks = 0
  let secondUpdates = 0
  let second: SceneNode | null = null

  scene.addSimpleModel{
    model: SimpleModel(),
    onTick: (tick: SceneTick): void => {
      firstTicks += 1
      second!.remove()
    },
  }
  second = scene.addSimpleModel{
    model: SimpleModel(),
    onTick: (tick: SceneTick): void => {
      secondTicks += 1
    },
    onUpdate: (update: SceneUpdate): void => {
      secondUpdates += 1
    },
  }

  scene.update(0.1)

  Assert.equal(firstTicks, 1)
  Assert.equal(secondTicks, 0)
  Assert.equal(secondUpdates, 0)
}
