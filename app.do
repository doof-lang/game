import {
  clearMainEventWakeHandler,
  drainMainEventLoop,
  setMainEventWakeHandler,
} from "std/event"
import { Image, PixelBytes } from "std/image"

import {
  NativeGameApp,
  NativeGameEvent,
  NativeRenderFrame,
  NativeGameSurface,
  NativeInputState,
  requestGameAppRender,
  requestGameAppStop,
  requestGameAppWake,
  beginGameAppPanGesture,
  updateGameAppPanGesture,
  endGameAppPanGesture,
  cancelGameAppPanGesture,
  cancelGameAppPanInertia,
} from "./native"

import { GameEvent } from "./event"
import { controllerStickXAxis, controllerStickYAxis } from "./controller"
import { InputAxis, InputStick } from "./input_axis"
import { InputButton } from "./input_button"
import { InputState } from "./input"
import { loadIntrinsicBitmapFontForSurface } from "./intrinsic_font"
import {
  Point,
  Renderer,
  Texture,
  createRenderer,
  createTextureForSurface,
  createTextureFromPixelsForSurface,
  loadTextureForSurface,
} from "./render"
import { ScreenGesture, ScreenGestures } from "./screen_gestures"
import { ScreenPointer } from "./screen_pointer"
import { Sound, loadSound as loadSoundFile } from "./sound"
import { GameSurface } from "./surface"
import { BitmapFont, loadBitmapFontForSurface } from "./text"
import { ControllerAxis, ControllerButton, ControllerSlot, ControllerStick, GameEventKind, GameRenderMode, Key, MouseButton } from "./types"

function defaultGameEventHandler(event: GameEvent): void {}

function defaultGameRenderHandler(renderer: Renderer): void {}

export class GameApp {
  readonly title: string
  readonly renderMode: GameRenderMode
  private readonly native: NativeGameApp
  input: InputState
  surface: GameSurface
  private inputButtons: InputButton[] = []
  private screenGestures: ScreenGestures[] = []
  private screenPointers: ScreenPointer[] = []
  private onEventHandler: (event: GameEvent): void
  private onRenderHandler: (renderer: Renderer): void

  static constructor(title: string, renderMode: GameRenderMode = GameRenderMode.Continuous): GameApp {
    native := NativeGameApp.create(title)
    return GameApp {
      title: title,
      renderMode: renderMode,
      native: native,
      input: InputState(native.input()),
      surface: GameSurface(native.surface()),
      inputButtons: [],
      screenGestures: [],
      screenPointers: [],
      onEventHandler: defaultGameEventHandler,
      onRenderHandler: defaultGameRenderHandler,
    }
  }

  onEvent(handler: (event: GameEvent): void): GameApp {
    this.onEventHandler = handler
    return this
  }

  onRender(handler: (renderer: Renderer): void): GameApp {
    this.onRenderHandler = handler
    return this
  }

  key(key: Key): InputButton {
    button := InputButton.source((): bool => this.input.isKeyDown(key))
    inputButtons.push(button)
    return button
  }

  mouseButton(button: MouseButton): InputButton {
    inputButton := InputButton.source((): bool => this.input.isMouseButtonDown(button))
    inputButtons.push(inputButton)
    return inputButton
  }

  controllerButton(slot: ControllerSlot, button: ControllerButton): InputButton {
    inputButton := InputButton.source((): bool => this.input.isControllerButtonDown(slot, button))
    inputButtons.push(inputButton)
    return inputButton
  }

  controllerAxis(slot: ControllerSlot, axis: ControllerAxis): InputAxis {
    return InputAxis.source((): double => this.input.controllerAxis(slot, axis))
  }

  controllerStick(slot: ControllerSlot, stick: ControllerStick): InputStick {
    return InputStick.source(
      (): double => this.input.controllerAxis(slot, controllerStickXAxis(stick)),
      (): double => this.input.controllerAxis(slot, controllerStickYAxis(stick)),
    )
  }

  screenPointer(): ScreenPointer {
    pointer := ScreenPointer.fromInput(this.input)
    screenPointers.push(pointer)
    return pointer
  }

  gestures(): ScreenGestures {
    screenGesture := ScreenGestures {}
    screenGestures.push(screenGesture)
    return screenGesture
  }

  requestRender(): void {
    requestGameAppRender()
  }

  fps(): double {
    return this.native.fps()
  }

  loadTexture(path: string): Result<Texture, string> {
    return loadTextureForSurface(this.surface, path)
  }

  createTexture(image: Image): Result<Texture, string> {
    return createTextureForSurface(this.surface, image)
  }

  createTextureFromPixels(pixels: PixelBytes): Result<Texture, string> {
    return createTextureFromPixelsForSurface(this.surface, pixels)
  }

  loadBitmapFont(path: string): Result<BitmapFont, string> {
    return loadBitmapFontForSurface(this.surface, path)
  }

  loadIntrinsicFont(): Result<BitmapFont, string> {
    return loadIntrinsicBitmapFontForSurface(this.surface)
  }

  loadSound(path: string): Result<Sound, string> {
    return loadSoundFile(path)
  }

  stop(): void {
    requestGameAppStop()
  }

  beginPanGesture(x: double, y: double): void {
    beginGameAppPanGesture(x, y)
  }

  updatePanGesture(x: double, y: double): void {
    updateGameAppPanGesture(x, y)
  }

  endPanGesture(): void {
    endGameAppPanGesture()
  }

  cancelPanGesture(): void {
    cancelGameAppPanGesture()
  }

  cancelPanInertia(): void {
    cancelGameAppPanInertia()
  }

  run(): Result<void, string> {
    setMainEventWakeHandler((): void => requestGameAppWake())

    result := native.run(
      this.renderMode == GameRenderMode.Continuous,
      (event: NativeGameEvent, input: NativeInputState): void => {
        this.input = InputState(input)
        gameEvent := GameEvent(event)
        updateInputButtons()
        updateScreenPointers(gameEvent)
        updateScreenGestures(gameEvent)
        if !isBinaryInputEvent(gameEvent) {
          this.onEventHandler(gameEvent)
        }
      },
      (surface: NativeGameSurface, input: NativeInputState): void => {
        this.input = InputState(input)
        gameSurface := GameSurface(surface)
        this.surface = gameSurface
        renderer := createRenderer(gameSurface, NativeRenderFrame.create(surface))
        this.onRenderHandler(renderer)
        renderer.finish()
      },
      (): int => drainMainEventLoop(),
    )

    clearMainEventWakeHandler()
    return result
  }

  private updateInputButtons(): void {
    for button of inputButtons {
      button.update()
    }
  }

  private updateScreenPointers(event: GameEvent): void {
    kind := event.kind()
    if kind != GameEventKind.MouseDown && kind != GameEventKind.MouseUp && kind != GameEventKind.MouseMove {
      return
    }

    point := Point(event.x(), event.y())
    for pointer of screenPointers {
      if kind == GameEventKind.MouseDown && isPrimaryPointerButton(event.mouseButton()) {
        pointer.pressAt(point)
      } else if kind == GameEventKind.MouseUp && isPrimaryPointerButton(event.mouseButton()) {
        pointer.releaseAt(point)
      } else if kind == GameEventKind.MouseMove {
        pointer.moveTo(point)
      }
    }
  }

  private updateScreenGestures(event: GameEvent): void {
    kind := event.kind()
    if kind != GameEventKind.Pan
      && kind != GameEventKind.Scroll
      && kind != GameEventKind.Magnify
      && kind != GameEventKind.DoubleTap {
      return
    }

    for gestures of screenGestures {
      if kind == GameEventKind.Pan {
        gestures.emitPan(ScreenGesture.pan(Point(event.x(), event.y()), event.panDeltaX(), event.panDeltaY()))
      } else if kind == GameEventKind.Scroll {
        gestures.emitScroll(ScreenGesture.scroll(Point(event.x(), event.y()), event.scrollDeltaX(), event.scrollDeltaY()))
      } else if kind == GameEventKind.Magnify {
        gestures.emitMagnify(
          ScreenGesture.magnify(Point(event.x(), event.y()), event.panDeltaX(), event.panDeltaY(), event.magnificationDelta()),
        )
      } else if kind == GameEventKind.DoubleTap {
        gestures.emitDoubleTap(ScreenGesture.doubleTap(Point(event.x(), event.y())))
      }
    }
  }
}

export function initGameApp(title: string, renderMode: GameRenderMode = GameRenderMode.Continuous): GameApp {
  return GameApp(title, renderMode)
}

function isBinaryInputEvent(event: GameEvent): bool {
  kind := event.kind()
  return kind == GameEventKind.KeyDown
    || kind == GameEventKind.KeyUp
    || kind == GameEventKind.MouseDown
    || kind == GameEventKind.MouseUp
}

function isPrimaryPointerButton(button: MouseButton): bool {
  return button == MouseButton.Left || button == MouseButton.Other
}
