export import class NativeSound from "native_sound.hpp" as doof_game::NativeSound {
  isolated static load(path: string): Result<NativeSound, string>
  isolated static fromMonoSamples(sampleRate: int, samples: double[]): Result<NativeSound, string>
  isolated duration(): double
  play(volume: double, pan: double): Result<void, string>
  isolated stop(): void
  isolated isPlaying(): bool
}
