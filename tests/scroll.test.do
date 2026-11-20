import { Assert } from "std/assert"

import { ScrollStepper, scrollBy } from "../index"

export function testPositiveDeltaRevealsEarlierRows(): none {
  s := ScrollStepper {}
  Assert.equal(s.wheel(1.0, 0.0), -1)   // content moves down: back toward the top
  Assert.equal(s.wheel(-1.0, 1.0), 1)
  Assert.equal(s.swipe(-3.0, 2.0), 1)
  Assert.equal(s.wheel(0.0, 3.0), 0)
}

export function testWheelMovesARowPerLine(): none {
  s := ScrollStepper {}
  Assert.equal(s.wheel(-1.0, 0.0), 1)
  Assert.equal(s.wheel(-1.0, 0.05), 1)  // a fast spin keeps moving
  Assert.equal(s.wheel(-3.0, 0.10), 3)  // accelerated notch
  Assert.equal(s.wheel(-0.5, 0.15), 0)  // high-resolution wheel: half a line
  Assert.equal(s.wheel(-0.5, 0.20), 1)
}

export function testSwipeMovesARowPerStep(): none {
  s := ScrollStepper { pointsPerRow: 10.0, gap: 0.2 }
  Assert.equal(s.swipe(-4.0, 0.0), 1)     // first event of the swipe
  Assert.equal(s.swipe(-4.0, 0.016), 0)
  Assert.equal(s.swipe(-4.0, 0.032), 0)
  Assert.equal(s.swipe(-4.0, 0.048), 1)   // carry reached 12
  Assert.equal(s.swipe(-25.0, 0.064), 2)  // carry 2 + 25 = 27
  Assert.equal(s.swipe(20.0, 0.080), -1)  // carry 7 - 20 = -13
}

export function testPauseStartsANewGesture(): none {
  s := ScrollStepper { pointsPerRow: 10.0, gap: 0.2 }
  s.swipe(-1.0, 0.0)
  Assert.equal(s.swipe(-9.0, 0.1), 0)
  Assert.equal(s.swipe(-9.0, 0.5), 1)     // carry dropped, first event again
  s.reset()
  Assert.equal(s.swipe(-1.0, 0.55), 1)
}

export function testScrollByClamps(): none {
  Assert.equal(scrollBy(3, 2, 10), 5)
  Assert.equal(scrollBy(9, 5, 10), 10)
  Assert.equal(scrollBy(1, -5, 10), 0)
  Assert.equal(scrollBy(0, 3, -2), 0)
}
