// Immediate-mode 2D drawing over std/game: rounded shapes, gradients, soft
// shadows and glows, atlas images and scaled bitmap text, batched into as few
// meshes as the paint order allows. Everything is in logical screen points, so
// draw inside a pass whose camera is `Camera.screen()`.
//
//   canvas := Canvas {}
//   body := canvas.font(app.loadBitmapFontResource("fonts/body.fnt")!, 40.0)
//   renderer.pass(RenderPassDescriptor { camera: Camera.screen(), blend: Blend.alpha() }, (pass): none => {
//     canvas.begin(pass)
//     canvas.round(Rect(20.0, 20.0, 200.0, 60.0), 10.0, Color(0.2, 0.2, 0.25))
//     canvas.text(body, "Hello", 32.0, 36.0, 18.0, Color.white)
//     canvas.end()
//   })

import { Color, Point, Point3, Rect, RenderPass, Texture } from "./render"
import { SimpleMesh, SimpleMeshBuilder, drawSimpleMesh, drawTexturedSimpleMesh } from "./mesh"
import { BitmapFont, TextAlign, TextBounds, TextLayoutOptions, createTextMeshSpec, measureText } from "./text"
import { PI, cos, sin, sqrt } from "std/math"

// A bitmap font registered with a canvas, plus the pixel size it was
// rasterised at (the `size` on the `info` line of its .fnt file). Text is
// drawn at any size by scaling from that.
export class CanvasFont {
  font: BitmapFont
  readonly pixels: double
  readonly slot: int
}

// Corner arc resolution for rounded shapes.
readonly ARC_STEPS = 6

// The outline of a rounded rectangle, clockwise from the top-left corner.
function outline(r: Rect, radius: double): Point[] {
  limit := if r.width < r.height then r.width / 2.0 else r.height / 2.0
  rad := if radius > limit then limit else radius
  let points: Point[] = []
  if rad <= 0.01 {
    points.push(Point(r.x, r.y))
    points.push(Point(r.x + r.width, r.y))
    points.push(Point(r.x + r.width, r.y + r.height))
    points.push(Point(r.x, r.y + r.height))
    return points
  }
  centers: Point[] := [
    Point(r.x + rad, r.y + rad),
    Point(r.x + r.width - rad, r.y + rad),
    Point(r.x + r.width - rad, r.y + r.height - rad),
    Point(r.x + rad, r.y + r.height - rad),
  ]
  for corner of 0..<4 {
    start := PI + double(corner) * PI / 2.0
    for step of 0..<(ARC_STEPS + 1) {
      angle := start + double(step) / double(ARC_STEPS) * PI / 2.0
      points.push(Point(centers[corner].x + cos(angle) * rad, centers[corner].y + sin(angle) * rad))
    }
  }
  return points
}

// A uniform scale then offset from canvas space to screen space:
// screen = point * scale + offset.
export struct CanvasTransform {
  readonly offset: Point = Point(0.0, 0.0)
  readonly scale: double = 1.0

  static readonly identity = CanvasTransform {}

  // The transform that draws a `content`-sized space as large as fits in
  // `bounds`, centred (letterboxed) in it.
  static fit(content: Point, bounds: Rect): CanvasTransform {
    if content.x <= 0.0 || content.y <= 0.0 {
      return CanvasTransform { offset: Point(bounds.x, bounds.y) }
    }
    sx := bounds.width / content.x
    sy := bounds.height / content.y
    k := if sx < sy then sx else sy
    return CanvasTransform {
      offset: Point(bounds.x + (bounds.width - content.x * k) / 2.0, bounds.y + (bounds.height - content.y * k) / 2.0),
      scale: k,
    }
  }

  // This transform applied after `inner`.
  compose(inner: CanvasTransform): CanvasTransform {
    return CanvasTransform {
      offset: Point(offset.x + inner.offset.x * scale, offset.y + inner.offset.y * scale),
      scale: scale * inner.scale,
    }
  }

  apply(p: Point): Point => Point(p.x * scale + offset.x, p.y * scale + offset.y)
  applyRect(r: Rect): Rect => Rect(r.x * scale + offset.x, r.y * scale + offset.y, r.width * scale, r.height * scale)
  invert(p: Point): Point => Point((p.x - offset.x) / scale, (p.y - offset.y) / scale)
}

// A click target recorded while drawing, in screen space. A target with no
// action only blocks what is under it (a dialog's backdrop).
class HitTarget {
  readonly rect: Rect
  readonly action: (): none
  readonly blocks: bool = false
}

function noAction(): none {}

// Covers any screen: the catch-all blocker at the bottom of a modal layer.
readonly EVERYWHERE = Rect(-1000000000.0, -1000000000.0, 2000000000.0, 2000000000.0)

// One batched mesh and the texture slot it is drawn with.
class Batch {
  mesh: SimpleMesh
  readonly slot: int
}

export class Canvas {
  textures: Texture[] = []
  private let pass: RenderPass | none = none
  private let builder: SimpleMeshBuilder = SimpleMeshBuilder()
  // 0 = untextured; otherwise an index into `textures` plus one.
  private let slot: int = 0
  private let pending: int = 0
  // The batches of the frame last drawn, for `replay`.
  private let batches: Batch[] = []
  private let current: CanvasTransform = CanvasTransform.identity
  private let saved: CanvasTransform[] = []
  // Click targets of the frame being drawn, and of the last finished frame.
  private let building: HitTarget[] = []
  private let hits: HitTarget[] = []
  // How many click targets (and modal starts) have been recorded this frame,
  // dropped ones included: a position in the frame's drawing order.
  private let recorded: int = 0
  // Where this frame's and the last frame's modal layer began, or -1.
  private let modalAt: int = -1
  private let lastModalAt: int = -1

  // Registers a texture and returns the slot to pass to `image`.
  register(texture: Texture): int {
    textures.push(texture)
    return textures.length
  }

  // Registers a bitmap font rasterised at `pixels` for drawing text.
  font(font: BitmapFont, pixels: double): CanvasFont {
    return CanvasFont { font, pixels, slot: register(font.texture) }
  }

  begin(target: RenderPass): none {
    pass = target
    builder = SimpleMeshBuilder()
    slot = 0
    pending = 0
    batches = []
    current = CanvasTransform.identity
    saved = []
    building = []
    recorded = 0
    modalAt = -1
  }

  // Draws the previous frame again without rebuilding it.
  replay(target: RenderPass): none {
    for batch of batches {
      if batch.slot == 0 {
        drawSimpleMesh(target, batch.mesh)
      } else {
        drawTexturedSimpleMesh(target, batch.mesh, textures[batch.slot - 1])
      }
    }
  }

  end(): none {
    flush()
    pass = none
    hits = building
    building = []
    lastModalAt = modalAt
    recorded = 0
    modalAt = -1
  }

  private flush(): none {
    if pending == 0 {
      return
    }
    target := pass else {
      return
    }
    mesh := builder.build(target.surface())
    if slot == 0 {
      drawSimpleMesh(target, mesh)
    } else {
      drawTexturedSimpleMesh(target, mesh, textures[slot - 1])
    }
    batches.push(Batch { mesh, slot })
    builder = SimpleMeshBuilder()
    pending = 0
  }

  private use(next: int): none {
    if next != slot {
      flush()
      slot = next
    }
  }

  private vert(p: Point, color: Color, uv: Point = Point(0.0, 0.0)): int {
    pending += 1
    q := current.apply(p)
    return builder.vertex(Point3(q.x, q.y, 0.0), color, uv)
  }

  // --------------------------------------------------------- hit testing

  // Makes `r` (in canvas space) clickable: `click` runs `action` when it is
  // the topmost target under the point. Targets added later are on top, so
  // record a target as its control is drawn. Targets take effect when the
  // frame ends and stay until the next one does.
  onClick(r: Rect, action: (): none): none {
    building.push(HitTarget { rect: current.applyRect(r), action })
    recorded += 1
  }

  // Swallows clicks over `r` without acting, so targets drawn earlier can't be
  // reached through it.
  blockClicks(r: Rect): none {
    building.push(HitTarget { rect: current.applyRect(r), action: noAction, blocks: true })
    recorded += 1
  }

  // Starts a modal layer (a dialog or a menu) over everything drawn so far
  // this frame. Nothing drawn before it can be clicked, and `click` swallows
  // any click that no target drawn after it takes, so a click outside a
  // dialog never falls through to the game. Next frame, `hovering` and
  // `isUnderModal` treat everything drawn before this point as covered.
  // To close a menu by clicking outside it, record a full-screen `onClick`
  // right after `modal()`.
  modal(): none {
    building = [HitTarget { rect: EVERYWHERE, action: noAction, blocks: true }]
    modalAt = recorded
    recorded += 1
  }

  // True when the last frame had a modal layer and drawing has not yet
  // reached it this frame: whatever is being drawn now is under the dialog,
  // so it shouldn't react to the pointer.
  isUnderModal(): bool => lastModalAt >= 0 && recorded <= lastModalAt

  // Runs the topmost target of the last frame under the screen point `p`.
  // Returns false when there is none, so the caller can handle the click
  // itself (on a board). Under a modal layer every click is handled.
  click(p: Point): bool {
    let i = hits.length - 1
    while i >= 0 {
      hit := hits[i]
      if hit.rect.contains(p) {
        if !hit.blocks {
          hit.action()
        }
        return true
      }
      i -= 1
    }
    return false
  }

  // True when a target or blocker of the last frame is under `p`.
  covers(p: Point): bool {
    for hit of hits {
      if hit.rect.contains(p) {
        return true
      }
    }
    return false
  }

  // True when the screen point `p` is inside `r` (in canvas space) and what is
  // being drawn now is not under a modal layer: use it for hover highlights
  // and tooltips instead of `r.contains(pointer)`.
  hovering(r: Rect, p: Point): bool => !isUnderModal() && current.applyRect(r).contains(p)

  // ----------------------------------------------------------- transform

  // Draws everything until the matching `pop` through `transform`, applied
  // inside whatever transform is already in effect. Sizes scale too: a line
  // 2 wide under scale 0.5 is 1 point wide on screen.
  push(transform: CanvasTransform): none {
    saved.push(current)
    current = current.compose(transform)
  }

  pop(): none {
    if saved.length > 0 {
      current = saved.pop()!
    }
  }

  // The transform now in effect, from canvas space to screen space.
  transform(): CanvasTransform => current

  // Maps a screen point (such as the pointer) into the current canvas space.
  toCanvas(p: Point): Point => current.invert(p)

  // Maps a rect in the current canvas space to screen space, for hit testing.
  toScreen(r: Rect): Rect => current.applyRect(r)

  // -------------------------------------------------------------- shapes

  rect(r: Rect, color: Color): none {
    gradient(r, color, color)
  }

  // Vertical gradient.
  gradient(r: Rect, top: Color, bottom: Color): none {
    use(0)
    a := vert(Point(r.x, r.y), top)
    b := vert(Point(r.x + r.width, r.y), top)
    c := vert(Point(r.x + r.width, r.y + r.height), bottom)
    d := vert(Point(r.x, r.y + r.height), bottom)
    builder.triangle(a, b, c)
    builder.triangle(a, c, d)
  }

  // Horizontal gradient.
  gradientH(r: Rect, left: Color, right: Color): none {
    use(0)
    a := vert(Point(r.x, r.y), left)
    b := vert(Point(r.x + r.width, r.y), right)
    c := vert(Point(r.x + r.width, r.y + r.height), right)
    d := vert(Point(r.x, r.y + r.height), left)
    builder.triangle(a, b, c)
    builder.triangle(a, c, d)
  }

  round(r: Rect, radius: double, color: Color): none {
    roundGradient(r, radius, color, color)
  }

  roundGradient(r: Rect, radius: double, top: Color, bottom: Color): none {
    use(0)
    points := outline(r, radius)
    center := vert(Point(r.x + r.width / 2.0, r.y + r.height / 2.0), top.mix(bottom, 0.5))
    let first = -1
    let prev = -1
    for p of points {
      t := if r.height > 0.0 then (p.y - r.y) / r.height else 0.0
      index := vert(p, top.mix(bottom, t))
      if prev >= 0 {
        builder.triangle(center, prev, index)
      } else {
        first = index
      }
      prev = index
    }
    builder.triangle(center, prev, first)
  }

  // A band between two outlines of the same rounded rectangle; `outer` grows
  // (or, negative, shrinks) the far edge. Used for borders, glows and shadows.
  private band(r: Rect, radius: double, outer: double, innerColor: Color, outerColor: Color): none {
    use(0)
    inner := outline(r, radius)
    grown := outline(Rect(r.x - outer, r.y - outer, r.width + outer * 2.0, r.height + outer * 2.0), radius + outer)
    if inner.length != grown.length {
      return
    }
    let firstIn = -1
    let firstOut = -1
    let prevIn = -1
    let prevOut = -1
    for i of 0..<inner.length {
      a := vert(inner[i], innerColor)
      b := vert(grown[i], outerColor)
      if prevIn >= 0 {
        builder.triangle(prevIn, prevOut, b)
        builder.triangle(prevIn, b, a)
      } else {
        firstIn = a
        firstOut = b
      }
      prevIn = a
      prevOut = b
    }
    builder.triangle(prevIn, prevOut, firstOut)
    builder.triangle(prevIn, firstOut, firstIn)
  }

  // Border drawn inside the rectangle's edge.
  stroke(r: Rect, radius: double, width: double, color: Color): none {
    if radius <= 0.01 {
      rect(Rect(r.x, r.y, r.width, width), color)
      rect(Rect(r.x, r.y + r.height - width, r.width, width), color)
      rect(Rect(r.x, r.y + width, width, r.height - width * 2.0), color)
      rect(Rect(r.x + r.width - width, r.y + width, width, r.height - width * 2.0), color)
      return
    }
    shrunk := r.inset(width)
    band(shrunk, if radius > width then radius - width else 0.5, width, color, color)
  }

  // Feathered halo fading out over `spread` beyond the rectangle.
  glow(r: Rect, radius: double, spread: double, color: Color): none {
    band(r, radius, spread, color, color.fade(0.0))
  }

  // Soft drop shadow under a rounded rectangle.
  shadow(r: Rect, radius: double, spread: double, alpha: double = 0.5): none {
    dark := Color(0.0, 0.0, 0.0, alpha)
    moved := Rect(r.x, r.y + spread * 0.35, r.width, r.height)
    round(moved, radius, dark)
    glow(moved, radius, spread, dark)
  }

  circle(center: Point, radius: double, color: Color): none {
    round(Rect(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0), radius, color)
  }

  ring(center: Point, radius: double, width: double, color: Color): none {
    stroke(Rect(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0), radius, width, color)
  }

  halo(center: Point, radius: double, spread: double, color: Color): none {
    glow(Rect(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0), radius, spread, color)
  }

  line(a: Point, b: Point, width: double, color: Color): none {
    use(0)
    dx := b.x - a.x
    dy := b.y - a.y
    length := sqrt(dx * dx + dy * dy)
    if length <= 0.0001 {
      return
    }
    nx := -dy / length * width / 2.0
    ny := dx / length * width / 2.0
    p0 := vert(Point(a.x + nx, a.y + ny), color)
    p1 := vert(Point(b.x + nx, b.y + ny), color)
    p2 := vert(Point(b.x - nx, b.y - ny), color)
    p3 := vert(Point(a.x - nx, a.y - ny), color)
    builder.triangle(p0, p1, p2)
    builder.triangle(p0, p2, p3)
  }

  triangle(a: Point, b: Point, c: Point, color: Color): none {
    use(0)
    builder.triangle(vert(a, color), vert(b, color), vert(c, color))
  }

  // A five-pointed star with its top point up.
  star(center: Point, radius: double, color: Color): none {
    use(0)
    hub := vert(center, color)
    let first = -1
    let prev = -1
    for i of 0..<10 {
      angle := -PI / 2.0 + double(i) * PI / 5.0
      reach := if i % 2 == 0 then radius else radius * 0.42
      index := vert(Point(center.x + cos(angle) * reach, center.y + sin(angle) * reach), color)
      if prev >= 0 {
        builder.triangle(hub, prev, index)
      } else {
        first = index
      }
      prev = index
    }
    builder.triangle(hub, prev, first)
  }

  // A filled convex polygon (or any polygon that is star-shaped about its
  // first point).
  polygon(points: readonly Point[], color: Color): none {
    if points.length < 3 {
      return
    }
    use(0)
    first := vert(points[0], color)
    let prev = vert(points[1], color)
    for i of 2..<points.length {
      next := vert(points[i], color)
      builder.triangle(first, prev, next)
      prev = next
    }
  }

  // A filled wedge of a circle from angle `from` to `to` (radians, clockwise
  // from 3 o'clock on screen). A wedge from -PI/2 sweeping `fraction * 2 PI`
  // makes a pie timer.
  pie(center: Point, radius: double, from: double, to: double, color: Color): none {
    use(0)
    steps := segments(radius, to - from)
    hub := vert(center, color)
    let prev = -1
    for i of 0..<(steps + 1) {
      angle := from + (to - from) * double(i) / double(steps)
      index := vert(Point(center.x + cos(angle) * radius, center.y + sin(angle) * radius), color)
      if prev >= 0 {
        builder.triangle(hub, prev, index)
      }
      prev = index
    }
  }

  // An arc of a ring `width` wide whose outer edge is at `radius`, from
  // angle `from` to `to` — a progress meter or a partial ring.
  arc(center: Point, radius: double, width: double, from: double, to: double, color: Color): none {
    use(0)
    steps := segments(radius, to - from)
    inner := if radius > width then radius - width else 0.0
    let prevIn = -1
    let prevOut = -1
    for i of 0..<(steps + 1) {
      angle := from + (to - from) * double(i) / double(steps)
      c := cos(angle)
      s := sin(angle)
      a := vert(Point(center.x + c * inner, center.y + s * inner), color)
      b := vert(Point(center.x + c * radius, center.y + s * radius), color)
      if prevIn >= 0 {
        builder.triangle(prevIn, prevOut, b)
        builder.triangle(prevIn, b, a)
      }
      prevIn = a
      prevOut = b
    }
  }

  // Enough straight segments for a smooth curve of this radius and sweep.
  private segments(radius: double, sweep: double): int {
    turn := if sweep < 0.0 then -sweep else sweep
    n := int(turn / (PI / 2.0) * double(ARC_STEPS) * (if radius * current.scale > 40.0 then 2.0 else 1.0)) + 1
    return if n < 1 then 1 else n
  }

  // A line from `a` to `b` drawn as dashes `dash` long with `gapLength` between.
  dashed(a: Point, b: Point, width: double, dash: double, gapLength: double, color: Color): none {
    dx := b.x - a.x
    dy := b.y - a.y
    length := sqrt(dx * dx + dy * dy)
    if length <= 0.0001 || dash <= 0.0 {
      return
    }
    ux := dx / length
    uy := dy / length
    let at = 0.0
    while at < length {
      end := if at + dash > length then length else at + dash
      line(Point(a.x + ux * at, a.y + uy * at), Point(a.x + ux * end, a.y + uy * end), width, color)
      at = end + gapLength
    }
  }

  // -------------------------------------------------------------- images

  // Draws the `uv` region (in 0..1 texture space) of a registered texture
  // into a rounded rectangle. `texture` is the slot from `register`.
  image(texture: int, r: Rect, uv: Rect, radius: double = 0.0, tint: Color = Color(1.0, 1.0, 1.0)): none {
    use(texture)
    points := outline(r, radius)
    center := vert(Point(r.x + r.width / 2.0, r.y + r.height / 2.0), tint, Point(uv.x + uv.width / 2.0, uv.y + uv.height / 2.0))
    let first = -1
    let prev = -1
    for p of points {
      u := uv.x + (p.x - r.x) / r.width * uv.width
      v := uv.y + (p.y - r.y) / r.height * uv.height
      index := vert(p, tint, Point(u, v))
      if prev >= 0 {
        builder.triangle(center, prev, index)
      } else {
        first = index
      }
      prev = index
    }
    builder.triangle(center, prev, first)
  }

  // ---------------------------------------------------------------- text

  // The size of `value` drawn at `size`, wrapped at `maxWidth` when given.
  measure(face: CanvasFont, value: string, size: double, maxWidth: double = 0.0): TextBounds {
    scale := size / face.pixels
    bounds := measureText(face.font, value, TextLayoutOptions { maxWidth: if maxWidth > 0.0 then maxWidth / scale else 0.0 })
    return TextBounds { width: bounds.width * scale, height: bounds.height * scale, lineCount: bounds.lineCount }
  }

  lineHeight(face: CanvasFont, size: double): double => double(face.font.lineHeight) * size / face.pixels

  // Draws text with its top-left at (x, y); wraps at `maxWidth` when given.
  // Centre and right alignment are relative to `maxWidth`.
  text(
    face: CanvasFont,
    value: string,
    x: double,
    y: double,
    size: double,
    color: Color,
    maxWidth: double = 0.0,
    align: TextAlign = TextAlign.Left,
  ): none {
    if value == "" {
      return
    }
    scale := size / face.pixels
    spec := createTextMeshSpec(face.font, value, TextLayoutOptions {
      maxWidth: if maxWidth > 0.0 then maxWidth / scale else 0.0,
      align,
      color,
    })
    use(face.slot)
    let base = -1
    for i of 0..<spec.positions.length {
      p := spec.positions[i]
      index := vert(Point(x + p.x * scale, y + p.y * scale), color, spec.uvs[i])
      if base < 0 {
        base = index
      }
    }
    let i = 0
    while i + 2 < spec.indices.length {
      builder.triangle(base + spec.indices[i], base + spec.indices[i + 1], base + spec.indices[i + 2])
      i += 3
    }
  }

  // Wrapped text; returns the height drawn.
  paragraph(face: CanvasFont, value: string, x: double, y: double, size: double, color: Color, maxWidth: double): double {
    text(face, value, x, y, size, color, maxWidth)
    return measure(face, value, size, maxWidth).height
  }

  // Single line, clipped with an ellipsis to fit `maxWidth`.
  textClipped(face: CanvasFont, value: string, x: double, y: double, size: double, color: Color, maxWidth: double): none {
    text(face, clip(face, value, size, maxWidth), x, y, size, color)
  }

  clip(face: CanvasFont, value: string, size: double, maxWidth: double): string {
    if measure(face, value, size).width <= maxWidth {
      return value
    }
    let cut = value.length
    while cut > 1 && measure(face, value.substring(0, cut) + "…", size).width > maxWidth {
      cut -= 1
    }
    return value.substring(0, cut) + "…"
  }
}

// Where to put a tooltip `size` big for a pointer at `anchor`: below and to
// the right, flipped to the left when it would leave `bounds`, and kept
// inside `bounds` vertically.
export function placeTooltip(anchor: Point, size: Point, bounds: Rect, offset: double = 18.0, margin: double = 8.0): Rect {
  let x = anchor.x + offset
  let y = anchor.y + offset
  if x + size.x > bounds.x + bounds.width - margin {
    x = anchor.x - size.x - offset
  }
  if x < bounds.x + margin {
    x = bounds.x + margin
  }
  if y + size.y > bounds.y + bounds.height - margin {
    y = bounds.y + bounds.height - margin - size.y
  }
  if y < bounds.y + margin {
    y = bounds.y + margin
  }
  return Rect(x, y, size.x, size.y)
}
