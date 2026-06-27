import { NativeSimpleModelBatch, drawNativeSimpleModelBatch } from "./native"
import { SimpleMesh, SimpleMeshLighting } from "./mesh"
import { Color, Point3, RenderPass, Texture } from "./render"
import { GameSurface } from "./surface"
import { Rotation, Transform, Vec3 } from "./transform"

export class Vec2 {
  readonly x: double
  readonly y: double

  static readonly zero = Vec2 { x: 0.0, y: 0.0 }
  static readonly one = Vec2 { x: 1.0, y: 1.0 }

  static xy(x: double, y: double): Vec2 {
    return Vec2 { x: x, y: y }
  }
}

export class SimpleModelInstanceConfig {
  transform: Transform = Transform {
    position: Point3(0.0, 0.0, 0.0),
    rotation: Rotation { qx: 0.0, qy: 0.0, qz: 0.0, qw: 1.0 },
    scale: Vec3 { x: 1.0, y: 1.0, z: 1.0 },
  }
  tint: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }
  whiteBlend: double = 0.0
  uvOffset: Vec2 = Vec2 { x: 0.0, y: 0.0 }
  uvScale: Vec2 = Vec2 { x: 1.0, y: 1.0 }
}

class SimpleModelInstanceState {
  slot: int
  live: bool = true
}

export class SimpleModelBatch {
  readonly surface: GameSurface
  readonly mesh: SimpleMesh
  texture: Texture | null = null
  readonly capacity: int

  private transforms: Transform[] = []
  private tints: Color[] = []
  private whiteBlends: double[] = []
  private uvOffsets: Vec2[] = []
  private uvScales: Vec2[] = []
  private dirty: int[] = []
  private states: SimpleModelInstanceState[] = []
  private native: NativeSimpleModelBatch | null = null

  count(): int => transforms.length

  add(
    transform: Transform = Transform {
      position: Point3(0.0, 0.0, 0.0),
      rotation: Rotation { qx: 0.0, qy: 0.0, qz: 0.0, qw: 1.0 },
      scale: Vec3 { x: 1.0, y: 1.0, z: 1.0 },
    },
    tint: Color = Color { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
    whiteBlend: double = 0.0,
    uvOffset: Vec2 = Vec2 { x: 0.0, y: 0.0 },
    uvScale: Vec2 = Vec2 { x: 1.0, y: 1.0 },
  ): SimpleModelInstance {
    if count() >= capacity {
      panic("SimpleModelBatch capacity exceeded")
    }

    slot := count()
    state := SimpleModelInstanceState { slot: slot }
    transforms.push(transform)
    tints.push(tint)
    whiteBlends.push(whiteBlend)
    uvOffsets.push(uvOffset)
    uvScales.push(uvScale)
    dirty.push(1)
    states.push(state)

    return SimpleModelInstance { batch: this, state: state }
  }

  private requireLive(state: SimpleModelInstanceState): int {
    if !state.live {
      panic("SimpleModelInstance is no longer live")
    }
    return state.slot
  }

  private transformOf(state: SimpleModelInstanceState): Transform {
    return transforms[requireLive(state)]
  }

  private tintOf(state: SimpleModelInstanceState): Color {
    return tints[requireLive(state)]
  }

  private uvOffsetOf(state: SimpleModelInstanceState): Vec2 {
    return uvOffsets[requireLive(state)]
  }

  private whiteBlendOf(state: SimpleModelInstanceState): double {
    return whiteBlends[requireLive(state)]
  }

  private uvScaleOf(state: SimpleModelInstanceState): Vec2 {
    return uvScales[requireLive(state)]
  }

  private setTransformFor(state: SimpleModelInstanceState, transform: Transform): void {
    slot := requireLive(state)
    transforms[slot] = transform
    dirty[slot] = 1
  }

  private setTintFor(state: SimpleModelInstanceState, tint: Color): void {
    slot := requireLive(state)
    tints[slot] = tint
    dirty[slot] = 1
  }

  private setWhiteBlendFor(state: SimpleModelInstanceState, whiteBlend: double): void {
    slot := requireLive(state)
    whiteBlends[slot] = whiteBlend
    dirty[slot] = 1
  }

  private setUvOffsetFor(state: SimpleModelInstanceState, uvOffset: Vec2): void {
    slot := requireLive(state)
    uvOffsets[slot] = uvOffset
    dirty[slot] = 1
  }

  private setUvScaleFor(state: SimpleModelInstanceState, uvScale: Vec2): void {
    slot := requireLive(state)
    uvScales[slot] = uvScale
    dirty[slot] = 1
  }

  private remove(state: SimpleModelInstanceState): void {
    slot := requireLive(state)
    state.live = false

    last := count() - 1
    if slot != last {
      transforms[slot] = transforms[last]
      tints[slot] = tints[last]
      whiteBlends[slot] = whiteBlends[last]
      uvOffsets[slot] = uvOffsets[last]
      uvScales[slot] = uvScales[last]
      dirty[slot] = 1

      movedState := states[last]
      movedState.slot = slot
      states[slot] = movedState
    }

    transforms = transforms.slice(0, last)
    tints = tints.slice(0, last)
    whiteBlends = whiteBlends.slice(0, last)
    uvOffsets = uvOffsets.slice(0, last)
    uvScales = uvScales.slice(0, last)
    dirty = dirty.slice(0, last)
    states = states.slice(0, last)
  }

  private syncNative(): NativeSimpleModelBatch {
    if native == null {
      native = try! NativeSimpleModelBatch.create(surface.metalDeviceHandle(), capacity)
    }

    target := native!
    target.setCount(count())
    for slot of 0..<count() {
      if dirty[slot] != 0 {
        matrix := transforms[slot].toMat4()
        tint := tints[slot]
        whiteBlend := whiteBlends[slot]
        uvOffset := uvOffsets[slot]
        uvScale := uvScales[slot]
        target.setInstance(
          slot,
          matrix.m00,
          matrix.m01,
          matrix.m02,
          matrix.m03,
          matrix.m10,
          matrix.m11,
          matrix.m12,
          matrix.m13,
          matrix.m20,
          matrix.m21,
          matrix.m22,
          matrix.m23,
          matrix.m30,
          matrix.m31,
          matrix.m32,
          matrix.m33,
          tint.r,
          tint.g,
          tint.b,
          tint.a,
          whiteBlend,
          uvOffset.x,
          uvOffset.y,
          uvScale.x,
          uvScale.y,
        )
        dirty[slot] = 0
      }
    }
    return target
  }
}

export class SimpleModelInstance {
  private batch: SimpleModelBatch
  private state: SimpleModelInstanceState

  isLive(): bool => state.live

  transform(): Transform => batch.transformOf(state)
  tint(): Color => batch.tintOf(state)
  whiteBlend(): double => batch.whiteBlendOf(state)
  uvOffset(): Vec2 => batch.uvOffsetOf(state)
  uvScale(): Vec2 => batch.uvScaleOf(state)

  setTransform(transform: Transform): SimpleModelInstance {
    batch.setTransformFor(state, transform)
    return this
  }

  setTint(tint: Color): SimpleModelInstance {
    batch.setTintFor(state, tint)
    return this
  }

  setWhiteBlend(whiteBlend: double): SimpleModelInstance {
    batch.setWhiteBlendFor(state, whiteBlend)
    return this
  }

  setUvOffset(uvOffset: Vec2): SimpleModelInstance {
    batch.setUvOffsetFor(state, uvOffset)
    return this
  }

  setUvScale(uvScale: Vec2): SimpleModelInstance {
    batch.setUvScaleFor(state, uvScale)
    return this
  }

  setPosition(position: Point3): SimpleModelInstance {
    return setTransform(transform().withPosition(position))
  }

  setRotation(rotation: Rotation): SimpleModelInstance {
    return setTransform(transform().withRotation(rotation))
  }

  setScale(scale: Vec3): SimpleModelInstance {
    return setTransform(transform().withScale(scale))
  }

  moveBy(delta: Vec3): SimpleModelInstance {
    return moveWorldBy(delta)
  }

  moveWorldBy(delta: Vec3): SimpleModelInstance {
    return setTransform(transform().movedWorldBy(delta))
  }

  moveLocalBy(delta: Vec3): SimpleModelInstance {
    return setTransform(transform().movedLocalBy(delta))
  }

  rotateLocalBy(delta: Rotation): SimpleModelInstance {
    return setTransform(transform().rotatedLocalBy(delta))
  }

  rotateLocalX(degrees: double): SimpleModelInstance {
    return setTransform(transform().rotatedLocalX(degrees))
  }

  rotateLocalY(degrees: double): SimpleModelInstance {
    return setTransform(transform().rotatedLocalY(degrees))
  }

  rotateLocalZ(degrees: double): SimpleModelInstance {
    return setTransform(transform().rotatedLocalZ(degrees))
  }

  rotateWorldX(degrees: double): SimpleModelInstance {
    return setTransform(transform().rotatedWorldX(degrees))
  }

  rotateWorldY(degrees: double): SimpleModelInstance {
    return setTransform(transform().rotatedWorldY(degrees))
  }

  rotateWorldZ(degrees: double): SimpleModelInstance {
    return setTransform(transform().rotatedWorldZ(degrees))
  }

  scaleBy(factor: double): SimpleModelInstance {
    return setTransform(transform().scaledBy(factor))
  }

  scaleByVec(factor: Vec3): SimpleModelInstance {
    return setTransform(transform().scaledByVec(factor))
  }

  remove(): void {
    batch.remove(state)
  }
}

export function drawSimpleModelBatch(
  pass: RenderPass,
  batch: SimpleModelBatch,
  lighting: SimpleMeshLighting = SimpleMeshLighting {},
): void {
  if batch.count() == 0 {
    return
  }

  nativeBatch := batch.syncNative()
  mvp := pass.camera().matrix(pass.surface())
  drawNativeSimpleModelBatch(
    batch.mesh.nativeSimpleMesh(),
    nativeBatch,
    if batch.texture != null then batch.texture!.metalTextureHandle() else 0L,
    batch.texture != null,
    pass.metalRenderCommandEncoderHandle(),
    pass.metalDeviceHandle(),
    pass.nativeBlendModeCode(),
    pass.hasDepthAttachment(),
    mvp.m00,
    mvp.m01,
    mvp.m02,
    mvp.m03,
    mvp.m10,
    mvp.m11,
    mvp.m12,
    mvp.m13,
    mvp.m20,
    mvp.m21,
    mvp.m22,
    mvp.m23,
    mvp.m30,
    mvp.m31,
    mvp.m32,
    mvp.m33,
    lighting.ambient,
    lighting.directional,
    lighting.direction.x,
    lighting.direction.y,
    lighting.direction.z,
  )
}
