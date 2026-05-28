import { NativeGameSurface } from "./native"

export class GameSurface {
  private readonly native: NativeGameSurface

  pixelWidth(): int => this.native.pixelWidth()
  pixelHeight(): int => this.native.pixelHeight()
  scale(): double => this.native.scale()

  metalDeviceHandle(): long => this.native.metalDeviceHandle()
  metalCommandQueueHandle(): long => this.native.metalCommandQueueHandle()
  metalLayerHandle(): long => this.native.metalLayerHandle()
}
