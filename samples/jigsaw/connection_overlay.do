import {
  Color,
  GameApp,
  GameSurface,
  Point3,
  Rect,
  RenderPass,
  Transform,
  UiLabel,
  UiLayer,
  Vec3,
} from "std/game"

import {
  JigsawRuntime,
  ServerConnectionState,
} from "./client_runtime"

const OVERLAY_WIDTH = 520.0
const OVERLAY_HEIGHT = 124.0

export class JigsawConnectionOverlay {
  ui: UiLayer
  statusLabel: UiLabel

  configure(surface: GameSurface): void {
    x := (surface.width() - OVERLAY_WIDTH) * 0.5
    y := (surface.height() - OVERLAY_HEIGHT) * 0.5
    this.ui.setTransform(
      Transform
        .identity()
        .withPosition(Point3(x, y, 0.0))
        .withScale(Vec3.xyz(1.0, 1.0, 1.0))
    )
  }

  update(runtime: JigsawRuntime): void {
    if runtime.state == ServerConnectionState.Connecting {
      address := runtime.serverAddress else {
        this.statusLabel.setText("Connecting to jigsaw server...")
        return
      }
      this.statusLabel.setText("Connecting to jigsaw server\n${address}")
      return
    }
    if runtime.state == ServerConnectionState.Disconnected {
      message := runtime.lastError else {
        this.statusLabel.setText("Jigsaw server disconnected\nReconnecting...")
        return
      }
      this.statusLabel.setText("Jigsaw server disconnected\nReconnecting...")
    }
  }

  draw(pass: RenderPass): void {
    this.ui.draw(pass)
  }
}

export function createJigsawConnectionOverlay(app: GameApp): JigsawConnectionOverlay {
  ui := UiLayer(app)
  ui.addPanel(Rect(0.0, 0.0, OVERLAY_WIDTH, OVERLAY_HEIGHT), {
    background: Color(0.035, 0.040, 0.048, 0.92),
    border: Color(0.62, 0.70, 0.78, 0.95),
    borderWidth: 2.0,
  })
  statusLabel := ui.addLabel("", Rect(28.0, 24.0, OVERLAY_WIDTH - 56.0, OVERLAY_HEIGHT - 48.0), {
    textColor: Color(0.92, 0.96, 1.0, 1.0),
    paddingX: 0.0,
    paddingY: 0.0,
    lineSpacing: 5.0,
  })
  overlay := JigsawConnectionOverlay { ui, statusLabel }
  overlay.configure(app.surface)
  return overlay
}
