import { NativeInputState } from "./native"
import { keyCode } from "./keys"
import { mouseButtonCode } from "./mouse"
import { Key, MouseButton } from "./types"

export class InputState {
  private readonly native: NativeInputState

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
