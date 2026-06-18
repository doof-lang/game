import { Assert } from "std/assert"
import { approxEqual } from "std/math"

import { InputAxis, InputStick } from "../index"

function assertApprox(actual: double, expected: double): void {
  Assert.isTrue(approxEqual(actual, expected))
}

class TestAxisSource {
  value: double = 0.0

  axis(): InputAxis {
    return InputAxis.source((): double => value)
  }
}

class TestStickSource {
  x: double = 0.0
  y: double = 0.0

  stick(): InputStick {
    return InputStick.source((): double => x, (): double => y)
  }
}

export function testInputAxisReadsCurrentValue(): void {
  source := TestAxisSource {}
  axis := source.axis()

  assertApprox(axis.value(), 0.0)
  source.value = 0.5
  assertApprox(axis.value(), 0.5)
}

export function testInputAxisDeadzoneScalesOutsideDeadzone(): void {
  source := TestAxisSource { value: 0.1 }
  axis := source.axis().withDeadzone(0.2)

  assertApprox(axis.value(), 0.0)
  source.value = 0.6
  assertApprox(axis.value(), 0.5)
  source.value = -0.6
  assertApprox(axis.value(), -0.5)
}

export function testInputAxisInvertsAndClamps(): void {
  source := TestAxisSource { value: 0.75 }

  assertApprox(source.axis().inverted().value(), -0.75)
  assertApprox(source.axis().clamped(-0.5, 0.5).value(), 0.5)
}

export function testInputStickReadsLengthAndInvertsY(): void {
  source := TestStickSource { x: 0.3, y: -0.4 }
  stick := source.stick()

  assertApprox(stick.x(), 0.3)
  assertApprox(stick.y(), -0.4)
  assertApprox(stick.length(), 0.5)
  assertApprox(stick.invertedY().y(), 0.4)
}

export function testInputStickDeadzoneUsesRadialLength(): void {
  source := TestStickSource { x: 0.3, y: 0.4 }
  stick := source.stick().withDeadzone(0.2)

  assertApprox(stick.length(), 0.375)

  source.x = 0.06
  source.y = 0.08
  assertApprox(stick.x(), 0.0)
  assertApprox(stick.y(), 0.0)
}
