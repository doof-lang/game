#include "native_sound.hpp"

#import <AVFoundation/AVFoundation.h>
#import <TargetConditionals.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace doof_game {

namespace {

NSString* stringFromUtf8(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

std::string nsErrorMessage(NSError* error, const std::string& fallback) {
    if (error == nil || [error localizedDescription] == nil) {
        return fallback;
    }

    return std::string([[error localizedDescription] UTF8String]);
}

void appendU16(std::vector<uint8_t>& output, uint16_t value) {
    output.push_back(static_cast<uint8_t>(value & 0xff));
    output.push_back(static_cast<uint8_t>((value >> 8) & 0xff));
}

void appendU32(std::vector<uint8_t>& output, uint32_t value) {
    output.push_back(static_cast<uint8_t>(value & 0xff));
    output.push_back(static_cast<uint8_t>((value >> 8) & 0xff));
    output.push_back(static_cast<uint8_t>((value >> 16) & 0xff));
    output.push_back(static_cast<uint8_t>((value >> 24) & 0xff));
}

void appendAscii(std::vector<uint8_t>& output, const char* value) {
    output.insert(output.end(), value, value + std::strlen(value));
}

std::vector<uint8_t> encodeMonoWav(int32_t sampleRate, const std::vector<double>& samples) {
    const uint16_t channelCount = 1;
    const uint16_t bitsPerSample = 16;
    const uint16_t blockAlign = channelCount * bitsPerSample / 8;
    const uint32_t byteRate = static_cast<uint32_t>(sampleRate) * blockAlign;
    const uint32_t dataSize = static_cast<uint32_t>(samples.size() * blockAlign);

    std::vector<uint8_t> output;
    output.reserve(44 + dataSize);
    appendAscii(output, "RIFF");
    appendU32(output, 36 + dataSize);
    appendAscii(output, "WAVE");
    appendAscii(output, "fmt ");
    appendU32(output, 16);
    appendU16(output, 1);
    appendU16(output, channelCount);
    appendU32(output, static_cast<uint32_t>(sampleRate));
    appendU32(output, byteRate);
    appendU16(output, blockAlign);
    appendU16(output, bitsPerSample);
    appendAscii(output, "data");
    appendU32(output, dataSize);

    for (double sample : samples) {
        const double clamped = std::max(-1.0, std::min(1.0, std::isfinite(sample) ? sample : 0.0));
        const int16_t encoded = static_cast<int16_t>(std::round(clamped * 32767.0));
        appendU16(output, static_cast<uint16_t>(encoded));
    }

    return output;
}

#if TARGET_OS_IOS
void configureAudioSession() {
    AVAudioSession* session = [AVAudioSession sharedInstance];
    if (session == nil) {
        return;
    }

    [session setCategory:AVAudioSessionCategoryAmbient error:nil];
    [session setActive:YES error:nil];
}
#else
void configureAudioSession() {}
#endif

}  // namespace

struct NativeSound::Impl {
    NSData* data = nil;
    double duration = 0.0;
    std::vector<AVAudioPlayer*> players;
    std::mutex mutex;

    Impl(void* rawData, double duration)
        : data((__bridge NSData*)rawData),
          duration(duration) {
        [data retain];
    }

    ~Impl() {
        stop();
        [data release];
    }

    void pruneStopped() {
        auto it = players.begin();
        while (it != players.end()) {
            AVAudioPlayer* player = *it;
            if (player == nil || ![player isPlaying]) {
                [player release];
                it = players.erase(it);
            } else {
                ++it;
            }
        }
    }

    void stop() {
        std::lock_guard<std::mutex> lock(mutex);
        for (AVAudioPlayer* player : players) {
            [player stop];
            [player release];
        }
        players.clear();
    }
};

NativeSound::NativeSound(void* data, double duration)
    : impl_(std::make_shared<Impl>(data, duration)) {}

NativeSound::~NativeSound() = default;

doof::Result<std::shared_ptr<NativeSound>, std::string> NativeSound::load(const std::string& path) {
    NSString* nsPath = stringFromUtf8(path);
    if (nsPath == nil) {
        return doof::Result<std::shared_ptr<NativeSound>, std::string>::failure("Sound path is not valid UTF-8");
    }

    NSData* data = [NSData dataWithContentsOfFile:nsPath];
    if (data == nil || [data length] == 0) {
        return doof::Result<std::shared_ptr<NativeSound>, std::string>::failure("Failed to load sound: " + path);
    }

    NSError* error = nil;
    AVAudioPlayer* player = [[AVAudioPlayer alloc] initWithData:data error:&error];
    if (player == nil) {
        return doof::Result<std::shared_ptr<NativeSound>, std::string>::failure(
            "Failed to decode sound '" + path + "': " + nsErrorMessage(error, "unknown audio decode error")
        );
    }

    const double duration = [player duration];
    [player release];
    auto sound = std::shared_ptr<NativeSound>(new NativeSound((__bridge void*)data, duration));
    return doof::Result<std::shared_ptr<NativeSound>, std::string>::success(sound);
}

doof::Result<std::shared_ptr<NativeSound>, std::string> NativeSound::fromMonoSamples(
    int32_t sampleRate,
    const std::shared_ptr<std::vector<double>>& samples
) {
    if (sampleRate <= 0) {
        return doof::Result<std::shared_ptr<NativeSound>, std::string>::failure("Sound sample rate must be positive");
    }
    if (!samples || samples->empty()) {
        return doof::Result<std::shared_ptr<NativeSound>, std::string>::failure("Sound samples must not be empty");
    }
    if (samples->size() > (std::numeric_limits<uint32_t>::max() - 44) / 2) {
        return doof::Result<std::shared_ptr<NativeSound>, std::string>::failure("Sound sample buffer is too large");
    }

    std::vector<uint8_t> wav = encodeMonoWav(sampleRate, *samples);
    NSData* data = [NSData dataWithBytes:wav.data() length:wav.size()];
    if (data == nil) {
        return doof::Result<std::shared_ptr<NativeSound>, std::string>::failure("Failed to allocate sound data");
    }

    const double duration = static_cast<double>(samples->size()) / static_cast<double>(sampleRate);
    auto sound = std::shared_ptr<NativeSound>(new NativeSound((__bridge void*)data, duration));
    return doof::Result<std::shared_ptr<NativeSound>, std::string>::success(sound);
}

double NativeSound::duration() const {
    return impl_ ? impl_->duration : 0.0;
}

doof::Result<void, std::string> NativeSound::play(double volume, double pan) {
    if (!impl_ || impl_->data == nil) {
        return doof::Result<void, std::string>::failure("Sound is not loaded");
    }

    configureAudioSession();

    NSError* error = nil;
    AVAudioPlayer* player = [[AVAudioPlayer alloc] initWithData:impl_->data error:&error];
    if (player == nil) {
        return doof::Result<void, std::string>::failure(
            "Failed to create sound player: " + nsErrorMessage(error, "unknown audio player error")
        );
    }

    [player setVolume:static_cast<float>(std::max(0.0, std::min(1.0, volume)))];
    [player setPan:static_cast<float>(std::max(-1.0, std::min(1.0, pan)))];
    [player prepareToPlay];
    if (![player play]) {
        [player release];
        return doof::Result<void, std::string>::failure("Failed to start sound playback");
    }

    {
        std::lock_guard<std::mutex> lock(impl_->mutex);
        impl_->pruneStopped();
        impl_->players.push_back(player);
    }
    return doof::Result<void, std::string>::success();
}

void NativeSound::stop() {
    if (impl_) {
        impl_->stop();
    }
}

bool NativeSound::isPlaying() {
    if (!impl_) {
        return false;
    }

    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->pruneStopped();
    return !impl_->players.empty();
}

}  // namespace doof_game
