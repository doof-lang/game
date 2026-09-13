export import class NativeSound from "native_sound.hpp" as doof_game::NativeSound {
  isolated static load(path: string): Result<NativeSound, string>
  isolated static fromMonoSamples(sampleRate: int, samples: double[]): Result<NativeSound, string>
  isolated duration(): double
  // Native implementations serialize per-sound state with their own mutex.
  isolated prepare(): Result<none, string>
  isolated play(volume: double, pan: double): Result<none, string>
  isolated playAsync(volume: double, pan: double): Result<none, string>
  isolated stop(): none
  isolated isPlaying(): bool
}
