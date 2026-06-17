import { Assert } from "std/assert"

import {
  SfxrSoundConfig,
  Sound,
  SoundSamples,
  SoundWave,
  generateSoundSamples,
} from "../index"

function assertSamplesBounded(samples: SoundSamples): void {
  Assert.isTrue(samples.samples.length > 0)
  for sample of samples.samples {
    Assert.isTrue(sample >= -1.0)
    Assert.isTrue(sample <= 1.0)
  }
}

export function testSoundSynthGeneratesExpectedSampleCount(): void {
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

export function testSoundSynthPresetsGenerateReusableSamples(): void {
  assertSamplesBounded(generateSoundSamples(SfxrSoundConfig.pickup()))
  assertSamplesBounded(generateSoundSamples(SfxrSoundConfig.laser()))
  assertSamplesBounded(generateSoundSamples(SfxrSoundConfig.explosion()))
  assertSamplesBounded(generateSoundSamples(SfxrSoundConfig.jump()))
  assertSamplesBounded(generateSoundSamples(SfxrSoundConfig.hit()))
}

export function testSoundSynthIsDeterministicForNoise(): void {
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

export function testSoundCanBeCreatedFromSynthSamples(): void {
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
