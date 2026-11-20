import { Assert } from "std/assert"
import { approxEqual, pow } from "std/math"

import { FrameClock, Pacer } from "../index"

function assertApprox(actual: double, expected: double): none {
  Assert.isTrue(approxEqual(actual, expected), "expected ${actual} to approximately equal ${expected}")
}

export function testClockAddsUpFrameTime(): none {
  c := FrameClock {}
  c.advance(10.0)
  assertApprox(c.seconds(), 0.0)
  assertApprox(c.delta(), 0.0)
  c.advance(10.2)
  c.advance(10.45)
  assertApprox(c.seconds(), 0.45)
  assertApprox(c.delta(), 0.25)
  Assert.equal(c.frames(), 3)
}

export function testClockCapsLongFrames(): none {
  c := FrameClock { maxDelta: 0.1 }
  c.advance(0.0)
  c.advance(30.0)        // the laptop slept
  assertApprox(c.delta(), 0.1)
  assertApprox(c.seconds(), 0.1)
  c.advance(29.0)        // a clock that steps back counts as no time
  assertApprox(c.delta(), 0.0)
}

export function testTicksKeepPaceAtAnyRefreshRate(): none {
  at60 := FrameClock {}
  at120 := FrameClock {}
  for i of 0..60 { at60.advance(double(i) / 60.0) }
  for i of 0..120 { at120.advance(double(i) / 120.0) }
  Assert.equal(at60.ticks(), 60)
  Assert.equal(at120.ticks(), 60)
  Assert.equal(at120.ticks(10.0), 10)
}

export function testPacerFiresOncePerInterval(): none {
  p := Pacer { interval: 0.5 }
  Assert.isTrue(p.step(0.0), "fires at once when not restarted")
  Assert.isFalse(p.step(0.2))
  Assert.isFalse(p.step(0.2))
  assertApprox(p.remaining(), 0.1)
  Assert.isTrue(p.step(0.2))
  Assert.isFalse(p.step(0.1))
}

export function testPacerNeverBursts(): none {
  p := Pacer { interval: 0.1 }
  p.restart()
  Assert.isTrue(p.step(1.0), "a long frame fires once")
  Assert.isFalse(p.step(0.05), "and then waits a whole interval")
  p.interval = 0.02
  Assert.isFalse(p.step(0.04))
  Assert.isTrue(p.step(0.02))
}

export function testEaseMatchesAt60And120Hz(): none {
  at60 := FrameClock {}
  at120 := FrameClock {}
  let x60 = 0.0
  let x120 = 0.0
  for i of 0..30 {
    at60.advance(double(i) / 60.0)
    x60 += (1.0 - x60) * at60.ease(0.2)
  }
  for i of 0..60 {
    at120.advance(double(i) / 120.0)
    x120 += (1.0 - x120) * at120.ease(0.2)
  }
  assertApprox(x60, x120)
  assertApprox(x60, 1.0 - pow(0.8, 30.0))
}

export function testPacerKeepsAnExactAverageRate(): none {
  // Every 60 Hz frame, even though frames jitter around 1/60 s.
  p := Pacer { interval: 1.0 / 60.0 }
  p.restart()
  let fired = 0
  for i of 0..<600 {
    if p.step(if i % 2 == 0 then 0.016 else 0.0173) { fired += 1 }
  }
  Assert.isTrue(fired >= 597 && fired <= 600, "fired ${fired} times in 600 frames")

  // Every other frame at 120 Hz.
  q := Pacer { interval: 1.0 / 60.0 }
  q.restart()
  let firedQ = 0
  for i of 0..<1200 {
    if q.step(1.0 / 120.0) { firedQ += 1 }
  }
  Assert.isTrue(firedQ >= 598 && firedQ <= 600, "fired ${firedQ} times in 1200 frames")
}
