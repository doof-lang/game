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

## Prepare An Interactive Effect

Call `sound.prepare()` during loading to preload a playback voice without
starting playback. Preparation is idempotent; `isPlaying()` remains false.
On macOS/iOS, completed voices are reused and simultaneous plays still overlap.
`stop()` releases playback resources; call `prepare()` again if needed.
The Windows WAV backend has no separate player to preload, so preparation is a
silent no-op there.

Activating an audio device can also cost time on the first actual `play()`.
For an effect that must respond immediately, a startup play with volume zero
can warm that path before accepting input:

```doof
try! pickup.prepare()
try! pickup.play({ volume: 0.0 })
```

This is real muted playback: unlike `prepare()`, it can briefly make
`isPlaying()` true. The later interactive play still uses its normal volume.

For UI-sensitive playback, `sound.playAsync(options)` queues native playback
and returns as soon as the request is accepted. On Apple hosts it uses a
per-sound serial dispatch queue with user-interactive priority, independent of
the Doof computation scheduler. Warmup and later clicks are FIFO:

```doof
try! pickup.playAsync({ volume: 0.0 }) // startup warmup on the audio queue
// In the input handler:
try! pickup.playAsync({ volume: 0.7 })
```

Success means queued, not completed playback; later native errors are logged.
`stop()` cancels pending queued requests as well as stopping active voices.
`isPlaying()` reports active voices, not pending requests. Windows uses a
background thread for each queued request; FIFO is only guaranteed on Apple
hosts.

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
