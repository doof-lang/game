import { Assert } from "std/assert"

import { Point, ScreenGesture, ScreenGestures } from "../index"

export function testScreenGesturesDispatchPanPayload(): void {
  gestures := ScreenGestures {}
  let calls = 0
  let lastX = 0.0
  let lastY = 0.0
  let lastDeltaX = 0.0
  let lastDeltaY = 0.0

  gestures.onPan((gesture): void => {
    calls += 1
    lastX = gesture.point.x
    lastY = gesture.point.y
    lastDeltaX = gesture.deltaX
    lastDeltaY = gesture.deltaY
  })

  gestures.emitPan(ScreenGesture.pan(Point(12.0, 24.0), 3.0, -4.0))

  Assert.equal(calls, 1)
  Assert.equal(lastX, 12.0)
  Assert.equal(lastY, 24.0)
  Assert.equal(lastDeltaX, 3.0)
  Assert.equal(lastDeltaY, -4.0)
}

export function testScreenGesturesDispatchScrollPayload(): void {
  gestures := ScreenGestures {}
  let calls = 0
  let lastDeltaX = 0.0
  let lastDeltaY = 0.0

  gestures.onScroll((gesture): void => {
    calls += 1
    lastDeltaX = gesture.deltaX
    lastDeltaY = gesture.deltaY
  })

  gestures.emitScroll(ScreenGesture.scroll(Point(2.0, 4.0), 5.0, 6.0))

  Assert.equal(calls, 1)
  Assert.equal(lastDeltaX, 5.0)
  Assert.equal(lastDeltaY, 6.0)
}

export function testScreenGesturesDispatchMagnifyPayload(): void {
  gestures := ScreenGestures {}
  let calls = 0
  let lastDeltaX = 0.0
  let lastDeltaY = 0.0
  let lastMagnification = 0.0

  gestures.onMagnify((gesture): void => {
    calls += 1
    lastDeltaX = gesture.deltaX
    lastDeltaY = gesture.deltaY
    lastMagnification = gesture.magnificationDelta
  })

  gestures.emitMagnify(ScreenGesture.magnify(Point(7.0, 8.0), 1.5, -2.5, 0.2))

  Assert.equal(calls, 1)
  Assert.equal(lastDeltaX, 1.5)
  Assert.equal(lastDeltaY, -2.5)
  Assert.equal(lastMagnification, 0.2)
}

export function testScreenGesturesDispatchDoubleTapPayload(): void {
  gestures := ScreenGestures {}
  let calls = 0
  let lastX = 0.0
  let lastY = 0.0

  gestures.onDoubleTap((gesture): void => {
    calls += 1
    lastX = gesture.point.x
    lastY = gesture.point.y
  })

  gestures.emitDoubleTap(ScreenGesture.doubleTap(Point(9.0, 10.0)))

  Assert.equal(calls, 1)
  Assert.equal(lastX, 9.0)
  Assert.equal(lastY, 10.0)
}
