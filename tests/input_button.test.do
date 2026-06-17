import { Assert } from "std/assert"

import { InputButton } from "../index"

class TestInputSource {
  down: bool = false

  button(): InputButton {
    return InputButton.source((): bool => down)
  }
}

export function testInputButtonReflectsCurrentState(): void {
  source := TestInputSource {}
  button := source.button()

  Assert.isFalse(button.pressed())
  Assert.isTrue(button.released())

  source.down = true
  button.update()

  Assert.isTrue(button.pressed())
  Assert.isFalse(button.released())
}

export function testInputButtonPressedAndReleasedHandlersFireOnEdgesOnly(): void {
  source := TestInputSource {}
  button := source.button()
  let pressed = 0
  let released = 0

  button.onPressed((): void => {
    pressed += 1
  })
  button.onReleased((): void => {
    released += 1
  })

  button.update()
  Assert.equal(pressed, 0)
  Assert.equal(released, 0)

  source.down = true
  button.update()
  button.update()
  Assert.equal(pressed, 1)
  Assert.equal(released, 0)

  source.down = false
  button.update()
  button.update()
  Assert.equal(pressed, 1)
  Assert.equal(released, 1)
}

export function testCompositeInputButtonUsesOrState(): void {
  first := TestInputSource {}
  second := TestInputSource {}
  firstButton := first.button()
  secondButton := second.button()
  composite := InputButton.any([firstButton, secondButton])

  Assert.isFalse(composite.pressed())
  Assert.isTrue(composite.released())

  first.down = true
  firstButton.update()
  Assert.isTrue(composite.pressed())

  second.down = true
  secondButton.update()
  Assert.isTrue(composite.pressed())

  first.down = false
  firstButton.update()
  Assert.isTrue(composite.pressed())

  second.down = false
  secondButton.update()
  Assert.isFalse(composite.pressed())
  Assert.isTrue(composite.released())
}

export function testCompositeInputButtonHandlersFireOnlyForAggregateEdges(): void {
  first := TestInputSource {}
  second := TestInputSource {}
  firstButton := first.button()
  secondButton := second.button()
  composite := InputButton.any([firstButton, secondButton])
  let pressed = 0
  let released = 0

  composite.onPressed((): void => {
    pressed += 1
  })
  composite.onReleased((): void => {
    released += 1
  })

  first.down = true
  firstButton.update()
  Assert.equal(pressed, 1)
  Assert.equal(released, 0)

  second.down = true
  secondButton.update()
  Assert.equal(pressed, 1)
  Assert.equal(released, 0)

  first.down = false
  firstButton.update()
  Assert.equal(pressed, 1)
  Assert.equal(released, 0)

  second.down = false
  secondButton.update()
  Assert.equal(pressed, 1)
  Assert.equal(released, 1)
}
