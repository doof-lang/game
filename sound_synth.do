import { TAU, clamp, floor, sin } from "std/math"

import { Sound, SoundSamples } from "./sound"
import { SfxrSoundConfig, SoundWave } from "./sound_synth_types"

class FilterResult {
  readonly sample: double
  readonly lowPassState: double
  readonly highPassState: double
}

function sampleCount(config: SfxrSoundConfig): int {
  seconds := config.attackTime + config.sustainTime + config.decayTime
  if config.sampleRate <= 0 || seconds <= 0.0 {
    panic("Sound synth requires a positive sampleRate and envelope duration")
  }
  return maxInt(1, int(seconds * double(config.sampleRate)))
}

function maxInt(a: int, b: int): int => if a > b then a else b

function unitNoise(index: int, seed: int): double {
  value := sin((double(index) + 1.0) * 12.9898 + double(seed) * 78.233) * 43758.5453123
  return floor(value) - value
}

function waveSample(wave: SoundWave, phase: double, duty: double, noise: double): double {
  return case wave {
    SoundWave.Square -> if phase < duty then 1.0 else -1.0,
    SoundWave.Saw -> 1.0 - phase * 2.0,
    SoundWave.Sine -> sin(phase * TAU),
    SoundWave.Noise -> noise * 2.0 + 1.0,
    SoundWave.Triangle -> if phase < 0.5 then phase * 4.0 - 1.0 else 3.0 - phase * 4.0,
  }
}

function envelope(config: SfxrSoundConfig, time: double): double {
  if time < config.attackTime {
    if config.attackTime <= 0.0 {
      return 1.0
    }
    return time / config.attackTime
  }

  sustainEnd := config.attackTime + config.sustainTime
  if time < sustainEnd {
    if config.sustainTime <= 0.0 {
      return 1.0
    }
    progress := (time - config.attackTime) / config.sustainTime
    return 1.0 + config.sustainPunch * (1.0 - progress)
  }

  if config.decayTime <= 0.0 {
    return 0.0
  }
  progress := (time - sustainEnd) / config.decayTime
  return clamp(1.0 - progress, 0.0, 1.0)
}

function applyFilter(
  sample: double,
  lowPassCutoff: double,
  highPassCutoff: double,
  lowPassState: double,
  previousLowPassState: double,
  highPassState: double,
): FilterResult {
  nextLowPass := lowPassState + (sample - lowPassState) * lowPassCutoff * lowPassCutoff
  nextHighPass := highPassState + nextLowPass - previousLowPassState
  filtered := if highPassCutoff > 0.0 then nextHighPass * highPassCutoff else nextLowPass
  return FilterResult {
    sample: filtered,
    lowPassState: nextLowPass,
    highPassState: nextHighPass,
  }
}

export function generateSoundSamples(config: SfxrSoundConfig): SoundSamples {
  count := sampleCount(config)
  samples: double[] := []
  sampleRate := double(config.sampleRate)
  let phase = 0.0
  let frequency = config.baseFrequency
  let frequencySlide = config.frequencySlide
  let duty = config.squareDuty
  let lowPassCutoff = clamp(config.lowPassCutoff, 0.0, 1.0)
  let highPassCutoff = clamp(config.highPassCutoff, 0.0, 1.0)
  let lowPassState = 0.0
  let highPassState = 0.0

  for index of 0..<count {
    time := double(index) / sampleRate
    vibrato := if config.vibratoDepth == 0.0 then 0.0 else sin(time * config.vibratoSpeed * TAU) * config.vibratoDepth
    frequency = clamp(frequency + frequencySlide / sampleRate, 20.0, sampleRate * 0.45)
    frequencySlide += config.frequencySlideSlide / sampleRate
    phase += (frequency + vibrato) / sampleRate
    while phase >= 1.0 {
      phase -= 1.0
    }

    duty = clamp(duty + config.squareDutySweep / sampleRate, 0.05, 0.95)
    lowPassCutoff = clamp(lowPassCutoff + config.lowPassSweep / sampleRate, 0.0, 1.0)
    highPassCutoff = clamp(highPassCutoff + config.highPassSweep / sampleRate, 0.0, 1.0)

    raw := waveSample(config.wave, phase, duty, unitNoise(index, config.seed))
    env := envelope(config, time)
    filtered := applyFilter(
      raw,
      lowPassCutoff,
      highPassCutoff,
      lowPassState,
      lowPassState,
      highPassState,
    )
    lowPassState = filtered.lowPassState
    highPassState = filtered.highPassState * (1.0 - highPassCutoff)
    samples.push(clamp(filtered.sample * env * config.volume, -1.0, 1.0))
  }

  return SoundSamples { sampleRate: config.sampleRate, samples }
}

export function synthSound(config: SfxrSoundConfig): Result<Sound, string> {
  return Sound.fromSamples(generateSoundSamples(config))
}

export function pickupSound(): Result<Sound, string> => synthSound(SfxrSoundConfig.pickup())

export function laserSound(): Result<Sound, string> => synthSound(SfxrSoundConfig.laser())

export function explosionSound(): Result<Sound, string> => synthSound(SfxrSoundConfig.explosion())

export function jumpSound(): Result<Sound, string> => synthSound(SfxrSoundConfig.jump())

export function hitSound(): Result<Sound, string> => synthSound(SfxrSoundConfig.hit())
