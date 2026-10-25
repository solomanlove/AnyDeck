#include <arpa/inet.h>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <deque>
#include <mutex>
#include <netinet/in.h>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>
#include <vector>

#include <multimedia/player_framework/native_avbuffer.h>
#include <multimedia/player_framework/native_avscreen_capture.h>
#include <multimedia/player_framework/native_avscreen_capture_errors.h>

// 仅通过 HDC 反向端口连接桌面本地监听器；采集回调不做网络 I/O。
class AudioBridge {
public:
    int Start(uint16_t port, bool microphone)
    {
        Stop();
        socket_ = socket(AF_INET, SOCK_STREAM, 0);
        if (socket_ < 0) return -1;
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_port = htons(port);
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        if (connect(socket_, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0) {
            close(socket_);
            socket_ = -1;
            return -2;
        }
        microphone_ = microphone;
        capture_ = OH_AVScreenCapture_Create();
        if (capture_ == nullptr) {
            Stop();
            return -3;
        }
        OH_AVScreenCaptureConfig config{};
        config.captureMode = OH_CAPTURE_HOME_SCREEN;
        config.dataType = OH_ORIGINAL_STREAM;
        config.videoInfo.videoCapInfo.videoFrameWidth = 0;
        config.videoInfo.videoCapInfo.videoFrameHeight = 0;
        config.videoInfo.videoCapInfo.videoSource = OH_VIDEO_SOURCE_SURFACE_RGBA;
        config.audioInfo.innerCapInfo = {48000, 2, OH_ALL_PLAYBACK};
        config.audioInfo.micCapInfo = {48000, 2, OH_MIC};
        OH_AVScreenCapture_SetMicrophoneEnabled(capture_, microphone);
        OH_AVScreenCapture_SetDataCallback(capture_, OnBuffer, this);
        OH_AVScreenCapture_SetStateCallback(capture_, OnState, this);
        const int init = OH_AVScreenCapture_Init(capture_, config);
        if (init != AV_SCREEN_CAPTURE_ERR_OK) {
            Stop();
            return init;
        }
        {
            std::lock_guard<std::mutex> lock(mutex_);
            accepting_ = true;
        }
        writer_ = std::thread(&AudioBridge::WriteLoop, this);
        const int result = OH_AVScreenCapture_StartScreenCapture(capture_);
        if (result != AV_SCREEN_CAPTURE_ERR_OK) {
            Stop();
        }
        return result;
    }

    void Stop()
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            accepting_ = false;
            frames_.clear();
        }
        condition_.notify_all();
        if (capture_ != nullptr) {
            OH_AVScreenCapture_StopScreenCapture(capture_);
            OH_AVScreenCapture_Release(capture_);
            capture_ = nullptr;
        }
        if (socket_ >= 0) shutdown(socket_, SHUT_RDWR);
        if (writer_.joinable()) writer_.join();
        if (socket_ >= 0) close(socket_);
        socket_ = -1;
    }

    ~AudioBridge() { Stop(); }

private:
    static void OnBuffer(OH_AVScreenCapture *, OH_AVBuffer *buffer,
                         OH_AVScreenCaptureBufferType type, int64_t, void *userData)
    {
        auto *self = static_cast<AudioBridge *>(userData);
        if (self == nullptr || buffer == nullptr) return;
        const auto expected = self->microphone_
            ? OH_SCREEN_CAPTURE_BUFFERTYPE_AUDIO_MIC
            : OH_SCREEN_CAPTURE_BUFFERTYPE_AUDIO_INNER;
        if (type != expected) return; // 视频及另一条音频源一律不转发。
        OH_AVCodecBufferAttr attr{};
        if (OH_AVBuffer_GetBufferAttr(buffer, &attr) != AV_ERR_OK ||
            attr.size <= 0 || attr.offset < 0 ||
            attr.offset + attr.size > OH_AVBuffer_GetCapacity(buffer)) return;
        const uint8_t *data = OH_AVBuffer_GetAddr(buffer);
        if (data == nullptr) return;
        std::vector<uint8_t> frame(data + attr.offset, data + attr.offset + attr.size);
        {
            std::lock_guard<std::mutex> lock(self->mutex_);
            if (!self->accepting_ || self->frames_.size() >= 24) return;
            self->frames_.push_back(std::move(frame));
        }
        self->condition_.notify_one();
    }

    static void OnState(OH_AVScreenCapture *, OH_AVScreenCaptureStateCode state, void *userData)
    {
        auto *self = static_cast<AudioBridge *>(userData);
        if (self == nullptr) return;
        if (state == OH_SCREEN_CAPTURE_STATE_CANCELED ||
            state == OH_SCREEN_CAPTURE_STATE_STOPPED_BY_USER ||
            state == OH_SCREEN_CAPTURE_STATE_INTERRUPTED_BY_OTHER) {
            std::lock_guard<std::mutex> lock(self->mutex_);
            self->accepting_ = false;
            self->condition_.notify_all();
        }
    }

    bool SendAll(const uint8_t *data, size_t length)
    {
        while (length > 0) {
            const ssize_t sent = send(socket_, data, length, MSG_NOSIGNAL);
            if (sent <= 0) return false;
            data += sent;
            length -= static_cast<size_t>(sent);
        }
        return true;
    }

    void WriteLoop()
    {
        const uint8_t header[16] = {'A','D','B','A','U','D','1',0,
                                    0x80,0xbb,0,0,2,2,
                                    static_cast<uint8_t>(microphone_ ? 1 : 0),0};
        if (!SendAll(header, sizeof(header))) {
            std::lock_guard<std::mutex> lock(mutex_);
            accepting_ = false;
            return;
        }
        for (;;) {
            std::vector<uint8_t> frame;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                condition_.wait(lock, [&] { return !frames_.empty() || !accepting_; });
                if (frames_.empty() && !accepting_) break;
                frame = std::move(frames_.front());
                frames_.pop_front();
            }
            const uint32_t size = static_cast<uint32_t>(frame.size());
            const uint8_t length[4] = {
                static_cast<uint8_t>(size), static_cast<uint8_t>(size >> 8),
                static_cast<uint8_t>(size >> 16), static_cast<uint8_t>(size >> 24)};
            if (!SendAll(length, sizeof(length)) || !SendAll(frame.data(), frame.size())) {
                std::lock_guard<std::mutex> lock(mutex_);
                accepting_ = false;
                frames_.clear();
                break;
            }
        }
    }

    OH_AVScreenCapture *capture_ = nullptr;
    int socket_ = -1;
    bool microphone_ = false;
    bool accepting_ = false;
    std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<std::vector<uint8_t>> frames_;
    std::thread writer_;
};

static AudioBridge bridge;

#include <napi/native_api.h>

static napi_value Start(napi_env env, napi_callback_info info)
{
    size_t count = 2;
    napi_value args[2]{};
    napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    int32_t port = 0;
    bool microphone = false;
    if (count == 2) {
        napi_get_value_int32(env, args[0], &port);
        napi_get_value_bool(env, args[1], &microphone);
    }
    const int result = port > 0 && port < 65536
        ? bridge.Start(static_cast<uint16_t>(port), microphone) : -4;
    napi_value value;
    napi_create_int32(env, result, &value);
    return value;
}

static napi_value Stop(napi_env env, napi_callback_info)
{
    bridge.Stop();
    napi_value value;
    napi_get_undefined(env, &value);
    return value;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor methods[] = {
        {"startAudio", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopAudio", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, 2, methods);
    return exports;
}
EXTERN_C_END

static napi_module module = {1, 0, nullptr, Init, "entry", nullptr, {0}};
extern "C" __attribute__((constructor)) void RegisterEntryModule()
{
    napi_module_register(&module);
}
