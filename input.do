import { NativeInputState } from "./native"
import { controllerAxisCode, controllerButtonCode, controllerSlotCode } from "./controller"
import { keyCode } from "./keys"
import { mouseButtonCode } from "./mouse"
import { ControllerAxis, ControllerButton, ControllerSlot, Key, MouseButton } from "./types"

export class ControllerQuery {
  private readonly native: NativeInputState

  connected(slot: ControllerSlot): bool => this.native.isControllerConnectedCode(controllerSlotCode(slot))
  name(slot: ControllerSlot): string => this.native.controllerNameCode(controllerSlotCode(slot))
}

export class InputState {
  private readonly native: NativeInputState

  controllers(): ControllerQuery => ControllerQuery(this.native)
  isControllerConnected(slot: ControllerSlot): bool => this.native.isControllerConnectedCode(controllerSlotCode(slot))
  isControllerButtonDown(slot: ControllerSlot, button: ControllerButton): bool {
    return this.native.isControllerButtonDownCode(controllerSlotCode(slot), controllerButtonCode(button))
  }
  controllerAxis(slot: ControllerSlot, axis: ControllerAxis): double {
    return this.native.controllerAxisCode(controllerSlotCode(slot), controllerAxisCode(axis))
  }
  isKeyDown(key: Key): bool => this.native.isKeyDownCode(keyCode(key))
  isMouseButtonDown(button: MouseButton): bool => this.native.isMouseButtonDownCode(mouseButtonCode(button))
  mouseX(): double => this.native.mouseX()
  mouseY(): double => this.native.mouseY()
  mouseDeltaX(): double => this.native.mouseDeltaX()
  mouseDeltaY(): double => this.native.mouseDeltaY()
  panDeltaX(): double => this.native.panDeltaX()
  panDeltaY(): double => this.native.panDeltaY()
  scrollDeltaX(): double => this.native.scrollDeltaX()
  scrollDeltaY(): double => this.native.scrollDeltaY()
  magnificationDelta(): double => this.native.magnificationDelta()
}
