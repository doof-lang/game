import { resourcePath } from "std/path"

import { NativeSound } from "./sound_native"

export class SoundPlayOptions {
  volume: double = 1.0
  pan: double = 0.0
}

export class Sound {
  private readonly native: NativeSound

  static load(path: string): Result<Sound, string> {
    try native := NativeSound.load(path)
    return Success(Sound { native })
  }

  static loadResource(path: string): Result<Sound, string> {
    try resolvedPath := resourcePath(path)
    return Sound.load(resolvedPath)
  }

  static fromSamples(samples: SoundSamples): Result<Sound, string> {
    try native := NativeSound.fromMonoSamples(samples.sampleRate, samples.samples)
    return Success(Sound { native })
  }

  duration(): double => native.duration()

  // Preload a playback voice before a latency-sensitive interaction. Repeated
  // preparation is safe; this does not start audible playback.
  prepare(): Result<none, string> => native.prepare()

  play(options: SoundPlayOptions = SoundPlayOptions {}): Result<none, string> {
    return native.play(options.volume, options.pan)
  }

  // Success means queued. Native playback errors are logged on the worker.
  // Apple hosts use a dedicated serial queue with user-interactive priority.
  playAsync(options: SoundPlayOptions = SoundPlayOptions {}): Result<none, string> {
    return native.playAsync(options.volume, options.pan)
  }

  stop(): none {
    native.stop()
  }

  isPlaying(): bool => native.isPlaying()
}

export class SoundSamples {
  sampleRate: int
  samples: double[]

  duration(): double {
    if sampleRate <= 0 {
      return 0.0
    }
    return double(samples.length) / double(sampleRate)
  }
}

export function loadSound(path: string): Result<Sound, string> {
  return Sound.load(path)
}

export function loadSoundResource(path: string): Result<Sound, string> {
  return Sound.loadResource(path)
}
