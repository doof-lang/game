export import class NativeSound from "native_sound.hpp" as doof_game::NativeSound {
  static load(path: string): Result<NativeSound, string>
  static fromMonoSamples(sampleRate: int, samples: double[]): Result<NativeSound, string>
  duration(): double
  play(volume: double, pan: double): Result<void, string>
  stop(): void
  isPlaying(): bool
}
