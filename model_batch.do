import { NativeSimpleModelBatch, drawNativeSimpleModelBatch } from "./native"
import { SimpleMaterial, SimpleMesh, SimpleMeshLighting } from "./mesh"
import { Point3, RenderPass, Texture } from "./render"
import { GameSurface } from "./surface"
import { Rotation, Transform, Vec3 } from "./transform"

export class SimpleModelInstanceConfig {
  transform: Transform = Transform {
    position: Point3(0.0, 0.0, 0.0),
    rotation: Rotation { qx: 0.0, qy: 0.0, qz: 0.0, qw: 1.0 },
    scale: Vec3 { x: 1.0, y: 1.0, z: 1.0 },
  }
  material: SimpleMaterial = SimpleMaterial {}
}

class SimpleModelInstanceState {
  slot: int
  live: bool = true
}

export class SimpleModelBatch {
  readonly surface: GameSurface
  readonly mesh: SimpleMesh
  texture: Texture | none = none
  readonly capacity: int

  private transforms: Transform[] = []
  private materials: SimpleMaterial[] = []
  private dirty: int[] = []
  private states: SimpleModelInstanceState[] = []
  private native: NativeSimpleModelBatch | none = none

  count(): int => transforms.length

  add(
    transform: Transform = Transform {
      position: Point3(0.0, 0.0, 0.0),
      rotation: Rotation { qx: 0.0, qy: 0.0, qz: 0.0, qw: 1.0 },
      scale: Vec3 { x: 1.0, y: 1.0, z: 1.0 },
    },
    material: SimpleMaterial = SimpleMaterial {},
  ): SimpleModelInstance {
    if count() >= capacity {
      panic("SimpleModelBatch capacity exceeded")
    }

    slot := count()
    state := SimpleModelInstanceState { slot: slot }
    transforms.push(transform)
    materials.push(material)
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

  private materialOf(state: SimpleModelInstanceState): SimpleMaterial {
    return materials[requireLive(state)]
  }

  private setTransformFor(state: SimpleModelInstanceState, transform: Transform): none {
    slot := requireLive(state)
    transforms[slot] = transform
    dirty[slot] = 1
  }

  private setMaterialFor(state: SimpleModelInstanceState, material: SimpleMaterial): none {
    slot := requireLive(state)
    materials[slot] = material
    dirty[slot] = 1
  }

  private remove(state: SimpleModelInstanceState): none {
    slot := requireLive(state)
    state.live = false

    last := count() - 1
    if slot != last {
      transforms[slot] = transforms[last]
      materials[slot] = materials[last]
      dirty[slot] = 1

      movedState := states[last]
      movedState.slot = slot
      states[slot] = movedState
    }

    transforms = transforms.slice(0, last)
    materials = materials.slice(0, last)
    dirty = dirty.slice(0, last)
    states = states.slice(0, last)
  }

  private syncNative(): NativeSimpleModelBatch {
    if native == none {
      native = try! NativeSimpleModelBatch.create(surface.metalDeviceHandle(), capacity)
    }

    target := native!
    target.setCount(count())
    for slot of 0..<count() {
      if dirty[slot] != 0 {
        transform := transforms[slot]
        matrix := transform.toMat4()
        normal := transform.toNormalMat3()
        material := materials[slot]
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
          normal.m00,
          normal.m01,
          normal.m02,
          normal.m10,
          normal.m11,
          normal.m12,
          normal.m20,
          normal.m21,
          normal.m22,
          material.tint.r,
          material.tint.g,
          material.tint.b,
          material.tint.a,
          material.whiteBlend,
          material.uvOffset.x,
          material.uvOffset.y,
          material.uvScale.x,
          material.uvScale.y,
          material.specular,
          material.shininess,
          material.fresnel,
          material.fresnelPower,
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
  material(): SimpleMaterial => batch.materialOf(state)

  setTransform(transform: Transform): SimpleModelInstance {
    batch.setTransformFor(state, transform)
    return this
  }

  setMaterial(material: SimpleMaterial): SimpleModelInstance {
    batch.setMaterialFor(state, material)
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

  remove(): none {
    batch.remove(state)
  }
}

export function drawSimpleModelBatch(
  pass: RenderPass,
  batch: SimpleModelBatch,
  lighting: SimpleMeshLighting = SimpleMeshLighting {},
): none {
  if batch.count() == 0 {
    return
  }

  nativeBatch := batch.syncNative()
  mvp := pass.camera().matrix(pass.surface())
  eye := pass.camera().transform.position
  drawNativeSimpleModelBatch(
    batch.mesh.nativeSimpleMesh(),
    nativeBatch,
    if batch.texture != none then batch.texture!.metalTextureHandle() else 0L,
    batch.texture != none,
    pass.metalRenderCommandEncoderHandle(),
    pass.metalDeviceHandle(),
    pass.nativeBlendModeCode(),
    pass.hasColorAttachment(),
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
    eye.x,
    eye.y,
    eye.z,
  )
}
