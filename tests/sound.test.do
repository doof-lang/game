import { Assert } from "std/assert"

import {
  SfxrSoundConfig,
  Sound,
  SoundSamples,
  SoundWave,
  generateSoundSamples,
} from "../index"

function assertSamplesBounded(samples: SoundSamples): none {
  Assert.isTrue(samples.samples.length > 0)
  for sample of samples.samples {
    Assert.isTrue(sample >= -1.0)
    Assert.isTrue(sample <= 1.0)
  }
}

export function testSoundSynthGeneratesExpectedSampleCount(): none {
  samples := generateSoundSamples(SfxrSoundConfig {
    wave: SoundWave.Sine,
    sampleRate: 1000,
    baseFrequency: 100.0,
    attackTime: 0.01,
    sustainTime: 0.02,
    decayTime: 0.03,
  })

  Assert.equal(samples.sampleRate, 1000)
  Assert.equal(samples.samples.length, 60)
  Assert.equal(samples.duration(), 0.06)
  assertSamplesBounded(samples)
}

export function testSoundSynthPresetsGenerateReusableSamples(): none {
  assertSamplesBounded(generateSoundSamples(SfxrSoundConfig.pickup()))
  assertSamplesBounded(generateSoundSamples(SfxrSoundConfig.laser()))
  assertSamplesBounded(generateSoundSamples(SfxrSoundConfig.explosion()))
  assertSamplesBounded(generateSoundSamples(SfxrSoundConfig.jump()))
  assertSamplesBounded(generateSoundSamples(SfxrSoundConfig.hit()))
}

export function testSoundSynthIsDeterministicForNoise(): none {
  config := SfxrSoundConfig {
    wave: SoundWave.Noise,
    seed: 123,
    sampleRate: 8000,
    sustainTime: 0.02,
    decayTime: 0.01,
  }

  first := generateSoundSamples(config)
  second := generateSoundSamples(config)

  Assert.equal(first.samples.length, second.samples.length)
  for index of 0..<first.samples.length {
    Assert.equal(first.samples[index], second.samples[index])
  }
}

export function testSoundCanBeCreatedFromSynthSamples(): none {
  samples := generateSoundSamples(SfxrSoundConfig {
    wave: SoundWave.Sine,
    sampleRate: 8000,
    baseFrequency: 440.0,
    sustainTime: 0.01,
    decayTime: 0.01,
  })

  sound := try! Sound.fromSamples(samples)
  Assert.equal(sound.duration(), samples.duration())
  Assert.isFalse(sound.isPlaying())
  sound.stop()
}

export function testSoundPreparationIsSilentAndIdempotent(): none {
  sound := try! Sound.fromSamples(SoundSamples { sampleRate: 8000, samples: [0.0, 0.0, 0.0, 0.0] })
  try! sound.prepare()
  try! sound.prepare()
  Assert.isFalse(sound.isPlaying())
  sound.stop()
  Assert.isFalse(sound.isPlaying())
  // Stopping releases playback resources; explicit preparation works again.
  try! sound.prepare()
  Assert.isFalse(sound.isPlaying())
  sound.stop()
}

class BackgroundSound {
  private let sound: Sound | none = none

  prepare(): Result<none, string> {
    try prepared := Sound.fromSamples(SoundSamples { sampleRate: 8000, samples: [0.0, 0.0, 0.0, 0.0] })
    try prepared.prepare()
    sound = prepared
    return Success {}
  }

  isPlaying(): bool => if sound == none then false else sound!.isPlaying()

  play(): Result<none, string> {
    prepared := sound else { return Failure("Sound was not prepared") }
    return prepared.play({ volume: 0.0 })
  }

  stop(): none { if sound != none { sound!.stop() } }
}

export function testSoundPreparationAndPlaybackCanRunOnWorker(): none {
  worker := Actor<BackgroundSound>()
  task := async worker.prepare()
  result := try! task.get()
  try! result
  Assert.isFalse(worker.isPlaying())
  playback := async worker.play()
  played := try! playback.get()
  try! played
  sound := retire worker
  sound.stop()
}
