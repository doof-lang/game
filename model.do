import { SimpleMesh, drawSimpleMesh, drawTexturedSimpleMesh } from "./mesh"
import { Point3, RenderPass, Texture } from "./render"
import { Rotation, Transform, Vec3 } from "./transform"

export class SimpleModel {
  readonly mesh: SimpleMesh
  texture: Texture | null = null
  transform: Transform

  static constructor(
    mesh: SimpleMesh,
    texture: Texture | null = null,
  ): SimpleModel {
    return SimpleModel(mesh, texture, Transform.identity())
  }

  setTransform(transform: Transform): SimpleModel {
    this.transform = transform
    return this
  }

  setTexture(texture: Texture | null): SimpleModel {
    this.texture = texture
    return this
  }

  clearTexture(): SimpleModel {
    texture = null
    return this
  }

  setPosition(position: Point3): SimpleModel {
    transform = transform.withPosition(position)
    return this
  }

  setRotation(rotation: Rotation): SimpleModel {
    transform = transform.withRotation(rotation)
    return this
  }

  setScale(scale: Vec3): SimpleModel {
    transform = transform.withScale(scale)
    return this
  }

  moveBy(delta: Vec3): SimpleModel {
    return moveWorldBy(delta)
  }

  moveWorldBy(delta: Vec3): SimpleModel {
    transform = transform.movedWorldBy(delta)
    return this
  }

  moveLocalBy(delta: Vec3): SimpleModel {
    transform = transform.movedLocalBy(delta)
    return this
  }

  rotateLocalBy(delta: Rotation): SimpleModel {
    transform = transform.rotatedLocalBy(delta)
    return this
  }

  rotateLocalX(degrees: double): SimpleModel {
    transform = transform.rotatedLocalX(degrees)
    return this
  }

  rotateLocalY(degrees: double): SimpleModel {
    transform = transform.rotatedLocalY(degrees)
    return this
  }

  rotateLocalZ(degrees: double): SimpleModel {
    transform = transform.rotatedLocalZ(degrees)
    return this
  }

  rotateWorldX(degrees: double): SimpleModel {
    transform = transform.rotatedWorldX(degrees)
    return this
  }

  rotateWorldY(degrees: double): SimpleModel {
    transform = transform.rotatedWorldY(degrees)
    return this
  }

  rotateWorldZ(degrees: double): SimpleModel {
    transform = transform.rotatedWorldZ(degrees)
    return this
  }

  scaleBy(factor: double): SimpleModel {
    transform = transform.scaledBy(factor)
    return this
  }

  scaleByVec(factor: Vec3): SimpleModel {
    transform = transform.scaledByVec(factor)
    return this
  }
}

export function drawSimpleModel(pass: RenderPass, model: SimpleModel): void {
  if model.texture != null {
    drawTexturedSimpleMesh(pass, model.mesh, model.texture!, model.transform.toMat4())
    return
  }

  drawSimpleMesh(pass, model.mesh, model.transform.toMat4())
}
