import {
  GameEventKind,
  Key,
  SfxrSoundConfig,
  SoundPlayOptions,
  initGameApp,
  synthSound,
} from "std/game"

function main(): int {
  app := initGameApp{ title: "Doof Game Sound" }

  pickup := synthSound(SfxrSoundConfig.pickup()) else error {
    println(error)
    return 1
  }
  laser := synthSound(SfxrSoundConfig.laser()) else error {
    println(error)
    return 1
  }
  explosion := synthSound(SfxrSoundConfig.explosion()) else error {
    println(error)
    return 1
  }
  jump := synthSound(SfxrSoundConfig.jump()) else error {
    println(error)
    return 1
  }
  hit := synthSound(SfxrSoundConfig.hit()) else error {
    println(error)
    return 1
  }

  println("Press 1 pickup, 2 laser, 3 explosion, 4 jump, or 5 hit. Escape quits.")

  app.key(Key.Digit1).onPressed() {
    pickup.play(SoundPlayOptions { volume: 0.7, pan: -0.7 }) else error { println(error) }
  }
  app.key(Key.Digit2).onPressed() {
    laser.play(SoundPlayOptions { volume: 0.55, pan: 0.7 }) else error { println(error) }
  }
  app.key(Key.Digit3).onPressed() {
    explosion.play(SoundPlayOptions { volume: 0.65 }) else error { println(error) }
  }
  app.key(Key.Digit4).onPressed() {
    jump.play(SoundPlayOptions { volume: 0.6, pan: -0.25 }) else error { println(error) }
  }
  app.key(Key.Digit5).onPressed() {
    hit.play(SoundPlayOptions { volume: 0.6, pan: 0.25 }) else error { println(error) }
  }
  app.key(Key.Escape).onPressed((): void => app.stop())

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    }
  })

  app.run() else error {
    println(error)
    return 1
  }
  return 0
}
