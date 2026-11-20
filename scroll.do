// Turns wheel and trackpad scrolling into whole rows of a list, in the
// platform's direction.
//
// std/game reports scroll deltas the way macOS and Windows do: a positive
// `deltaY` means the content should move down, revealing what is above it. The
// platform has already applied the user's "natural scrolling" setting, so
// following the sign is all a game needs to do.
//
// A mouse wheel arrives as `onScroll` gestures measured in lines, one event per
// notch. A trackpad or Magic Mouse swipe arrives as `onPan` gestures measured
// in points, many small events per swipe followed by momentum. Moving a row
// per event makes swipes race, and moving a row per N points makes a slow
// first touch feel dead, so the first event after a pause always moves one row
// and the rest of the gesture moves a row per `linesPerRow` or `pointsPerRow`.
export class ScrollStepper {
  // Wheel lines that move one row.
  readonly linesPerRow: double = 1.0
  // Swipe distance, in points, that moves one row.
  readonly pointsPerRow: double = 28.0
  // A pause longer than this (in the units of `now`) starts a new gesture.
  readonly gap: double = 0.2
  private let carry: double = 0.0
  private let last: double = -1.0e18

  // Feeds a wheel delta (`ScreenGesture.deltaY` from `onScroll`) seen at time
  // `now`. Returns the rows to move toward the end of the list: add them to the
  // number of rows hidden above the view. `now` is the time in seconds,
  // usually `app.seconds()`.
  wheel(deltaY: double, now: double): int => feed(-deltaY, now, linesPerRow)

  // Feeds a trackpad delta (`ScreenGesture.deltaY` from `onPan`). Returns rows
  // as `wheel` does.
  swipe(deltaY: double, now: double): int => feed(-deltaY, now, pointsPerRow)

  // Forgets any partial row, so the next event starts a new gesture.
  reset(): none {
    carry = 0.0
    last = -1.0e18
  }

  private feed(forward: double, now: double, step: double): int {
    let rows = 0
    if now - last > gap {
      carry = 0.0
      rows = if forward > 0.0 then 1 else if forward < 0.0 then -1 else 0
    } else {
      carry += forward
    }
    last = now
    while carry >= step {
      rows += 1
      carry -= step
    }
    while carry <= -step {
      rows -= 1
      carry += step
    }
    return rows
  }
}

// Adds `rows` to `offset` and keeps the result within 0...max (0 when max < 0).
export function scrollBy(offset: int, rows: int, max: int): int {
  next := offset + rows
  if next > max { return if max > 0 then max else 0 }
  if next < 0 { return 0 }
  return next
}
