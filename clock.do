import { floor, pow } from "std/math"

// Frame time for animation and pacing, so a game runs at the same speed on a
// 60 Hz, 120 Hz or throttled display.
//
// `GameApp` advances its clock (`app.clock()`) just before each `onRender`.
// `seconds` adds up the time between frames, but no single step counts for
// more than `maxDelta`. A stall, a breakpoint or a sleeping laptop then
// pauses the game rather than skipping it ahead.
export class FrameClock {
  // The longest step a single frame may take, in seconds.
  readonly maxDelta: double = 0.25
  // Game time in seconds since the first frame.
  private let elapsed: double = 0.0
  // Seconds between the last frame and the one before it, at most maxDelta.
  private let step: double = 0.0
  private let frameCount: int = 0
  private let lastNow: double = -1.0

  // Game time, in seconds since the first frame.
  seconds(): double => elapsed

  // Seconds since the previous frame (0 on the first), at most `maxDelta`.
  delta(): double => step

  // Frames advanced so far.
  frames(): int => frameCount

  // Game time counted in steps of 1/rate seconds: `ticks(60.0)` is a
  // 60 Hz frame counter that keeps that pace at any refresh rate.
  ticks(rate: double = 60.0): int => int(floor(elapsed * rate))

  // For motion that eases toward a target, moving `fraction` of the
  // remaining distance every 1/rate seconds: the share to move this frame.
  // `x += (target - x) * clock.ease(0.2)` looks the same at any refresh rate.
  ease(fraction: double, rate: double = 60.0): double {
    if fraction >= 1.0 { return 1.0 }
    if fraction <= 0.0 { return 0.0 }
    return 1.0 - pow(1.0 - fraction, step * rate)
  }

  // Starts a new frame at time `now`, in seconds on any steady clock.
  advance(now: double): none {
    if lastNow < 0.0 || now <= lastNow {
      step = 0.0
    } else {
      gap := now - lastNow
      step = if gap > maxDelta then maxDelta else gap
    }
    lastNow = now
    elapsed += step
    frameCount += 1
  }
}

// Fires every `interval` seconds of frame time: for bots that act at a
// readable speed, repeating actions, timed spawns.
export class Pacer {
  // Seconds between firings. Change it at any time; the change counts from
  // the next restart or firing.
  let interval: double
  private let wait: double = 0.0

  // Spends `delta` seconds (usually `clock.delta()`) and says whether the
  // interval has run out, at most once per call. Overshoot carries into the
  // next wait, so it fires at an exact average rate however frames fall. If
  // it falls a whole interval behind (a long frame), it fires once and then
  // waits a whole interval: it never catches up in a burst.
  step(delta: double): bool {
    wait -= delta
    if wait > 0.0 {
      return false
    }
    wait += interval
    if wait <= 0.0 {
      wait = interval
    }
    return true
  }

  // Waits a whole interval from now before firing again.
  restart(): none {
    wait = interval
  }

  // Seconds left before the next firing.
  remaining(): double => if wait > 0.0 then wait else 0.0
}
