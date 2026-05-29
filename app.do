import {
  clearMainEventWakeHandler,
  drainMainEventLoop,
  setMainEventWakeHandler,
} from "std/event"

import {
  NativeGameApp,
  NativeGameEvent,
  NativeRenderFrame,
  NativeGameSurface,
  NativeInputState,
  requestGameAppRender,
  requestGameAppStop,
  requestGameAppWake,
} from "./native"

import { GameEvent } from "./event"
import { InputState } from "./input"
import { Renderer, Texture, createRenderer, loadTextureForSurface } from "./render"
import { GameSurface } from "./surface"

function defaultGameEventHandler(event: GameEvent): void {}

function defaultGameRenderHandler(renderer: Renderer): void {}

export class GameApp {
  readonly title: string
  private readonly native: NativeGameApp
  input: InputState
  surface: GameSurface
  private onEventHandler: (event: GameEvent): void
  private onRenderHandler: (renderer: Renderer): void

  static constructor(title: string): GameApp {
    native := NativeGameApp.create(title)
    return GameApp {
      title: title,
      native: native,
      input: InputState(native.input()),
      surface: GameSurface(native.surface()),
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

  requestRender(): void {
    requestGameAppRender()
  }

  fps(): double {
    return this.native.fps()
  }

  loadTexture(path: string): Result<Texture, string> {
    return loadTextureForSurface(this.surface, path)
  }

  stop(): void {
    requestGameAppStop()
  }

  run(): Result<void, string> {
    setMainEventWakeHandler((): void => requestGameAppWake())

    result := native.run(
      (event: NativeGameEvent, input: NativeInputState): void => {
        this.input = InputState(input)
        this.onEventHandler(GameEvent(event))
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
}

export function initGameApp(title: string): GameApp {
  return GameApp(title)
}
