type InputButtonHandler = (): void
type InputButtonReader = (): bool

export class InputButton {
  private readState: InputButtonReader
  private down: bool = false
  private pressedHandlers: InputButtonHandler[] = []
  private releasedHandlers: InputButtonHandler[] = []
  private dependents: InputButton[] = []

  static source(readState: InputButtonReader): InputButton {
    return InputButton {
      readState,
      down: readState.call(),
    }
  }

  static any(buttons: InputButton[]): InputButton {
    composite := InputButton.source((): bool => anyButtonPressed(buttons))
    for button of buttons {
      button.addDependent(composite)
    }
    return composite
  }

  pressed(): bool => down
  released(): bool => !down

  onPressed(handler: InputButtonHandler): InputButton {
    pressedHandlers.push(handler)
    return this
  }

  onReleased(handler: InputButtonHandler): InputButton {
    releasedHandlers.push(handler)
    return this
  }

  update(): void {
    updateFromReader()
    updateDependents()
  }

  private addDependent(button: InputButton): void {
    dependents.push(button)
  }

  private updateFromReader(): void {
    next := readState.call()
    if next == down {
      return
    }

    down = next
    if down {
      for handler of pressedHandlers {
        handler.call()
      }
      return
    }

    for handler of releasedHandlers {
      handler.call()
    }
  }

  private updateDependents(): void {
    for dependent of dependents {
      dependent.update()
    }
  }
}

function anyButtonPressed(buttons: InputButton[]): bool {
  for button of buttons {
    if button.pressed() {
      return true
    }
  }
  return false
}
