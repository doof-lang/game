#pragma once

#include "doof_runtime.hpp"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace doof_game {

class NativeSound {
public:
    static doof::Result<std::shared_ptr<NativeSound>, std::string> load(const std::string& path);
    static doof::Result<std::shared_ptr<NativeSound>, std::string> fromMonoSamples(
        int32_t sampleRate,
        const std::shared_ptr<std::vector<double>>& samples
    );

    ~NativeSound();

    double duration() const;
    doof::Result<void, std::string> prepare();
    doof::Result<void, std::string> play(double volume, double pan);
    doof::Result<void, std::string> playAsync(double volume, double pan);
    void stop();
    bool isPlaying();

private:
    NativeSound(void* data, double duration);
    doof::Result<void, std::string> playInternal(double volume, double pan, uint64_t generation, bool queued);

    struct Impl;
    std::shared_ptr<Impl> impl_;
};

}  // namespace doof_game
