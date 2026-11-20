import { Assert } from "std/assert"
import { approxEqual } from "std/math"

import { Canvas, CanvasTransform, Color, Point, Rect, placeTooltip } from "../index"

function assertApprox(actual: double, expected: double): none {
  Assert.isTrue(approxEqual(actual, expected), "expected ${actual} to approximately equal ${expected}")
}

export function testColorFadeAndMix(): none {
  faded := Color(1.0, 0.5, 0.25, 0.8).fade(0.5)
  assertApprox(faded.a, 0.4)
  assertApprox(faded.g, 0.5)

  mid := Color(0.0, 0.0, 0.0, 0.0).mix(Color(1.0, 0.5, 0.25, 1.0), 0.5)
  assertApprox(mid.r, 0.5)
  assertApprox(mid.g, 0.25)
  assertApprox(mid.b, 0.125)
  assertApprox(mid.a, 0.5)
}

export function testRectHelpers(): none {
  r := Rect(10.0, 20.0, 30.0, 40.0)
  assertApprox(r.right(), 40.0)
  assertApprox(r.bottom(), 60.0)
  assertApprox(r.center().x, 25.0)
  assertApprox(r.center().y, 40.0)

  inner := r.inset(5.0)
  assertApprox(inner.x, 15.0)
  assertApprox(inner.width, 20.0)
  assertApprox(inner.height, 30.0)

  Assert.isTrue(r.contains(Point(10.0, 20.0)))
  Assert.isTrue(r.contains(Point(40.0, 60.0)))
  Assert.isFalse(r.contains(Point(9.9, 30.0)))
  Assert.isFalse(r.contains(Point(20.0, 60.1)))
}

export function testTransformFitLetterboxesAndInverts(): none {
  // A 200x100 board in a 400x400 area: scale 2, centred vertically.
  t := CanvasTransform.fit(Point(200.0, 100.0), Rect(0.0, 0.0, 400.0, 400.0))
  assertApprox(t.scale, 2.0)
  assertApprox(t.offset.x, 0.0)
  assertApprox(t.offset.y, 100.0)

  screen := t.apply(Point(50.0, 25.0))
  assertApprox(screen.x, 100.0)
  assertApprox(screen.y, 150.0)
  back := t.invert(screen)
  assertApprox(back.x, 50.0)
  assertApprox(back.y, 25.0)
}

export function testTransformComposesInnerFirst(): none {
  outer := CanvasTransform { offset: Point(10.0, 10.0), scale: 2.0 }
  inner := CanvasTransform { offset: Point(5.0, 0.0), scale: 3.0 }
  p := outer.compose(inner).apply(Point(1.0, 1.0))
  // inner: (8, 3); outer: (26, 16)
  assertApprox(p.x, 26.0)
  assertApprox(p.y, 16.0)
}

export function testClickRunsTopmostTargetOfLastFrame(): none {
  canvas := Canvas {}
  let clicked = ""
  canvas.onClick(Rect(0.0, 0.0, 100.0, 100.0), (): none => { clicked = "under" })
  canvas.onClick(Rect(50.0, 50.0, 100.0, 100.0), (): none => { clicked = "over" })

  // Nothing is clickable until the frame ends.
  Assert.isFalse(canvas.click(Point(10.0, 10.0)))
  canvas.end()

  Assert.isTrue(canvas.click(Point(75.0, 75.0)))
  Assert.equal(clicked, "over")
  Assert.isTrue(canvas.click(Point(10.0, 10.0)))
  Assert.equal(clicked, "under")
  Assert.isFalse(canvas.click(Point(300.0, 300.0)))
}

export function testBlockedClicksDoNothingButAreHandled(): none {
  canvas := Canvas {}
  let clicked = false
  canvas.onClick(Rect(0.0, 0.0, 100.0, 100.0), (): none => { clicked = true })
  canvas.blockClicks(Rect(0.0, 0.0, 400.0, 400.0))
  canvas.end()

  Assert.isTrue(canvas.click(Point(10.0, 10.0)))
  Assert.isFalse(clicked)
  Assert.isTrue(canvas.covers(Point(300.0, 300.0)))
}

export function testModalDropsTargetsUnderItAndSwallowsClicks(): none {
  canvas := Canvas {}
  let clicked = ""
  canvas.onClick(Rect(0.0, 0.0, 100.0, 100.0), (): none => { clicked = "under" })
  canvas.modal()
  canvas.onClick(Rect(200.0, 200.0, 50.0, 50.0), (): none => { clicked = "dialog" })
  canvas.end()

  Assert.isTrue(canvas.click(Point(10.0, 10.0)))
  Assert.equal(clicked, "")
  Assert.isTrue(canvas.click(Point(900.0, 900.0)))
  Assert.equal(clicked, "")
  Assert.isTrue(canvas.click(Point(210.0, 210.0)))
  Assert.equal(clicked, "dialog")
}

export function testClickOutsideCanCloseAModal(): none {
  canvas := Canvas {}
  let open = true
  canvas.modal()
  canvas.onClick(Rect(0.0, 0.0, 1000.0, 1000.0), (): none => { open = false })
  canvas.onClick(Rect(100.0, 100.0, 50.0, 50.0), (): none => {})
  canvas.end()

  canvas.click(Point(120.0, 120.0))
  Assert.isTrue(open)
  canvas.click(Point(500.0, 500.0))
  Assert.isFalse(open)
}

export function testHoveringIsOffUnderLastFramesModal(): none {
  canvas := Canvas {}
  button := Rect(0.0, 0.0, 100.0, 40.0)
  pointer := Point(10.0, 10.0)

  // A frame without a dialog: the button reacts.
  Assert.isTrue(canvas.hovering(button, pointer))
  canvas.onClick(button, (): none => {})
  canvas.end()

  // A frame with a dialog over it.
  Assert.isTrue(canvas.hovering(button, pointer))
  canvas.onClick(button, (): none => {})
  canvas.modal()
  canvas.end()

  // From then on, what is drawn before the dialog is covered, and the dialog
  // itself is not, even with no click targets before it.
  next := Canvas {}
  next.modal()
  next.end()
  Assert.isTrue(next.isUnderModal())
  Assert.isFalse(next.hovering(button, pointer))
  next.modal()
  Assert.isFalse(next.isUnderModal())
  Assert.isTrue(next.hovering(button, pointer))

  Assert.isTrue(canvas.isUnderModal())
  Assert.isFalse(canvas.hovering(button, pointer))
  canvas.onClick(button, (): none => {})
  canvas.modal()
  Assert.isFalse(canvas.isUnderModal())
  Assert.isTrue(canvas.hovering(button, Point(10.0, 10.0)))
  Assert.isFalse(canvas.hovering(button, Point(10.0, 60.0)))
  canvas.end()

  // The dialog closes: the next frame still has last frame's modal, the one
  // after is clear.
  canvas.onClick(button, (): none => {})
  canvas.end()
  Assert.isTrue(canvas.hovering(button, pointer))
}

export function testClickTargetsFollowTheTransform(): none {
  canvas := Canvas {}
  let clicked = false
  canvas.push(CanvasTransform { offset: Point(100.0, 0.0), scale: 2.0 })
  canvas.onClick(Rect(0.0, 0.0, 10.0, 10.0), (): none => { clicked = true })
  inside := canvas.toCanvas(Point(110.0, 10.0))
  canvas.pop()
  canvas.end()

  assertApprox(inside.x, 5.0)
  assertApprox(inside.y, 5.0)
  Assert.isFalse(canvas.click(Point(5.0, 5.0)))
  Assert.isTrue(canvas.click(Point(115.0, 15.0)))
  Assert.isTrue(clicked)
}

export function testShapesBuildWithoutAPass(): none {
  canvas := Canvas {}
  canvas.round(Rect(0.0, 0.0, 50.0, 20.0), 6.0, Color.white)
  canvas.shadow(Rect(0.0, 0.0, 50.0, 20.0), 6.0, 8.0)
  canvas.pie(Point(10.0, 10.0), 8.0, 0.0, 3.0, Color.red)
  canvas.arc(Point(10.0, 10.0), 8.0, 2.0, 0.0, 6.0, Color.blue)
  canvas.polygon([Point(0.0, 0.0), Point(10.0, 0.0), Point(5.0, 8.0)], Color.green)
  canvas.dashed(Point(0.0, 0.0), Point(100.0, 0.0), 2.0, 6.0, 4.0, Color.black)
  canvas.end()
}

export function testTooltipFlipsAndClamps(): none {
  screen := Rect(0.0, 0.0, 800.0, 600.0)
  size := Point(200.0, 100.0)

  plain := placeTooltip(Point(100.0, 100.0), size, screen)
  assertApprox(plain.x, 118.0)
  assertApprox(plain.y, 118.0)

  flipped := placeTooltip(Point(700.0, 550.0), size, screen)
  assertApprox(flipped.x, 482.0)
  assertApprox(flipped.y, 492.0)
}
