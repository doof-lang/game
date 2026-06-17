export enum SoundWave {
  Square,
  Saw,
  Sine,
  Noise,
  Triangle,
}

export class SfxrSoundConfig {
  wave: SoundWave = SoundWave.Square
  seed: int = 1
  sampleRate: int = 44100
  volume: double = 0.5

  baseFrequency: double = 440.0
  frequencySlide: double = 0.0
  frequencySlideSlide: double = 0.0
  vibratoDepth: double = 0.0
  vibratoSpeed: double = 0.0

  squareDuty: double = 0.5
  squareDutySweep: double = 0.0

  attackTime: double = 0.0
  sustainTime: double = 0.12
  sustainPunch: double = 0.0
  decayTime: double = 0.18

  lowPassCutoff: double = 1.0
  lowPassSweep: double = 0.0
  highPassCutoff: double = 0.0
  highPassSweep: double = 0.0

  static pickup(): SfxrSoundConfig {
    return SfxrSoundConfig {
      wave: SoundWave.Square,
      baseFrequency: 780.0,
      frequencySlide: 720.0,
      squareDuty: 0.36,
      attackTime: 0.0,
      sustainTime: 0.05,
      sustainPunch: 0.35,
      decayTime: 0.12,
      volume: 0.45,
    }
  }

  static laser(): SfxrSoundConfig {
    return SfxrSoundConfig {
      wave: SoundWave.Saw,
      baseFrequency: 880.0,
      frequencySlide: -2100.0,
      attackTime: 0.0,
      sustainTime: 0.08,
      decayTime: 0.18,
      lowPassCutoff: 0.82,
      volume: 0.42,
    }
  }

  static explosion(): SfxrSoundConfig {
    return SfxrSoundConfig {
      wave: SoundWave.Noise,
      seed: 19,
      baseFrequency: 120.0,
      frequencySlide: -90.0,
      attackTime: 0.0,
      sustainTime: 0.16,
      sustainPunch: 0.55,
      decayTime: 0.38,
      lowPassCutoff: 0.62,
      lowPassSweep: -0.22,
      highPassCutoff: 0.02,
      volume: 0.65,
    }
  }

  static jump(): SfxrSoundConfig {
    return SfxrSoundConfig {
      wave: SoundWave.Triangle,
      baseFrequency: 360.0,
      frequencySlide: 640.0,
      attackTime: 0.0,
      sustainTime: 0.08,
      decayTime: 0.16,
      volume: 0.45,
    }
  }

  static hit(): SfxrSoundConfig {
    return SfxrSoundConfig {
      wave: SoundWave.Noise,
      seed: 7,
      baseFrequency: 260.0,
      frequencySlide: -160.0,
      attackTime: 0.0,
      sustainTime: 0.04,
      sustainPunch: 0.25,
      decayTime: 0.10,
      highPassCutoff: 0.08,
      volume: 0.5,
    }
  }
}
