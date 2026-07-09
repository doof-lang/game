# Input

`std/game` separates high-level app events from queryable input state. Use
`onEvent` for close, resize, scroll, gestures, and controller connection
events. Use input helpers for buttons, pointers, and analog values.

## Keyboard Buttons

```doof
app.key(Key.Escape).onPressed() {
  app.stop()
}

app.key(Key.Space).onPressed() {
  println("jump")
}

app.onRender() {
  if app.input.isKeyDown(Key.A) {
    // Move left while A is held.
  }
}
```

`InputButton` handles edges such as press and release. `app.input` handles
current state.

## Combine Keyboard And Controller Buttons

```doof
jump := InputButton.any([
  app.key(Key.Space),
  app.controllerButton(.One, .South),
])

jump.onPressed() {
  println("jump")
}
```

This keeps gameplay code independent of which device produced the action.

## Mouse And Touch Pointer

`screenPointer()` tracks the primary pointer in screen coordinates. On iOS,
single-touch input is routed through the same pointer and mouse button model.

```doof
pointer := app.screenPointer()

pointer.onPressed() {
  println("pressed at ${pointer.x()}, ${pointer.y()}")
}

pointer.onMoved((point): void => {
  if pointer.pressed() {
    println("dragged to ${point.x}, ${point.y}")
  }
})
```

Call `syncFromInput` once per frame if you create a pointer directly instead
of using `app.screenPointer()`.

```doof
pointer.syncFromInput(app.input)
```

Use `Camera.screen()` for matching draw and pointer coordinates.

## Scroll, Pan, Magnify, And Resize

```doof
app.onEvent() {
  if event.kind() == GameEventKind.Resized {
    layoutFor(app.surface.width(), app.surface.height())
    app.requestRender()
  } else if event.kind() == GameEventKind.Scroll {
    cameraPanX += event.scrollDeltaX()
    cameraPanY += event.scrollDeltaY()
  } else if event.kind() == GameEventKind.Magnify {
    zoom += event.magnificationDelta()
  }
}
```

Frame-relative deltas are also available through `app.input`.

## Controller Sticks And Triggers

```doof
left := app.controllerStick(.One, .Left)
fire := app.controllerButton(.One, .RightTrigger)

fire.onPressed() {
  println("fire")
}

app.onRender() {
  x := left.x()
  y := left.y()
  throttle := app.controllerAxis(.One, .RightTrigger).value()
}
```

See [`samples/controller`](../../samples/controller).
