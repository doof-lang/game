import { SimpleMesh, SimpleMeshBuilder, drawSimpleMesh, drawTexturedSimpleMesh } from "./mesh"
import { BitmapFont, TextLayoutOptions, createTextMesh, measureText } from "./text"
import { Color, Mat4, Point, Point3, Rect, RenderPass, Texture } from "./render"
import { GameSurface } from "./surface"
import { UiButton, UiLabel, UiPanel } from "./ui_controls"

export function drawUiPanel(
  surface: GameSurface,
  pass: RenderPass,
  panel: UiPanel,
  model: Mat4,
): void {
  bounds := panel.bounds()
  fill := quadMesh(surface, bounds, panel.style.background, panel.style.z)
  drawSimpleMesh(pass, fill, model)

  borderWidth := panel.style.borderWidth
  if borderWidth <= 0.0 {
    return
  }

  border := panel.style.border
  z := panel.style.z + 0.005
  top := Rect(bounds.x, bounds.y, bounds.width, borderWidth)
  bottom := Rect(bounds.x, bounds.y + bounds.height - borderWidth, bounds.width, borderWidth)
  left := Rect(bounds.x, bounds.y, borderWidth, bounds.height)
  right := Rect(bounds.x + bounds.width - borderWidth, bounds.y, borderWidth, bounds.height)

  drawSimpleMesh(pass, quadMesh(surface, top, border, z), model)
  drawSimpleMesh(pass, quadMesh(surface, bottom, border, z), model)
  drawSimpleMesh(pass, quadMesh(surface, left, border, z), model)
  drawSimpleMesh(pass, quadMesh(surface, right, border, z), model)
}

export function drawUiLabel(
  surface: GameSurface,
  font: BitmapFont,
  pass: RenderPass,
  label: UiLabel,
  model: Mat4,
): void {
  if label.text == "" {
    return
  }

  bounds := label.bounds()
  options := TextLayoutOptions {
    position: Point(bounds.x + label.style.paddingX, bounds.y + label.style.paddingY),
    z: label.style.z,
    maxWidth: bounds.width - label.style.paddingX * 2.0,
    align: label.style.align,
    lineSpacing: label.style.lineSpacing,
    color: label.style.textColor,
  }
  drawUiText(surface, font, labelTexture(label), pass, label.text, options, model)
}

export function drawUiButton(
  surface: GameSurface,
  font: BitmapFont,
  pass: RenderPass,
  button: UiButton,
  model: Mat4,
): void {
  bounds := button.bounds()
  mesh := quadMesh(surface, bounds, buttonBackground(button), button.style.z)
  drawSimpleMesh(pass, mesh, model)

  if button.text == "" {
    return
  }

  textColor := if button.enabled then button.style.textColor else button.style.disabledTextColor
  textBounds := measureText(font, button.text)
  textY := bounds.y + (bounds.height - textBounds.height) * 0.5
  options := TextLayoutOptions {
    position: Point(bounds.x + button.style.paddingX, textY),
    z: button.style.z + 0.01,
    maxWidth: bounds.width - button.style.paddingX * 2.0,
    align: button.style.align,
    color: textColor,
  }
  drawUiText(surface, font, buttonTexture(button), pass, button.text, options, model)
}

function labelTexture(label: UiLabel): Texture {
  texture := label.style.fontTexture else {
    panic("UiLabel requires style.fontTexture when text is drawn")
  }
  return texture
}

function buttonTexture(button: UiButton): Texture {
  texture := button.style.fontTexture else {
    panic("UiButton requires style.fontTexture when text is drawn")
  }
  return texture
}

function drawUiText(
  surface: GameSurface,
  font: BitmapFont,
  fontTexture: Texture,
  pass: RenderPass,
  text: string,
  options: TextLayoutOptions,
  model: Mat4,
): void {
  mesh := createTextMesh(surface, font, text, options)
  drawTexturedSimpleMesh(pass, mesh, fontTexture, model)
}

function buttonBackground(button: UiButton): Color {
  if !button.enabled {
    return button.style.disabledBackground
  }
  if button.pressed && button.pressedInside {
    return button.style.pressedBackground
  }
  if button.hovered {
    return button.style.hoverBackground
  }
  return button.style.background
}

function quadMesh(surface: GameSurface, bounds: Rect, color: Color, z: double): SimpleMesh {
  return SimpleMeshBuilder
    .create()
    .quad{
      a: Point3(bounds.x, bounds.y, z),
      b: Point3(bounds.x + bounds.width, bounds.y, z),
      c: Point3(bounds.x + bounds.width, bounds.y + bounds.height, z),
      d: Point3(bounds.x, bounds.y + bounds.height, z),
      color,
    }
    .build(surface)
}
