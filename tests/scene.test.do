mock import for "../scene" {
  "./event" => "./scene_event.mock",
  "./model" => "./scene_model.mock",
  "./model_batch" => "./scene_model_batch.mock",
  "./render" => "./scene_render.mock"
}

import { Assert } from "std/assert"
import { approxEqual } from "std/math"

import { Scene, SceneNode, SceneTick, SceneUpdate } from "../scene"
import { GameEvent } from "./scene_event.mock"
import { SimpleModel } from "./scene_model.mock"

function assertApprox(actual: double, expected: double, message: string | none = none): none {
  Assert.isTrue(approxEqual(actual, expected), message)
}

export function testSceneWithoutFixedTicksRunsOnlyUpdates(): none {
  scene := Scene { ticksPerSecond: none, maxDeltaSeconds: 10.0 }
  let tickCount = 0
  let updateCount = 0
  let updateDelta = 0.0
  let elapsed = 0.0
  let sawNullAlpha = false

  scene.addSimpleModel{
    model: SimpleModel(),
    onTick: (tick: SceneTick): none => {
      tickCount += 1
    },
    onUpdate: (update: SceneUpdate): none => {
      updateCount += 1
      updateDelta = update.deltaSeconds
      elapsed = update.elapsedSeconds
      sawNullAlpha = update.tickAlpha == none
    },
  }

  scene.update(1.5)

  Assert.equal(tickCount, 0)
  Assert.equal(updateCount, 1)
  assertApprox(updateDelta, 1.5)
  assertApprox(elapsed, 1.5)
  Assert.isTrue(sawNullAlpha)
}

export function testSceneFixedTicksAndAlpha(): none {
  scene := Scene { ticksPerSecond: 4.0, maxDeltaSeconds: 10.0 }
  tickDeltas: double[] := []
  tickIndices: long[] := []
  updateAlphas: double[] := []
  updateElapsed: double[] := []

  scene.addSimpleModel{
    model: SimpleModel(),
    onTick: (tick: SceneTick): none => {
      tickDeltas.push(tick.deltaSeconds)
      tickIndices.push(tick.tickIndex)
    },
    onUpdate: (update: SceneUpdate): none => {
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

export function testSceneMaxDeltaSecondsCapsSceneTime(): none {
  scene := Scene { ticksPerSecond: 10.0, maxDeltaSeconds: 0.15 }
  let tickCount = 0
  let updateDelta = 0.0
  let elapsed = 0.0
  let alpha = 0.0

  scene.addSimpleModel{
    model: SimpleModel(),
    onTick: (tick: SceneTick): none => {
      tickCount += 1
    },
    onUpdate: (update: SceneUpdate): none => {
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

export function testSceneUpdateCallbacksRunInInsertionOrder(): none {
  scene := Scene { maxDeltaSeconds: 10.0 }
  order: int[] := []

  scene.addSimpleModel{ model: SimpleModel(), onUpdate: (update: SceneUpdate): none => order.push(1) }
  scene.addSimpleModel{ model: SimpleModel(), onUpdate: (update: SceneUpdate): none => order.push(2) }
  scene.addSimpleModel{ model: SimpleModel(), onUpdate: (update: SceneUpdate): none => order.push(3) }

  scene.update(0.5)

  Assert.equal(order.length, 3)
  Assert.equal(order[0], 1)
  Assert.equal(order[1], 2)
  Assert.equal(order[2], 3)
}

export function testSceneEventCallbacksReceiveForwardedEvent(): none {
  scene := Scene {}
  event := GameEvent { label: "pressed" }
  let receivedLabel = ""
  let ignoredNodeUpdateCount = 0

  scene.addSimpleModel{
    model: SimpleModel(),
    onUpdate: (update: SceneUpdate): none => {
      ignoredNodeUpdateCount += 1
    },
  }
  scene.addSimpleModel{
    model: SimpleModel(),
    onEvent: (forwarded: GameEvent): none => {
      receivedLabel = forwarded.label
    },
  }

  scene.handleEvent(event)

  Assert.equal(receivedLabel, "pressed")
  Assert.equal(ignoredNodeUpdateCount, 0)
}

export function testSceneEventCallbacksRunInInsertionOrder(): none {
  scene := Scene {}
  order: int[] := []

  scene.addSimpleModel{ model: SimpleModel(), onEvent: (event: GameEvent): none => order.push(1) }
  scene.addSimpleModel{ model: SimpleModel(), onEvent: (event: GameEvent): none => order.push(2) }
  scene.addSimpleModel{ model: SimpleModel(), onEvent: (event: GameEvent): none => order.push(3) }

  scene.handleEvent(GameEvent {})

  Assert.equal(order.length, 3)
  Assert.equal(order[0], 1)
  Assert.equal(order[1], 2)
  Assert.equal(order[2], 3)
}

export function testSceneEventMutationDuringCallbacksUsesSnapshotSemantics(): none {
  scene := Scene {}
  let lateEvents = 0
  let first: SceneNode | none = none

  first = scene.addSimpleModel{
    model: SimpleModel(),
    onEvent: (event: GameEvent): none => {
      scene.addSimpleModel{
        model: SimpleModel(),
        onEvent: (lateEvent: GameEvent): none => {
          lateEvents += 1
        },
      }
      first!.remove()
    },
  }

  scene.handleEvent(GameEvent {})
  Assert.equal(lateEvents, 0)

  scene.handleEvent(GameEvent {})
  Assert.equal(lateEvents, 1)
}

export function testSceneEventRemovalDuringCallbackSuppressesLaterCallbacks(): none {
  scene := Scene {}
  let firstEvents = 0
  let secondEvents = 0
  let second: SceneNode | none = none

  scene.addSimpleModel{
    model: SimpleModel(),
    onEvent: (event: GameEvent): none => {
      firstEvents += 1
      second!.remove()
    },
  }
  second = scene.addSimpleModel{
    model: SimpleModel(),
    onEvent: (event: GameEvent): none => {
      secondEvents += 1
    },
  }

  scene.handleEvent(GameEvent {})

  Assert.equal(firstEvents, 1)
  Assert.equal(secondEvents, 0)
}

export function testSceneRemoveIsIdempotent(): none {
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

export function testSceneMutationDuringCallbacksUsesSnapshotSemantics(): none {
  scene := Scene { ticksPerSecond: 10.0, maxDeltaSeconds: 10.0 }
  let lateTicks = 0
  let lateUpdates = 0
  let first: SceneNode | none = none

  first = scene.addSimpleModel{
    model: SimpleModel(),
    onTick: (tick: SceneTick): none => {
      scene.addSimpleModel{
        model: SimpleModel(),
        onTick: (lateTick: SceneTick): none => {
          lateTicks += 1
        },
        onUpdate: (lateUpdate: SceneUpdate): none => {
          lateUpdates += 1
        },
      }
      first!.remove()
    },
    onUpdate: (update: SceneUpdate): none => {
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

export function testSceneRemovalDuringCallbackSuppressesLaterCallbacks(): none {
  scene := Scene { ticksPerSecond: 10.0, maxDeltaSeconds: 10.0 }
  let firstTicks = 0
  let secondTicks = 0
  let secondUpdates = 0
  let second: SceneNode | none = none

  scene.addSimpleModel{
    model: SimpleModel(),
    onTick: (tick: SceneTick): none => {
      firstTicks += 1
      second!.remove()
    },
  }
  second = scene.addSimpleModel{
    model: SimpleModel(),
    onTick: (tick: SceneTick): none => {
      secondTicks += 1
    },
    onUpdate: (update: SceneUpdate): none => {
      secondUpdates += 1
    },
  }

  scene.update(0.1)

  Assert.equal(firstTicks, 1)
  Assert.equal(secondTicks, 0)
  Assert.equal(secondUpdates, 0)
}
