import { sqrt } from "std/math"

type InputAxisReader = (): double

export class InputAxis {
  private readValue: InputAxisReader

  static source(readValue: InputAxisReader): InputAxis {
    return InputAxis { readValue }
  }

  value(): double => readValue.call()

  withDeadzone(deadzone: double): InputAxis {
    reader := readValue
    return InputAxis.source((): double => applyAxisDeadzone(reader.call(), deadzone))
  }

  inverted(): InputAxis {
    reader := readValue
    return InputAxis.source((): double => 0.0 - reader.call())
  }

  clamped(min: double, max: double): InputAxis {
    reader := readValue
    return InputAxis.source((): double => clampDouble(reader.call(), min, max))
  }
}

export class InputStick {
  private readX: InputAxisReader
  private readY: InputAxisReader

  static source(readX: InputAxisReader, readY: InputAxisReader): InputStick {
    return InputStick { readX, readY }
  }

  x(): double => readX.call()
  y(): double => readY.call()
  length(): double => sqrt(x() * x() + y() * y())

  withDeadzone(deadzone: double): InputStick {
    xReader := readX
    yReader := readY
    return InputStick.source(
      (): double => deadzonedStickX(xReader.call(), yReader.call(), deadzone),
      (): double => deadzonedStickY(xReader.call(), yReader.call(), deadzone),
    )
  }

  invertedY(): InputStick {
    xReader := readX
    yReader := readY
    return InputStick.source(
      (): double => xReader.call(),
      (): double => 0.0 - yReader.call(),
    )
  }
}

function applyAxisDeadzone(value: double, deadzone: double): double {
  zone := clampDouble(deadzone, 0.0, 0.999999)
  magnitude := absoluteDouble(value)
  if magnitude <= zone {
    return 0.0
  }
  scaled := (magnitude - zone) / (1.0 - zone)
  if value < 0.0 {
    return 0.0 - scaled
  }
  return scaled
}

function deadzonedStickX(x: double, y: double, deadzone: double): double {
  length := sqrt(x * x + y * y)
  scale := deadzonedStickScale(length, deadzone)
  return x * scale
}

function deadzonedStickY(x: double, y: double, deadzone: double): double {
  length := sqrt(x * x + y * y)
  scale := deadzonedStickScale(length, deadzone)
  return y * scale
}

function deadzonedStickScale(length: double, deadzone: double): double {
  zone := clampDouble(deadzone, 0.0, 0.999999)
  if length <= zone || length <= 0.0 {
    return 0.0
  }
  clampedLength := clampDouble(length, 0.0, 1.0)
  return ((clampedLength - zone) / (1.0 - zone)) / length
}

function absoluteDouble(value: double): double {
  if value < 0.0 {
    return 0.0 - value
  }
  return value
}

function clampDouble(value: double, min: double, max: double): double {
  if value < min {
    return min
  }
  if value > max {
    return max
  }
  return value
}
