import { SimpleModel, drawSimpleModel } from "./model"
import { SimpleModelBatch, drawSimpleModelBatch } from "./model_batch"
import { RenderPass } from "./render"
import { GameEvent } from "./event"

export type SceneTickHandler = (tick: SceneTick): none
export type SceneUpdateHandler = (update: SceneUpdate): none
export type SceneEventHandler = (event: GameEvent): none

enum SceneNodeKind {
  SimpleModel,
  SimpleModelBatch,
}

export class SceneTick {
  scene: Scene
  readonly deltaSeconds: double
  readonly tickIndex: long
}

export class SceneUpdate {
  scene: Scene
  readonly deltaSeconds: double
  readonly elapsedSeconds: double
  readonly tickAlpha: double | none
}

export class SceneNode {
  readonly name: string | none
  onTick: SceneTickHandler | none = none
  onUpdate: SceneUpdateHandler | none = none
  onEvent: SceneEventHandler | none = none

  private readonly kind: SceneNodeKind
  private model: SimpleModel | none = none
  private batch: SimpleModelBatch | none = none
  private let removed: bool = false

  remove(): none {
    removed = true
  }

  isRemoved(): bool => removed
}

export class Scene {
  readonly ticksPerSecond: double | none
  readonly maxDeltaSeconds: double

  private let nodes: SceneNode[] = []
  private let tickAccumulator: double = 0.0
  private let nextTickIndex: long = 0L
  private let elapsedSceneSeconds: double = 0.0

  static constructor(
    ticksPerSecond: double | none = none,
    maxDeltaSeconds: double = 0.25,
  ): Scene {
    if maxDeltaSeconds <= 0.0 {
      panic("Scene maxDeltaSeconds must be positive")
    }

    tickRate := ticksPerSecond as double else {
      return Scene { ticksPerSecond, maxDeltaSeconds }
    }
    if tickRate <= 0.0 {
      panic("Scene ticksPerSecond must be positive")
    }

    return Scene { ticksPerSecond, maxDeltaSeconds }
  }

  addSimpleModel(
    model: SimpleModel,
    name: string | none = none,
    onTick: SceneTickHandler | none = none,
    onUpdate: SceneUpdateHandler | none = none,
    onEvent: SceneEventHandler | none = none,
  ): SceneNode {
    node := SceneNode {
      name,
      onTick,
      onUpdate,
      onEvent,
      kind: SceneNodeKind.SimpleModel,
      model,
    }
    nodes.push(node)
    return node
  }

  addSimpleModelBatch(
    batch: SimpleModelBatch,
    name: string | none = none,
    onTick: SceneTickHandler | none = none,
    onUpdate: SceneUpdateHandler | none = none,
    onEvent: SceneEventHandler | none = none,
  ): SceneNode {
    node := SceneNode {
      name,
      onTick,
      onUpdate,
      onEvent,
      kind: SceneNodeKind.SimpleModelBatch,
      batch,
    }
    nodes.push(node)
    return node
  }

  remove(node: SceneNode): bool {
    if node.isRemoved() {
      return false
    }

    for attached of nodes {
      if attached == node {
        node.remove()
        return true
      }
    }
    return false
  }

  update(deltaSeconds: double): none {
    if deltaSeconds < 0.0 {
      panic("Scene deltaSeconds must be non-negative")
    }

    frameDelta := if deltaSeconds > maxDeltaSeconds then maxDeltaSeconds else deltaSeconds
    snapshotLength := nodes.length
    runFixedTicks(snapshotLength, frameDelta)

    elapsedSceneSeconds += frameDelta
    updateEvent := SceneUpdate {
      scene: this,
      deltaSeconds: frameDelta,
      elapsedSeconds: elapsedSceneSeconds,
      tickAlpha: currentTickAlpha(),
    }
    for index of 0..<snapshotLength {
      node := nodes[index]
      if !node.isRemoved() {
        handler := node.onUpdate as SceneUpdateHandler else { continue }
        handler.call(updateEvent)
      }
    }

    compactRemovedNodes()
  }

  handleEvent(event: GameEvent): none {
    snapshotLength := nodes.length
    for index of 0..<snapshotLength {
      node := nodes[index]
      if !node.isRemoved() {
        handler := node.onEvent as SceneEventHandler else { continue }
        handler.call(event)
      }
    }

    compactRemovedNodes()
  }

  draw(pass: RenderPass): none {
    for node of nodes {
      if !node.isRemoved() {
        drawNode(pass, node)
      }
    }
  }

  frame(pass: RenderPass, deltaSeconds: double): none {
    update(deltaSeconds)
    draw(pass)
  }

  private runFixedTicks(snapshotLength: int, frameDelta: double): none {
    tickRate := ticksPerSecond as double else { return }
    tickSeconds := 1.0 / tickRate
    tickAccumulator += frameDelta

    while tickAccumulator >= tickSeconds {
      tickAccumulator -= tickSeconds
      nextTickIndex += 1L
      tick := SceneTick {
        scene: this,
        deltaSeconds: tickSeconds,
        tickIndex: nextTickIndex,
      }

      for index of 0..<snapshotLength {
        node := nodes[index]
        if !node.isRemoved() {
          handler := node.onTick as SceneTickHandler else { continue }
          handler.call(tick)
        }
      }
    }
  }

  private currentTickAlpha(): double | none {
    tickRate := ticksPerSecond as double else { return none }
    return tickAccumulator / (1.0 / tickRate)
  }

  private drawNode(pass: RenderPass, node: SceneNode): none {
    case node.kind {
      SceneNodeKind.SimpleModel -> drawSimpleModel(pass, node.model!)
      SceneNodeKind.SimpleModelBatch -> drawSimpleModelBatch(pass, node.batch!)
    }
  }

  private compactRemovedNodes(): none {
    retained: SceneNode[] := []
    for node of nodes {
      if !node.isRemoved() {
        retained.push(node)
      }
    }
    nodes = retained
  }
}
