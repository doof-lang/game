import { Point } from "./render"

export class ScreenGesture {
  readonly point: Point
  readonly deltaX: double = 0.0
  readonly deltaY: double = 0.0
  readonly magnificationDelta: double = 0.0

  static pan(point: Point, deltaX: double, deltaY: double): ScreenGesture {
    return ScreenGesture {
      point,
      deltaX,
      deltaY,
    }
  }

  static scroll(point: Point, deltaX: double, deltaY: double): ScreenGesture {
    return ScreenGesture {
      point,
      deltaX,
      deltaY,
    }
  }

  static magnify(point: Point, deltaX: double, deltaY: double, magnificationDelta: double): ScreenGesture {
    return ScreenGesture {
      point,
      deltaX,
      deltaY,
      magnificationDelta,
    }
  }

  static doubleTap(point: Point): ScreenGesture {
    return ScreenGesture {
      point,
    }
  }
}

type ScreenGestureHandler = (gesture: ScreenGesture): void

export class ScreenGestures {
  private panHandlers: ScreenGestureHandler[] = []
  private scrollHandlers: ScreenGestureHandler[] = []
  private magnifyHandlers: ScreenGestureHandler[] = []
  private doubleTapHandlers: ScreenGestureHandler[] = []

  onPan(handler: ScreenGestureHandler): ScreenGestures {
    panHandlers.push(handler)
    return this
  }

  onScroll(handler: ScreenGestureHandler): ScreenGestures {
    scrollHandlers.push(handler)
    return this
  }

  onMagnify(handler: ScreenGestureHandler): ScreenGestures {
    magnifyHandlers.push(handler)
    return this
  }

  onDoubleTap(handler: ScreenGestureHandler): ScreenGestures {
    doubleTapHandlers.push(handler)
    return this
  }

  emitPan(gesture: ScreenGesture): void {
    emit(panHandlers, gesture)
  }

  emitScroll(gesture: ScreenGesture): void {
    emit(scrollHandlers, gesture)
  }

  emitMagnify(gesture: ScreenGesture): void {
    emit(magnifyHandlers, gesture)
  }

  emitDoubleTap(gesture: ScreenGesture): void {
    emit(doubleTapHandlers, gesture)
  }
}

function emit(handlers: ScreenGestureHandler[], gesture: ScreenGesture): void {
  for handler of handlers {
    handler.call(gesture)
  }
}
