import { SimpleModel, drawSimpleModel } from "./model"
import { SimpleModelBatch, drawSimpleModelBatch } from "./model_batch"
import { RenderPass } from "./render"

export type SceneTickHandler = (tick: SceneTick): void
export type SceneUpdateHandler = (update: SceneUpdate): void

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
  readonly tickAlpha: double | null
}

export class SceneNode {
  readonly name: string | null
  onTick: SceneTickHandler | null = null
  onUpdate: SceneUpdateHandler | null = null

  private readonly kind: SceneNodeKind
  private model: SimpleModel | null = null
  private batch: SimpleModelBatch | null = null
  private removed: bool = false

  remove(): void {
    removed = true
  }

  isRemoved(): bool => removed
}

export class Scene {
  readonly ticksPerSecond: double | null
  readonly maxDeltaSeconds: double

  private nodes: SceneNode[] = []
  private tickAccumulator: double = 0.0
  private nextTickIndex: long = 0L
  private elapsedSceneSeconds: double = 0.0

  static constructor(
    ticksPerSecond: double | null = null,
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
    name: string | null = null,
    onTick: SceneTickHandler | null = null,
    onUpdate: SceneUpdateHandler | null = null,
  ): SceneNode {
    node := SceneNode {
      name,
      onTick,
      onUpdate,
      kind: SceneNodeKind.SimpleModel,
      model,
    }
    nodes.push(node)
    return node
  }

  addSimpleModelBatch(
    batch: SimpleModelBatch,
    name: string | null = null,
    onTick: SceneTickHandler | null = null,
    onUpdate: SceneUpdateHandler | null = null,
  ): SceneNode {
    node := SceneNode {
      name,
      onTick,
      onUpdate,
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

  update(deltaSeconds: double): void {
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

  draw(pass: RenderPass): void {
    for node of nodes {
      if !node.isRemoved() {
        drawNode(pass, node)
      }
    }
  }

  frame(pass: RenderPass, deltaSeconds: double): void {
    update(deltaSeconds)
    draw(pass)
  }

  private runFixedTicks(snapshotLength: int, frameDelta: double): void {
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

  private currentTickAlpha(): double | null {
    tickRate := ticksPerSecond as double else { return null }
    return tickAccumulator / (1.0 / tickRate)
  }

  private drawNode(pass: RenderPass, node: SceneNode): void {
    case node.kind {
      SceneNodeKind.SimpleModel -> drawSimpleModel(pass, node.model!)
      SceneNodeKind.SimpleModelBatch -> drawSimpleModelBatch(pass, node.batch!)
    }
  }

  private compactRemovedNodes(): void {
    retained: SceneNode[] := []
    for node of nodes {
      if !node.isRemoved() {
        retained.push(node)
      }
    }
    nodes = retained
  }
}
