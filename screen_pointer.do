import { InputState } from "./input"
import { Point } from "./render"
import { MouseButton } from "./types"

type ScreenPointerHandler = (point: Point): void

export class ScreenPointer {
  private point: Point = Point(0.0, 0.0)
  private down: bool = false
  private pressedHandlers: ScreenPointerHandler[] = []
  private releasedHandlers: ScreenPointerHandler[] = []
  private movedHandlers: ScreenPointerHandler[] = []

  static fromInput(input: InputState): ScreenPointer {
    pointer := ScreenPointer {}
    pointer.syncFromInput(input)
    return pointer
  }

  x(): double => point.x
  y(): double => point.y
  pressed(): bool => down
  released(): bool => !down

  onPressed(handler: ScreenPointerHandler): ScreenPointer {
    pressedHandlers.push(handler)
    return this
  }

  onReleased(handler: ScreenPointerHandler): ScreenPointer {
    releasedHandlers.push(handler)
    return this
  }

  onMoved(handler: ScreenPointerHandler): ScreenPointer {
    movedHandlers.push(handler)
    return this
  }

  moveTo(point: Point): void {
    this.point = point
    for handler of movedHandlers {
      handler.call(point)
    }
  }

  pressAt(point: Point): void {
    this.point = point
    if down {
      return
    }

    down = true
    for handler of pressedHandlers {
      handler.call(point)
    }
  }

  releaseAt(point: Point): void {
    this.point = point
    if !down {
      return
    }

    down = false
    for handler of releasedHandlers {
      handler.call(point)
    }
  }

  syncFromInput(input: InputState): void {
    point = Point(input.mouseX(), input.mouseY())
    down = input.isMouseButtonDown(MouseButton.Left) || input.isMouseButtonDown(MouseButton.Other)
  }
}
