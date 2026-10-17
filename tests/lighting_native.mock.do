// Records the lighting and material values std/game's mesh and model batch
// modules hand to the native layer, so argument order regressions show up.
export class LightingCapture {
  let meshCalls: int = 0
  let texturedMeshCalls: int = 0
  let batchCalls: int = 0
  let instanceCalls: int = 0
  let meshAmbientLight: double = -1.0
  let meshDirectionalLight: double = -1.0
  let meshEyeX: double = -1.0
  let meshEyeY: double = -1.0
  let meshEyeZ: double = -1.0
  let meshLightRed: double = -1.0
  let meshLightGreen: double = -1.0
  let meshLightBlue: double = -1.0
  let meshAmbientRed: double = -1.0
  let meshAmbientGreen: double = -1.0
  let meshAmbientBlue: double = -1.0
  let meshRed: double = -1.0
  let meshAlpha: double = -1.0
  let meshWhiteBlend: double = -1.0
  let meshUvOffsetX: double = -1.0
  let meshUvScaleY: double = -1.0
  let meshSpecular: double = -1.0
  let meshShininess: double = -1.0
  let meshFresnel: double = -1.0
  let meshFresnelPower: double = -1.0
  let meshAlphaCutoff: double = -1.0
  let batchAmbientLight: double = -1.0
  let batchDirectionalLight: double = -1.0
  let batchEyeZ: double = -1.0
  let batchLightRed: double = -1.0
  let batchLightGreen: double = -1.0
  let batchLightBlue: double = -1.0
  let batchAmbientRed: double = -1.0
  let batchAmbientGreen: double = -1.0
  let batchAmbientBlue: double = -1.0
  let instanceRed: double = -1.0
  let instanceAlpha: double = -1.0
  let instanceWhiteBlend: double = -1.0
  let instanceUvOffsetX: double = -1.0
  let instanceUvScaleY: double = -1.0
  let instanceSpecular: double = -1.0
  let instanceShininess: double = -1.0
  let instanceFresnel: double = -1.0
  let instanceFresnelPower: double = -1.0
  let instanceAlphaCutoff: double = -1.0
}

capture := LightingCapture {}
export { capture }

export class NativeSimpleMesh {
  vertexCount(): int => 3
  indexCount(): int => 3
}

export class NativeSimpleMeshBuilder {
  static create(): NativeSimpleMeshBuilder => NativeSimpleMeshBuilder {}

  addVertex(x: double, y: double, z: double, red: double, green: double, blue: double, alpha: double, u: double, v: double, nx: double, ny: double, nz: double): int => 0
  addTriangle(a: int, b: int, c: int): NativeSimpleMeshBuilder => this
  build(metalDeviceHandle: long): Result<NativeSimpleMesh, string> => Success(NativeSimpleMesh {})
}

export class NativeSimpleModelBatch {
  private batchCapacity: int
  private let batchCount: int = 0

  static create(metalDeviceHandle: long, capacity: int): Result<NativeSimpleModelBatch, string> {
    return Success(NativeSimpleModelBatch { batchCapacity: capacity })
  }

  capacity(): int => batchCapacity
  count(): int => batchCount
  setCount(count: int): none {
    batchCount = count
  }

  setInstance(
    slot: int,
    m00: double,
    m01: double,
    m02: double,
    m03: double,
    m10: double,
    m11: double,
    m12: double,
    m13: double,
    m20: double,
    m21: double,
    m22: double,
    m23: double,
    m30: double,
    m31: double,
    m32: double,
    m33: double,
    n00: double,
    n01: double,
    n02: double,
    n10: double,
    n11: double,
    n12: double,
    n20: double,
    n21: double,
    n22: double,
    red: double,
    green: double,
    blue: double,
    alpha: double,
    whiteBlend: double,
    uvOffsetX: double,
    uvOffsetY: double,
    uvScaleX: double,
    uvScaleY: double,
    specular: double,
    shininess: double,
    fresnel: double,
    fresnelPower: double,
    alphaCutoff: double,
  ): none {
    capture.instanceCalls += 1
    capture.instanceRed = red
    capture.instanceAlpha = alpha
    capture.instanceWhiteBlend = whiteBlend
    capture.instanceUvOffsetX = uvOffsetX
    capture.instanceUvScaleY = uvScaleY
    capture.instanceSpecular = specular
    capture.instanceShininess = shininess
    capture.instanceFresnel = fresnel
    capture.instanceFresnelPower = fresnelPower
    capture.instanceAlphaCutoff = alphaCutoff
  }
}

export function drawNativeSimpleMesh(
  mesh: NativeSimpleMesh,
  metalRenderCommandEncoderHandle: long,
  metalDeviceHandle: long,
  blendMode: int,
  hasColorAttachment: bool,
  hasDepthAttachment: bool,
  m00: double,
  m01: double,
  m02: double,
  m03: double,
  m10: double,
  m11: double,
  m12: double,
  m13: double,
  m20: double,
  m21: double,
  m22: double,
  m23: double,
  m30: double,
  m31: double,
  m32: double,
  m33: double,
  modelM00: double,
  modelM01: double,
  modelM02: double,
  modelM03: double,
  modelM10: double,
  modelM11: double,
  modelM12: double,
  modelM13: double,
  modelM20: double,
  modelM21: double,
  modelM22: double,
  modelM23: double,
  modelM30: double,
  modelM31: double,
  modelM32: double,
  modelM33: double,
  n00: double,
  n01: double,
  n02: double,
  n10: double,
  n11: double,
  n12: double,
  n20: double,
  n21: double,
  n22: double,
  ambientLight: double,
  directionalLight: double,
  lightDirectionX: double,
  lightDirectionY: double,
  lightDirectionZ: double,
  eyeX: double,
  eyeY: double,
  eyeZ: double,
  lightRed: double,
  lightGreen: double,
  lightBlue: double,
  ambientRed: double,
  ambientGreen: double,
  ambientBlue: double,
  red: double,
  green: double,
  blue: double,
  alpha: double,
  whiteBlend: double,
  uvOffsetX: double,
  uvOffsetY: double,
  uvScaleX: double,
  uvScaleY: double,
  specular: double,
  shininess: double,
  fresnel: double,
  fresnelPower: double,
  alphaCutoff: double,
): none {
  capture.meshCalls += 1
  capture.meshAmbientLight = ambientLight
  capture.meshDirectionalLight = directionalLight
  capture.meshEyeX = eyeX
  capture.meshEyeY = eyeY
  capture.meshEyeZ = eyeZ
  capture.meshLightRed = lightRed
  capture.meshLightGreen = lightGreen
  capture.meshLightBlue = lightBlue
  capture.meshAmbientRed = ambientRed
  capture.meshAmbientGreen = ambientGreen
  capture.meshAmbientBlue = ambientBlue
  capture.meshRed = red
  capture.meshAlpha = alpha
  capture.meshWhiteBlend = whiteBlend
  capture.meshUvOffsetX = uvOffsetX
  capture.meshUvScaleY = uvScaleY
  capture.meshSpecular = specular
  capture.meshShininess = shininess
  capture.meshFresnel = fresnel
  capture.meshFresnelPower = fresnelPower
  capture.meshAlphaCutoff = alphaCutoff
}

export function drawNativeTexturedSimpleMesh(
  mesh: NativeSimpleMesh,
  metalTextureHandle: long,
  metalRenderCommandEncoderHandle: long,
  metalDeviceHandle: long,
  blendMode: int,
  hasColorAttachment: bool,
  hasDepthAttachment: bool,
  m00: double,
  m01: double,
  m02: double,
  m03: double,
  m10: double,
  m11: double,
  m12: double,
  m13: double,
  m20: double,
  m21: double,
  m22: double,
  m23: double,
  m30: double,
  m31: double,
  m32: double,
  m33: double,
  modelM00: double,
  modelM01: double,
  modelM02: double,
  modelM03: double,
  modelM10: double,
  modelM11: double,
  modelM12: double,
  modelM13: double,
  modelM20: double,
  modelM21: double,
  modelM22: double,
  modelM23: double,
  modelM30: double,
  modelM31: double,
  modelM32: double,
  modelM33: double,
  n00: double,
  n01: double,
  n02: double,
  n10: double,
  n11: double,
  n12: double,
  n20: double,
  n21: double,
  n22: double,
  ambientLight: double,
  directionalLight: double,
  lightDirectionX: double,
  lightDirectionY: double,
  lightDirectionZ: double,
  eyeX: double,
  eyeY: double,
  eyeZ: double,
  lightRed: double,
  lightGreen: double,
  lightBlue: double,
  ambientRed: double,
  ambientGreen: double,
  ambientBlue: double,
  red: double,
  green: double,
  blue: double,
  alpha: double,
  whiteBlend: double,
  uvOffsetX: double,
  uvOffsetY: double,
  uvScaleX: double,
  uvScaleY: double,
  specular: double,
  shininess: double,
  fresnel: double,
  fresnelPower: double,
  alphaCutoff: double,
): none {
  capture.texturedMeshCalls += 1
  capture.meshAmbientLight = ambientLight
  capture.meshDirectionalLight = directionalLight
  capture.meshEyeX = eyeX
  capture.meshEyeY = eyeY
  capture.meshEyeZ = eyeZ
  capture.meshLightRed = lightRed
  capture.meshLightGreen = lightGreen
  capture.meshLightBlue = lightBlue
  capture.meshAmbientRed = ambientRed
  capture.meshAmbientGreen = ambientGreen
  capture.meshAmbientBlue = ambientBlue
  capture.meshRed = red
  capture.meshAlpha = alpha
  capture.meshWhiteBlend = whiteBlend
  capture.meshUvOffsetX = uvOffsetX
  capture.meshUvScaleY = uvScaleY
  capture.meshSpecular = specular
  capture.meshShininess = shininess
  capture.meshFresnel = fresnel
  capture.meshFresnelPower = fresnelPower
  capture.meshAlphaCutoff = alphaCutoff
}

export function drawNativeSimpleModelBatch(
  mesh: NativeSimpleMesh,
  batch: NativeSimpleModelBatch,
  metalTextureHandle: long,
  textured: bool,
  metalRenderCommandEncoderHandle: long,
  metalDeviceHandle: long,
  blendMode: int,
  hasColorAttachment: bool,
  hasDepthAttachment: bool,
  m00: double,
  m01: double,
  m02: double,
  m03: double,
  m10: double,
  m11: double,
  m12: double,
  m13: double,
  m20: double,
  m21: double,
  m22: double,
  m23: double,
  m30: double,
  m31: double,
  m32: double,
  m33: double,
  ambientLight: double,
  directionalLight: double,
  lightDirectionX: double,
  lightDirectionY: double,
  lightDirectionZ: double,
  eyeX: double,
  eyeY: double,
  eyeZ: double,
  lightRed: double,
  lightGreen: double,
  lightBlue: double,
  ambientRed: double,
  ambientGreen: double,
  ambientBlue: double,
): none {
  capture.batchCalls += 1
  capture.batchAmbientLight = ambientLight
  capture.batchDirectionalLight = directionalLight
  capture.batchEyeZ = eyeZ
  capture.batchLightRed = lightRed
  capture.batchLightGreen = lightGreen
  capture.batchLightBlue = lightBlue
  capture.batchAmbientRed = ambientRed
  capture.batchAmbientGreen = ambientGreen
  capture.batchAmbientBlue = ambientBlue
}
