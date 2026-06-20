import {
  NativeRenderFrame,
  NativeRenderPass,
  NativeTexture,
} from "./native"
import { GameSurface } from "./surface"
import { Rotation, Transform, Vec3 } from "./transform"
import { Image, PixelAlphaMode, PixelBytes } from "std/image"
import { cos, sin, tan } from "std/math"

export enum CameraKind {
  Screen,
  Identity,
  Orthographic,
  Perspective,
}

export enum ClearKind {
  None,
  Color,
  Depth,
  ColorDepth,
}

export enum DepthMode {
  Disabled,
  ReadOnly,
  ReadWrite,
}

export enum BlendMode {
  Opaque,
  Alpha,
}

export enum WindingMode {
  Clockwise,
  CounterClockwise,
}

export enum CullMode {
  None,
  Front,
  Back,
}

const CLEAR_NONE = 0
const CLEAR_COLOR = 1
const CLEAR_DEPTH = 2
const CLEAR_COLOR_DEPTH = 3

const DEPTH_DISABLED = 0
const DEPTH_READ_ONLY = 1
const DEPTH_READ_WRITE = 2

const BLEND_OPAQUE = 0
const BLEND_ALPHA = 1

const WINDING_CLOCKWISE = 0
const WINDING_COUNTER_CLOCKWISE = 1

const CULL_NONE = 0
const CULL_FRONT = 1
const CULL_BACK = 2

function clearKindCode(kind: ClearKind): int {
  return case kind {
    ClearKind.None -> CLEAR_NONE,
    ClearKind.Color -> CLEAR_COLOR,
    ClearKind.Depth -> CLEAR_DEPTH,
    ClearKind.ColorDepth -> CLEAR_COLOR_DEPTH,
  }
}

function depthModeCode(mode: DepthMode): int {
  return case mode {
    DepthMode.Disabled -> DEPTH_DISABLED,
    DepthMode.ReadOnly -> DEPTH_READ_ONLY,
    DepthMode.ReadWrite -> DEPTH_READ_WRITE,
  }
}

function blendModeCode(mode: BlendMode): int {
  return case mode {
    BlendMode.Opaque -> BLEND_OPAQUE,
    BlendMode.Alpha -> BLEND_ALPHA,
  }
}

function windingModeCode(mode: WindingMode): int {
  return case mode {
    WindingMode.Clockwise -> WINDING_CLOCKWISE,
    WindingMode.CounterClockwise -> WINDING_COUNTER_CLOCKWISE,
  }
}

function cullModeCode(mode: CullMode): int {
  return case mode {
    CullMode.None -> CULL_NONE,
    CullMode.Front -> CULL_FRONT,
    CullMode.Back -> CULL_BACK,
  }
}

export class Color {
  readonly r: double
  readonly g: double
  readonly b: double
  readonly a: double = 1.0

  static readonly black = Color(0.0, 0.0, 0.0)
  static readonly white = Color(1.0, 1.0, 1.0)
  static readonly red = Color(1.0, 0.0, 0.0)
  static readonly blue = Color(0.0, 0.0, 1.0)
  static readonly green = Color(0.0, 1.0, 0.0)
  static readonly transparent = Color(0.0, 0.0, 0.0, 0.0)
}

export class Point {
  readonly x: double
  readonly y: double
}

export class Point3 {
  readonly x: double
  readonly y: double
  readonly z: double
}

export class ClipPoint {
  readonly x: double
  readonly y: double
  readonly z: double
  readonly w: double
}

export class Mat4 {
  readonly m00: double
  readonly m01: double
  readonly m02: double
  readonly m03: double
  readonly m10: double
  readonly m11: double
  readonly m12: double
  readonly m13: double
  readonly m20: double
  readonly m21: double
  readonly m22: double
  readonly m23: double
  readonly m30: double
  readonly m31: double
  readonly m32: double
  readonly m33: double

  static readonly identity = Mat4 {
      m00: 1.0, m01: 0.0, m02: 0.0, m03: 0.0,
      m10: 0.0, m11: 1.0, m12: 0.0, m13: 0.0,
      m20: 0.0, m21: 0.0, m22: 1.0, m23: 0.0,
      m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
  }

  static translation(x: double, y: double, z: double): Mat4 {
    return Mat4 {
      m00: 1.0, m01: 0.0, m02: 0.0, m03: x,
      m10: 0.0, m11: 1.0, m12: 0.0, m13: y,
      m20: 0.0, m21: 0.0, m22: 1.0, m23: z,
      m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
    }
  }

  static scale(x: double, y: double, z: double): Mat4 {
    return Mat4 {
      m00: x, m01: 0.0, m02: 0.0, m03: 0.0,
      m10: 0.0, m11: y, m12: 0.0, m13: 0.0,
      m20: 0.0, m21: 0.0, m22: z, m23: 0.0,
      m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
    }
  }

  static rotationX(radians: double): Mat4 {
    c := cos(radians)
    s := sin(radians)
    return Mat4 {
      m00: 1.0, m01: 0.0, m02: 0.0, m03: 0.0,
      m10: 0.0, m11: c, m12: -s, m13: 0.0,
      m20: 0.0, m21: s, m22: c, m23: 0.0,
      m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
    }
  }

  static rotationY(radians: double): Mat4 {
    c := cos(radians)
    s := sin(radians)
    return Mat4 {
      m00: c, m01: 0.0, m02: s, m03: 0.0,
      m10: 0.0, m11: 1.0, m12: 0.0, m13: 0.0,
      m20: -s, m21: 0.0, m22: c, m23: 0.0,
      m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
    }
  }

  static rotationZ(radians: double): Mat4 {
    c := cos(radians)
    s := sin(radians)
    return Mat4 {
      m00: c, m01: -s, m02: 0.0, m03: 0.0,
      m10: s, m11: c, m12: 0.0, m13: 0.0,
      m20: 0.0, m21: 0.0, m22: 1.0, m23: 0.0,
      m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
    }
  }

  static orthographic(
    left: double,
    right: double,
    bottom: double,
    top: double,
    near: double = -1.0,
    far: double = 1.0,
  ): Mat4 {
    return Mat4 {
      m00: 2.0 / (right - left),
      m01: 0.0,
      m02: 0.0,
      m03: -(right + left) / (right - left),
      m10: 0.0,
      m11: 2.0 / (top - bottom),
      m12: 0.0,
      m13: -(top + bottom) / (top - bottom),
      m20: 0.0,
      m21: 0.0,
      m22: 1.0 / (near - far),
      m23: near / (near - far),
      m30: 0.0,
      m31: 0.0,
      m32: 0.0,
      m33: 1.0,
    }
  }

  static perspective(fovYRadians: double, aspect: double, near: double, far: double): Mat4 {
    f := 1.0 / tan(fovYRadians * 0.5)
    return Mat4 {
      m00: f / aspect,
      m01: 0.0,
      m02: 0.0,
      m03: 0.0,
      m10: 0.0,
      m11: f,
      m12: 0.0,
      m13: 0.0,
      m20: 0.0,
      m21: 0.0,
      m22: far / (near - far),
      m23: (far * near) / (near - far),
      m30: 0.0,
      m31: 0.0,
      m32: -1.0,
      m33: 0.0,
    }
  }

  multiply(other: Mat4): Mat4 {
    return Mat4 {
      m00: m00 * other.m00 + m01 * other.m10 + m02 * other.m20 + m03 * other.m30,
      m01: m00 * other.m01 + m01 * other.m11 + m02 * other.m21 + m03 * other.m31,
      m02: m00 * other.m02 + m01 * other.m12 + m02 * other.m22 + m03 * other.m32,
      m03: m00 * other.m03 + m01 * other.m13 + m02 * other.m23 + m03 * other.m33,
      m10: m10 * other.m00 + m11 * other.m10 + m12 * other.m20 + m13 * other.m30,
      m11: m10 * other.m01 + m11 * other.m11 + m12 * other.m21 + m13 * other.m31,
      m12: m10 * other.m02 + m11 * other.m12 + m12 * other.m22 + m13 * other.m32,
      m13: m10 * other.m03 + m11 * other.m13 + m12 * other.m23 + m13 * other.m33,
      m20: m20 * other.m00 + m21 * other.m10 + m22 * other.m20 + m23 * other.m30,
      m21: m20 * other.m01 + m21 * other.m11 + m22 * other.m21 + m23 * other.m31,
      m22: m20 * other.m02 + m21 * other.m12 + m22 * other.m22 + m23 * other.m32,
      m23: m20 * other.m03 + m21 * other.m13 + m22 * other.m23 + m23 * other.m33,
      m30: m30 * other.m00 + m31 * other.m10 + m32 * other.m20 + m33 * other.m30,
      m31: m30 * other.m01 + m31 * other.m11 + m32 * other.m21 + m33 * other.m31,
      m32: m30 * other.m02 + m31 * other.m12 + m32 * other.m22 + m33 * other.m32,
      m33: m30 * other.m03 + m31 * other.m13 + m32 * other.m23 + m33 * other.m33,
    }
  }

  transformPoint(point: Point3): ClipPoint {
    return ClipPoint {
      x: m00 * point.x + m01 * point.y + m02 * point.z + m03,
      y: m10 * point.x + m11 * point.y + m12 * point.z + m13,
      z: m20 * point.x + m21 * point.y + m22 * point.z + m23,
      w: m30 * point.x + m31 * point.y + m32 * point.z + m33,
    }
  }
}

export class Rect {
  readonly x: double
  readonly y: double
  readonly width: double
  readonly height: double
}

export class Texture {
  private readonly native: NativeTexture

  pixelWidth(): int => native.pixelWidth()
  pixelHeight(): int => native.pixelHeight()
  metalTextureHandle(): long => native.metalTextureHandle()
}

export class Atlas {
  readonly texture: Texture
  readonly columns: int
  readonly rows: int

  cellRect(column: int, row: int): Rect {
    cellWidth := double(texture.pixelWidth()) / double(columns)
    cellHeight := double(texture.pixelHeight()) / double(rows)
    return Rect(cellWidth * double(column), cellHeight * double(row), cellWidth, cellHeight)
  }
}

export class Camera {
  readonly kind: CameraKind
  readonly viewProjection: Mat4
  transform: Transform = Transform.identity()

  static screen(): Camera {
    return Camera { kind: CameraKind.Screen, viewProjection: Mat4.identity }
  }

  static identity(): Camera {
    return Camera { kind: CameraKind.Identity, viewProjection: Mat4.identity }
  }

  static orthographic(
    left: double,
    right: double,
    bottom: double,
    top: double,
    near: double = -1.0,
    far: double = 1.0,
  ): Camera {
    return Camera {
      kind: CameraKind.Orthographic,
      viewProjection: Mat4.orthographic(left, right, bottom, top, near, far),
    }
  }

  static perspective(fovYRadians: double, aspect: double, near: double, far: double): Camera {
    return Camera {
      kind: CameraKind.Perspective,
      viewProjection: Mat4.perspective(fovYRadians, aspect, near, far),
    }
  }

  withView(view: Mat4): Camera {
    return Camera {
      kind: kind,
      viewProjection: viewProjection.multiply(view),
      transform: transform,
    }
  }

  withTransform(transform: Transform): Camera {
    this.transform = transform
    return this
  }

  withPosition(position: Point3): Camera {
    transform = transform.withPosition(position)
    return this
  }

  withRotation(rotation: Rotation): Camera {
    transform = transform.withRotation(rotation)
    return this
  }

  withScale(scale: Vec3): Camera {
    transform = transform.withScale(scale)
  }

  moveBy(delta: Vec3): Camera {
    return moveWorldBy(delta)
  }

  moveWorldBy(delta: Vec3): Camera {
    transform = transform.movedWorldBy(delta)
    return this
  }

  moveLocalBy(delta: Vec3): Camera {
    return withTransform(transform.movedLocalBy(delta))
  }

  rotateLocalBy(delta: Rotation): Camera {
    return withTransform(transform.rotatedLocalBy(delta))
  }

  rotateLocalX(degrees: double): Camera {
    transform = transform.rotatedLocalX(degrees)
    return this
  }

  rotateLocalY(degrees: double): Camera {
    transform = transform.rotatedLocalY(degrees)
    return this
  }

  rotateLocalZ(degrees: double): Camera {
    transform = transform.rotatedLocalZ(degrees)
    return this
  }

  rotateWorldX(degrees: double): Camera {
    transform = transform.rotatedWorldX(degrees)
    return this
  }

  rotateWorldY(degrees: double): Camera {
    transform = transform.rotatedWorldY(degrees)
    return this
  }

  rotateWorldZ(degrees: double): Camera {
    transform = transform.rotatedWorldZ(degrees)
    return this
  }

  scaleBy(factor: double): Camera {
    transform = transform.scaledBy(factor)
    return this
  }

  scaleByVec(factor: Vec3): Camera {
    transform = transform.scaledByVec(factor)
    return this
  }

  matrix(surface: GameSurface): Mat4 {
    cameraView := transform.toInverseMat4()
    if kind == CameraKind.Screen {
      width := surface.width()
      height := surface.height()
      projection := Mat4 {
        m00: 2.0 / width, m01: 0.0, m02: 0.0, m03: -1.0,
        m10: 0.0, m11: -2.0 / height, m12: 0.0, m13: 1.0,
        m20: 0.0, m21: 0.0, m22: 1.0, m23: 0.0,
        m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
      }
      return projection.multiply(cameraView)
    }
    return viewProjection.multiply(cameraView)
  }

  project(surface: GameSurface, point: Point3): ClipPoint {
    return matrix(surface).transformPoint(point)
  }
}

export class Clear {
  readonly kind: ClearKind
  readonly colorValue: Color
  readonly depthValue: double

  static none(): Clear {
    return Clear {
      kind: ClearKind.None,
      colorValue: Color.transparent,
      depthValue: 1.0,
    }
  }

  static color(colorValue: Color): Clear {
    return Clear {
      kind: ClearKind.Color,
      colorValue: colorValue,
      depthValue: 1.0,
    }
  }

  static depth(depthValue: double): Clear {
    return Clear {
      kind: ClearKind.Depth,
      colorValue: Color.transparent,
      depthValue: depthValue,
    }
  }

  static colorDepth(colorValue: Color, depthValue: double): Clear {
    return Clear {
      kind: ClearKind.ColorDepth,
      colorValue: colorValue,
      depthValue: depthValue,
    }
  }
}

export class Depth {
  readonly mode: DepthMode

  static disabled(): Depth {
    return Depth { mode: DepthMode.Disabled }
  }

  static readOnly(): Depth {
    return Depth { mode: DepthMode.ReadOnly }
  }

  static readWrite(): Depth {
    return Depth { mode: DepthMode.ReadWrite }
  }
}

export class Blend {
  readonly mode: BlendMode

  static opaque(): Blend {
    return Blend { mode: BlendMode.Opaque }
  }

  static alpha(): Blend {
    return Blend { mode: BlendMode.Alpha }
  }
}

export class RenderPassDescriptor {
  camera: Camera = Camera {
    kind: CameraKind.Screen,
    viewProjection: Mat4 {
      m00: 1.0, m01: 0.0, m02: 0.0, m03: 0.0,
      m10: 0.0, m11: 1.0, m12: 0.0, m13: 0.0,
      m20: 0.0, m21: 0.0, m22: 1.0, m23: 0.0,
      m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
    },
  }
  clear: Clear = Clear {
    kind: ClearKind.None,
    colorValue: Color { r: 0.0, g: 0.0, b: 0.0, a: 0.0 },
    depthValue: 1.0,
  }
  depth: Depth = Depth { mode: DepthMode.Disabled }
  blend: Blend = Blend { mode: BlendMode.Opaque }
  winding: WindingMode = .CounterClockwise
  cull: CullMode = .None
}

export class RenderPass {
  private readonly gameSurface: GameSurface
  private passCamera: Camera
  private readonly passBlendModeCode: int
  private readonly native: NativeRenderPass

  surface(): GameSurface => gameSurface
  camera(): Camera => passCamera
  metalRenderCommandEncoderHandle(): long => native.metalRenderCommandEncoderHandle()
  metalCommandBufferHandle(): long => native.metalCommandBufferHandle()
  metalDeviceHandle(): long => native.metalDeviceHandle()
  nativeBlendModeCode(): int => passBlendModeCode
  hasDepthAttachment(): bool => native.hasDepthAttachment()
}

export class Renderer {
  private readonly gameSurface: GameSurface
  private readonly nativeFrame: NativeRenderFrame
  private isFinished: bool = false

  surface(): GameSurface => gameSurface

  loadTexture(path: string): Result<Texture, string> {
    return loadTextureForSurface(gameSurface, path)
  }

  createTexture(image: Image): Result<Texture, string> {
    return createTextureForSurface(gameSurface, image)
  }

  createTextureFromPixels(pixels: PixelBytes): Result<Texture, string> {
    return createTextureFromPixelsForSurface(gameSurface, pixels)
  }

  pass(desc: RenderPassDescriptor, draw: (pass: RenderPass): void): void {
    nativePass := nativeFrame.beginPass(
      clearKindCode(desc.clear.kind),
      desc.clear.colorValue.r,
      desc.clear.colorValue.g,
      desc.clear.colorValue.b,
      desc.clear.colorValue.a,
      desc.clear.depthValue,
      depthModeCode(desc.depth.mode),
      blendModeCode(desc.blend.mode),
      windingModeCode(desc.winding),
      cullModeCode(desc.cull),
    )

    renderPass := RenderPass {
      gameSurface: gameSurface,
      passCamera: desc.camera,
      passBlendModeCode: blendModeCode(desc.blend.mode),
      native: nativePass,
    }
    draw(renderPass)
    nativePass.end()
  }

  finish(): void {
    if isFinished {
      return
    }
    isFinished = true
    nativeFrame.commit()
  }
}

export function createRenderer(surface: GameSurface, nativeFrame: NativeRenderFrame): Renderer {
  return Renderer {
    gameSurface: surface,
    nativeFrame: nativeFrame,
  }
}

export function createTexture(native: NativeTexture): Texture {
  return Texture { native: native }
}

export function loadTextureForSurface(surface: GameSurface, path: string): Result<Texture, string> {
  return case NativeTexture.load(path, surface.metalDeviceHandle()) {
    s: Success -> Success {
      value: createTexture(s.value)
    },
    f: Failure -> Failure {
      error: f.error
    }
  }
}

export function createTextureForSurface(surface: GameSurface, image: Image): Result<Texture, string> {
  pixels := image.pixelBytes(PixelAlphaMode.Straight) else error {
    return Failure { error: error.message }
  }
  return createTextureFromPixelsForSurface(surface, pixels)
}

export function createTextureFromPixelsForSurface(surface: GameSurface, pixels: PixelBytes): Result<Texture, string> {
  return case NativeTexture.createRgba(
    pixels.bytes,
    pixels.width,
    pixels.height,
    pixels.alphaMode.value,
    surface.metalDeviceHandle(),
  ) {
    success: Success -> Success { value: createTexture(success.value) },
    failure: Failure -> Failure { error: failure.error },
  }
}
