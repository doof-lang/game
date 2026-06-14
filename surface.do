import { NativeGameSurface } from "./native"

export class GameSurface {
  private readonly native: NativeGameSurface

  width(): double => double(pixelWidth()) / effectiveScale()
  height(): double => double(pixelHeight()) / effectiveScale()
  pixelWidth(): int => this.native.pixelWidth()
  pixelHeight(): int => this.native.pixelHeight()
  scale(): double => this.native.scale()

  metalDeviceHandle(): long => this.native.metalDeviceHandle()
  metalCommandQueueHandle(): long => this.native.metalCommandQueueHandle()
  metalLayerHandle(): long => this.native.metalLayerHandle()

  private effectiveScale(): double {
    value := scale()
    if value <= 0.0 {
      return 1.0
    }
    return value
  }
}
