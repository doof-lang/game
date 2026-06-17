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

  static fromSamples(samples: SoundSamples): Result<Sound, string> {
    try native := NativeSound.fromMonoSamples(samples.sampleRate, samples.samples)
    return Success(Sound { native })
  }

  duration(): double => native.duration()

  play(options: SoundPlayOptions = SoundPlayOptions {}): Result<void, string> {
    return native.play(options.volume, options.pan)
  }

  stop(): void {
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
