# Sound

`std/game` supports reusable file-backed sounds and generated game effects.
Calling `play()` repeatedly can overlap voices, which is useful for one-shot
effects.

## Generated Sound Effects

```doof
pickup := synthSound(SfxrSoundConfig.pickup()) else error {
  println(error)
  return 1
}

app.key(Key.Digit1).onPressed() {
  pickup.play(SoundPlayOptions { volume: 0.7, pan: -0.4 }) else error {
    println(error)
  }
}
```

Presets include `pickup`, `laser`, `explosion`, `jump`, and `hit`.

See [`samples/sound`](../../samples/sound).

## File-Backed Audio

```doof
musicSting := app.loadSoundResource("audio/sting.wav") else error {
  println(error)
  return 1
}

musicSting.play(SoundPlayOptions { volume: 0.8 }) else error {
  println(error)
}
```

The native host can decode platform-supported formats such as WAV, MP3, AAC,
and CAF.

## Stop And Query A Sound

```doof
if musicSting.isPlaying() {
  musicSting.stop()
}

seconds := musicSting.duration()
```

`stop()` affects active voices for that `Sound` object. It does not stop other
sounds.

## Tune A Generated Effect

Start with a preset, then change fields before calling `synthSound`.

```doof
config := SfxrSoundConfig.laser()
config.attackTime = 0.0
config.sustainTime = 0.08
config.decayTime = 0.18
config.startFrequency = 0.55

laser := synthSound(config) else error {
  println(error)
  return 1
}
```
