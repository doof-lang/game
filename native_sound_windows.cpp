#include "native_sound.hpp"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <fstream>
#include <mutex>

namespace doof_game {
namespace {
void u16(std::vector<uint8_t>& out, uint16_t v) { out.push_back(uint8_t(v)); out.push_back(uint8_t(v >> 8)); }
void u32(std::vector<uint8_t>& out, uint32_t v) { u16(out, uint16_t(v)); u16(out, uint16_t(v >> 16)); }
void tag(std::vector<uint8_t>& out, const char* s) { out.insert(out.end(), s, s + 4); }
}

struct NativeSound::Impl {
    std::shared_ptr<std::vector<uint8_t>> bytes;
    double seconds = 0;
    std::chrono::steady_clock::time_point started{};
    bool playing = false;
    std::mutex mutex;
    Impl(void* data, double duration) : bytes(static_cast<std::vector<uint8_t>*>(data)), seconds(duration) {}
};

NativeSound::NativeSound(void* data, double duration) : impl_(std::make_shared<Impl>(data, duration)) {}
NativeSound::~NativeSound() = default;

doof::Result<std::shared_ptr<NativeSound>, std::string> NativeSound::load(const std::string& path) {
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (!input) return doof::Failure<std::string>{"Failed to open sound: " + path};
    auto size = input.tellg();
    if (size < 44) return doof::Failure<std::string>{"Sound is not a valid WAV file: " + path};
    input.seekg(0);
    auto* bytes = new std::vector<uint8_t>(static_cast<size_t>(size));
    if (!input.read(reinterpret_cast<char*>(bytes->data()), size)) { delete bytes; return doof::Failure<std::string>{"Failed to read sound: " + path}; }
    if (std::memcmp(bytes->data(), "RIFF", 4) || std::memcmp(bytes->data() + 8, "WAVE", 4)) { delete bytes; return doof::Failure<std::string>{"Windows sound loading currently requires WAV audio: " + path}; }
    uint32_t byteRate = 0, dataSize = 0; size_t offset = 12;
    while (offset + 8 <= bytes->size()) { uint32_t chunk = 0; std::memcpy(&chunk, bytes->data() + offset + 4, 4); if (!std::memcmp(bytes->data() + offset, "fmt ", 4) && chunk >= 12) std::memcpy(&byteRate, bytes->data() + offset + 16, 4); if (!std::memcmp(bytes->data() + offset, "data", 4)) { dataSize = chunk; break; } offset += 8 + chunk + (chunk & 1); }
    double duration = byteRate ? double(dataSize) / byteRate : 0;
    return doof::Success<std::shared_ptr<NativeSound>>{std::shared_ptr<NativeSound>(new NativeSound(bytes, duration))};
}

doof::Result<std::shared_ptr<NativeSound>, std::string> NativeSound::fromMonoSamples(int32_t rate, const std::shared_ptr<std::vector<double>>& samples) {
    if (rate <= 0 || !samples || samples->empty()) return doof::Failure<std::string>{"Sound samples and sample rate must be valid"};
    auto* bytes = new std::vector<uint8_t>(); bytes->reserve(44 + samples->size() * 2);
    tag(*bytes, "RIFF"); u32(*bytes, 36 + uint32_t(samples->size() * 2)); tag(*bytes, "WAVE"); tag(*bytes, "fmt "); u32(*bytes, 16); u16(*bytes, 1); u16(*bytes, 1); u32(*bytes, uint32_t(rate)); u32(*bytes, uint32_t(rate * 2)); u16(*bytes, 2); u16(*bytes, 16); tag(*bytes, "data"); u32(*bytes, uint32_t(samples->size() * 2));
    for (double value : *samples) { auto sample = int16_t(std::lround(std::clamp(value, -1.0, 1.0) * 32767.0)); u16(*bytes, uint16_t(sample)); }
    return doof::Success<std::shared_ptr<NativeSound>>{std::shared_ptr<NativeSound>(new NativeSound(bytes, double(samples->size()) / rate))};
}

double NativeSound::duration() const { return impl_->seconds; }
doof::Result<void, std::string> NativeSound::play(double, double) { std::lock_guard<std::mutex> lock(impl_->mutex); if (!PlaySoundA(reinterpret_cast<LPCSTR>(impl_->bytes->data()), nullptr, SND_ASYNC | SND_MEMORY | SND_NODEFAULT)) return doof::Failure<std::string>{"Failed to play WAV audio"}; impl_->started = std::chrono::steady_clock::now(); impl_->playing = true; return doof::Success<void>{}; }
void NativeSound::stop() { std::lock_guard<std::mutex> lock(impl_->mutex); PlaySoundW(nullptr, nullptr, 0); impl_->playing = false; }
bool NativeSound::isPlaying() { std::lock_guard<std::mutex> lock(impl_->mutex); if (impl_->playing && std::chrono::duration<double>(std::chrono::steady_clock::now() - impl_->started).count() >= impl_->seconds) impl_->playing = false; return impl_->playing; }

} // namespace doof_game
