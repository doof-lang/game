import { Assert } from "std/assert"

import { Point, ScreenPointer } from "../index"

export function testScreenPointerStartsReleasedAtOrigin(): void {
  pointer := ScreenPointer {}

  Assert.equal(pointer.x(), 0.0)
  Assert.equal(pointer.y(), 0.0)
  Assert.isFalse(pointer.pressed())
  Assert.isTrue(pointer.released())
}

export function testScreenPointerPressedAndReleasedHandlersFireOnEdgesOnly(): void {
  pointer := ScreenPointer {}
  let pressed = 0
  let released = 0
  let lastX = 0.0
  let lastY = 0.0

  pointer.onPressed((point): void => {
    pressed += 1
    lastX = point.x
    lastY = point.y
  })
  pointer.onReleased((point): void => {
    released += 1
    lastX = point.x
    lastY = point.y
  })

  pointer.pressAt(Point(12.0, 24.0))
  pointer.pressAt(Point(14.0, 28.0))
  Assert.isTrue(pointer.pressed())
  Assert.equal(pressed, 1)
  Assert.equal(released, 0)
  Assert.equal(lastX, 12.0)
  Assert.equal(lastY, 24.0)
  Assert.equal(pointer.x(), 14.0)
  Assert.equal(pointer.y(), 28.0)

  pointer.releaseAt(Point(16.0, 32.0))
  pointer.releaseAt(Point(18.0, 36.0))
  Assert.isTrue(pointer.released())
  Assert.equal(pressed, 1)
  Assert.equal(released, 1)
  Assert.equal(lastX, 16.0)
  Assert.equal(lastY, 32.0)
  Assert.equal(pointer.x(), 18.0)
  Assert.equal(pointer.y(), 36.0)
}

export function testScreenPointerMovedHandlersReceiveUpdatedPoint(): void {
  pointer := ScreenPointer {}
  let moved = 0
  let lastX = 0.0
  let lastY = 0.0

  pointer.onMoved((point): void => {
    moved += 1
    lastX = point.x
    lastY = point.y
  })

  pointer.moveTo(Point(4.0, 8.0))
  pointer.moveTo(Point(6.0, 10.0))

  Assert.equal(moved, 2)
  Assert.equal(lastX, 6.0)
  Assert.equal(lastY, 10.0)
  Assert.equal(pointer.x(), 6.0)
  Assert.equal(pointer.y(), 10.0)
}
