import {
  Blend,
  Camera,
  Clear,
  Color,
  Depth,
  GameSurface,
  GameEventKind,
  Key,
  Point3,
  Rect,
  RenderPassDescriptor,
  Transform,
  UiButtonStyle,
  UiLayer,
  UiLabel,
  UiPanelStyle,
  UiStyle,
  Vec3,
  initGameApp,
} from "std/game"
import { join, resourcesDirectory } from "std/path"

const PANEL_WIDTH = 640.0
const PANEL_HEIGHT = 540.0

function transformedPanelScale(surface: GameSurface): double {
  screenWidth := surface.width()
  screenHeight := surface.height()
  let scale = (screenHeight * 0.5) / PANEL_HEIGHT
  widthScale := (screenWidth - 48.0) / PANEL_WIDTH
  if scale > widthScale {
    scale = widthScale
  }
  if scale < 0.25 {
    scale = 0.25
  }
  return scale
}

function positionSampleUi(
  surface: GameSurface,
  ui: UiLayer,
  body: UiLabel,
  clicks: int,
): void {
  screenWidth := surface.width()
  screenHeight := surface.height()
  scale := transformedPanelScale(surface)
  panelX := (screenWidth - PANEL_WIDTH * scale) * 0.5
  panelY := (screenHeight - PANEL_HEIGHT * scale) * 0.5

  ui.setTransform(
    Transform
      .identity()
      .withPosition(Point3(panelX, panelY, 0.0))
      .withScale(Vec3.xyz(scale, scale, 1.0))
  )
  updateSampleBody(surface, scale, body, clicks)
}

function updateSampleBody(surface: GameSurface, scale: double, body: UiLabel, clicks: int): void {
  body.setText(
    "The retained UI layer can read the render surface dimensions, then resize " +
    "and center this fixed local panel with one transform.\n\n" +
    "Surface: ${int(surface.width())} x ${int(surface.height())} logical\n" +
    "Local panel: ${int(PANEL_WIDTH)} x ${int(PANEL_HEIGHT)}\n" +
    "Transform scale: ${scale}\n" +
    "Clicks: ${clicks}",
  )
}

function main(): int {
  app := initGameApp{ title: "Doof Game UI" }

  resources := try! resourcesDirectory()

  font := app.loadBitmapFont(join([resources, "fonts/DejaVuSans.fnt"])) else error {
    println(error)
    return 1
  }

  ui := UiLayer(app)

  let clicks = 0
  ui.addPanel(Rect(0.0, 0.0, PANEL_WIDTH, PANEL_HEIGHT), {
    background: Color(0.050, 0.062, 0.075, 0.94),
    border: Color(0.58, 0.70, 0.82, 1.0),
    borderWidth: 2.0,
  })
  ui.addLabel("Retained UI", Rect(26.0, 22.0, 428.0, 42.0), {
    font,
    textColor: Color(0.95, 0.88, 0.38, 1.0),
    paddingX: 0.0,
    paddingY: 0.0,
  })
  body := ui.addLabel("", Rect(26.0, 74.0, 600.0, 170.0), {
    font,
    textColor: Color(0.82, 0.88, 0.94, 1.0),
    paddingX: 0.0,
    paddingY: 0.0,
    lineSpacing: 4.0,
  })

  buttonStyle := UiButtonStyle{
    font,
    background: Color(0.18, 0.25, 0.30, 1.0),
    hoverBackground: Color(0.24, 0.36, 0.42, 1.0),
    pressedBackground: Color(0.10, 0.18, 0.23, 1.0),
    textColor: Color.white,
  }
  ui.addButton("Click me", (26.0, 466.0, 190.0, 42.0), buttonStyle) {
    clicks += 1
    updateSampleBody(app.surface, transformedPanelScale(app.surface), body, clicks)
  }

  positionSampleUi(app.surface, ui, body, clicks)
  app.key(Key.Escape).onPressed() {
    app.stop()
  }

  app.onEvent() {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    } else if event.kind() == GameEventKind.Resized {
      positionSampleUi(app.surface, ui, body, clicks)
      app.requestRender()
    }
  }

  app.onRender() {
    renderer.pass({
        camera: Camera.screen(),
        clear: Clear.colorDepth(Color(0.012, 0.015, 0.019), 1.0),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      }) {
      ui.draw(pass)
    }
  }

  app.run() else error {
      println(error)
      return 1
  }
  return 0
}
