#include "native_sound.hpp"

#import <AVFoundation/AVFoundation.h>
#import <TargetConditionals.h>
#include <dispatch/dispatch.h>

#include <algorithm>
#include <atomic>
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
    // Retain one idle, decoded voice instead of rebuilding a player per click.
    // Active voices remain separate so overlapping effects still work.
    AVAudioPlayer* readyPlayer = nil;
    dispatch_queue_t playbackQueue;
    std::atomic<uint64_t> generation{0};
    std::mutex mutex;

    Impl(void* rawData, double duration)
        : data((__bridge NSData*)rawData),
          duration(duration) {
        [data retain];
        auto attributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        playbackQueue = dispatch_queue_create("doof.game.sound", attributes);
    }

    ~Impl() {
        stop();
        [data release];
        dispatch_release(playbackQueue);
    }

    void pruneStopped() {
        auto it = players.begin();
        while (it != players.end()) {
            AVAudioPlayer* player = *it;
            if (player == nil || ![player isPlaying]) {
                if (player != nil && readyPlayer == nil) {
                    readyPlayer = player;
                    [readyPlayer setCurrentTime:0.0];
                } else {
                    [player release];
                }
                it = players.erase(it);
            } else {
                ++it;
            }
        }
    }

    void stop() {
        std::lock_guard<std::mutex> lock(mutex);
        generation.fetch_add(1);
        for (AVAudioPlayer* player : players) {
            [player stop];
            [player release];
        }
        players.clear();
        [readyPlayer stop];
        [readyPlayer release];
        readyPlayer = nil;
    }
};

NativeSound::NativeSound(void* data, double duration)
    : impl_(std::make_shared<Impl>(data, duration)) {}

NativeSound::~NativeSound() = default;

doof::Result<std::shared_ptr<NativeSound>, std::string> NativeSound::load(const std::string& path) {
    NSString* nsPath = stringFromUtf8(path);
    if (nsPath == nil) {
        return doof::Failure<std::string>{"Sound path is not valid UTF-8"};
    }

    NSData* data = [NSData dataWithContentsOfFile:nsPath];
    if (data == nil || [data length] == 0) {
        return doof::Failure<std::string>{"Failed to load sound: " + path};
    }

    NSError* error = nil;
    AVAudioPlayer* player = [[AVAudioPlayer alloc] initWithData:data error:&error];
    if (player == nil) {
        return doof::Failure<std::string>{"Failed to decode sound '" + path + "': " + nsErrorMessage(error, "unknown audio decode error")};
    }

    const double duration = [player duration];
    [player release];
    auto sound = std::shared_ptr<NativeSound>(new NativeSound((__bridge void*)data, duration));
    return doof::Success<std::shared_ptr<NativeSound>>{sound};
}

doof::Result<std::shared_ptr<NativeSound>, std::string> NativeSound::fromMonoSamples(
    int32_t sampleRate,
    const std::shared_ptr<std::vector<double>>& samples
) {
    if (sampleRate <= 0) {
        return doof::Failure<std::string>{"Sound sample rate must be positive"};
    }
    if (!samples || samples->empty()) {
        return doof::Failure<std::string>{"Sound samples must not be empty"};
    }
    if (samples->size() > (std::numeric_limits<uint32_t>::max() - 44) / 2) {
        return doof::Failure<std::string>{"Sound sample buffer is too large"};
    }

    std::vector<uint8_t> wav = encodeMonoWav(sampleRate, *samples);
    NSData* data = [NSData dataWithBytes:wav.data() length:wav.size()];
    if (data == nil) {
        return doof::Failure<std::string>{"Failed to allocate sound data"};
    }

    const double duration = static_cast<double>(samples->size()) / static_cast<double>(sampleRate);
    auto sound = std::shared_ptr<NativeSound>(new NativeSound((__bridge void*)data, duration));
    return doof::Success<std::shared_ptr<NativeSound>>{sound};
}

double NativeSound::duration() const {
    return impl_ ? impl_->duration : 0.0;
}

doof::Result<void, std::string> NativeSound::prepare() {
    if (!impl_ || impl_->data == nil) {
        return doof::Failure<std::string>{"Sound is not loaded"};
    }
    configureAudioSession();
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->pruneStopped();
    if (impl_->readyPlayer != nil) {
        return doof::Success<void>{};
    }
    NSError* error = nil;
    AVAudioPlayer* player = [[AVAudioPlayer alloc] initWithData:impl_->data error:&error];
    if (player == nil) {
        return doof::Failure<std::string>{"Failed to create sound player: " + nsErrorMessage(error, "unknown audio player error")};
    }
    if (![player prepareToPlay]) {
        [player release];
        return doof::Failure<std::string>{"Failed to prepare sound playback"};
    }
    impl_->readyPlayer = player;
    return doof::Success<void>{};
}

doof::Result<void, std::string> NativeSound::play(double volume, double pan) {
    return playInternal(volume, pan, 0, false);
}

doof::Result<void, std::string> NativeSound::playAsync(double volume, double pan) {
    if (!impl_ || impl_->data == nil) {
        return doof::Failure<std::string>{"Sound is not loaded"};
    }
    // The retained facade keeps sample data and the queue alive until execution.
    // FIFO warmup/playback is independent of the Doof computation scheduler.
    auto retained = std::shared_ptr<NativeSound>(new NativeSound(*this));
    const auto generation = impl_->generation.load();
    dispatch_async(impl_->playbackQueue, ^{
        @autoreleasepool {
            auto result = retained->playInternal(volume, pan, generation, true);
            if (auto* failure = std::get_if<doof::Failure<std::string>>(&result)) {
                NSLog(@"Doof sound playback failed: %s", failure->error.c_str());
            }
        }
    });
    return doof::Success<void>{};
}

doof::Result<void, std::string> NativeSound::playInternal(double volume, double pan, uint64_t generation, bool queued) {
    if (!impl_ || impl_->data == nil) {
        return doof::Failure<std::string>{"Sound is not loaded"};
    }

    configureAudioSession();
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (queued && generation != impl_->generation.load()) {
        return doof::Success<void>{};
    }
    impl_->pruneStopped();
    AVAudioPlayer* player = impl_->readyPlayer;
    impl_->readyPlayer = nil;
    if (player == nil) {
        // Allocate only when every existing voice is playing concurrently.
        NSError* error = nil;
        player = [[AVAudioPlayer alloc] initWithData:impl_->data error:&error];
        if (player == nil) {
            return doof::Failure<std::string>{"Failed to create sound player: " + nsErrorMessage(error, "unknown audio player error")};
        }
        if (![player prepareToPlay]) {
            [player release];
            return doof::Failure<std::string>{"Failed to prepare sound playback"};
        }
    }

    [player setVolume:static_cast<float>(std::max(0.0, std::min(1.0, volume)))];
    [player setPan:static_cast<float>(std::max(-1.0, std::min(1.0, pan)))];
    if (![player play]) {
        [player release];
        return doof::Failure<std::string>{"Failed to start sound playback"};
    }

    impl_->players.push_back(player);
    return doof::Success<void>{};
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
