#include "scrcpy_decoder.h"
#include <iostream>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <netdb.h>
#include <cstring>
#include <errno.h>
#include <cstdio>
#include <chrono>
#include <algorithm>

static uint32_t ReadUint32BE(const uint8_t* buf) {
    return (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3];
}

static uint64_t ReadUint64BE(const uint8_t* buf) {
    return ((uint64_t)ReadUint32BE(buf) << 32) | ReadUint32BE(buf + 4);
}

static void ScrcpyAudioQueueCallback(void* custom_data, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    ScrcpyDecoder* decoder = static_cast<ScrcpyDecoder*>(custom_data);
    decoder->ReleaseAudioBuffer(buffer);
}

ScrcpyDecoder::ScrcpyDecoder(const std::string& host, int port, bool audio_enabled, ScrcpyFrameCallback callback, void* opaque)
    : host_(host), port_(port), audio_enabled_(audio_enabled), callback_(callback), opaque_(opaque) {
    packet_ = av_packet_alloc();
    frame_ = av_frame_alloc();
    audio_packet_ = av_packet_alloc();
    audio_frame_ = av_frame_alloc();
    std::cout << "[ScrcpyDecoder] Constructor called for " << host << ":" << port << " (audio: " << audio_enabled_ << ")" << std::endl;
}

ScrcpyDecoder::~ScrcpyDecoder() {
    std::cout << "[ScrcpyDecoder] Destructor called" << std::endl;
    Stop();
    Cleanup();
    CleanupAudio();
    if (packet_) av_packet_free(&packet_);
    if (frame_) av_frame_free(&frame_);
    if (audio_packet_) av_packet_free(&audio_packet_);
    if (audio_frame_) av_frame_free(&audio_frame_);
}

bool ScrcpyDecoder::Start() {
    if (running_) return false;
    std::cout << "[ScrcpyDecoder] Starting decoder thread..." << std::endl;
    running_ = true;
    thread_ = std::thread(&ScrcpyDecoder::DecodeLoop, this);
    if (audio_enabled_) {
        std::cout << "[ScrcpyDecoder] Starting audio decoder thread..." << std::endl;
        audio_thread_ = std::thread(&ScrcpyDecoder::AudioLoop, this);
    }
    return true;
}

void ScrcpyDecoder::Stop() {
    std::cout << "[ScrcpyDecoder] Stopping..." << std::endl;
    running_ = false;
    
    {
        std::lock_guard<std::mutex> lock(socket_mutex_);
        if (video_socket_ != -1) {
            shutdown(video_socket_, SHUT_RDWR);
            close(video_socket_);
            video_socket_ = -1;
        }
        if (audio_socket_ != -1) {
            shutdown(audio_socket_, SHUT_RDWR);
            close(audio_socket_);
            audio_socket_ = -1;
        }
        if (control_socket_ != -1) {
            shutdown(control_socket_, SHUT_RDWR);
            close(control_socket_);
            control_socket_ = -1;
        }
    }

    // Wake up AudioQueue wait condition
    audio_buf_cond_.notify_all();

    if (thread_.joinable()) {
        thread_.join();
    }
    if (audio_thread_.joinable()) {
        audio_thread_.join();
    }
    std::cout << "[ScrcpyDecoder] Stopped" << std::endl;
}

bool ScrcpyDecoder::SendControl(const uint8_t* bytes, size_t len) {
    std::lock_guard<std::mutex> lock(socket_mutex_);
    if (control_socket_ == -1) return false;
    
    size_t sent = 0;
    while (sent < len) {
        ssize_t res = write(control_socket_, bytes + sent, len - sent);
        if (res <= 0) {
            return false;
        }
        sent += res;
    }
    return true;
}

bool ScrcpyDecoder::ReadExactly(int fd, uint8_t* buf, size_t len) {
    size_t total = 0;
    while (total < len) {
        if (!running_) return false;
        ssize_t res = read(fd, buf + total, len - total);
        if (res <= 0) {
            if (res < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
                // Wait briefly to prevent spinning CPU
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
                continue;
            }
            return false;
        }
        total += res;
    }
    return true;
}

bool ScrcpyDecoder::ConnectSockets() {
    struct sockaddr_in serv_addr;
    std::memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(port_);

    if (inet_pton(AF_INET, host_.c_str(), &serv_addr.sin_addr) <= 0) {
        std::cout << "[ScrcpyDecoder] Invalid host address: " << host_ << std::endl;
        return false;
    }

    struct timeval tv;
    tv.tv_sec = 1; // 1 second timeout
    tv.tv_usec = 0;

    std::cout << "[ScrcpyDecoder] Connecting to video socket on " << host_ << ":" << port_ << "..." << std::endl;
    int video_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (video_fd < 0) {
        std::cout << "[ScrcpyDecoder] Failed to create video socket. errno = " << errno << std::endl;
        return false;
    }
    setsockopt(video_fd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof(tv));
    setsockopt(video_fd, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof(tv));

    {
        std::lock_guard<std::mutex> lock(socket_mutex_);
        if (!running_) {
            close(video_fd);
            return false;
        }
        video_socket_ = video_fd;
    }

    if (connect(video_socket_, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
        std::cout << "[ScrcpyDecoder] Failed to connect video socket. errno = " << errno << std::endl;
        std::lock_guard<std::mutex> lock(socket_mutex_);
        if (video_socket_ != -1) {
            close(video_socket_);
            video_socket_ = -1;
        }
        return false;
    }
    std::cout << "[ScrcpyDecoder] Video socket connected!" << std::endl;

    if (audio_enabled_) {
        usleep(50000); // 50ms delay
        std::cout << "[ScrcpyDecoder] Connecting to audio socket..." << std::endl;
        int audio_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (audio_fd < 0) {
            std::cout << "[ScrcpyDecoder] Failed to create audio socket. errno = " << errno << std::endl;
            std::lock_guard<std::mutex> lock(socket_mutex_);
            if (video_socket_ != -1) { close(video_socket_); video_socket_ = -1; }
            return false;
        }
        setsockopt(audio_fd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof(tv));
        setsockopt(audio_fd, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof(tv));

        {
            std::lock_guard<std::mutex> lock(socket_mutex_);
            if (!running_) {
                if (video_socket_ != -1) { close(video_socket_); video_socket_ = -1; }
                close(audio_fd);
                return false;
            }
            audio_socket_ = audio_fd;
        }

        if (connect(audio_socket_, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
            std::cout << "[ScrcpyDecoder] Failed to connect audio socket. errno = " << errno << std::endl;
            std::lock_guard<std::mutex> lock(socket_mutex_);
            if (video_socket_ != -1) { close(video_socket_); video_socket_ = -1; }
            if (audio_socket_ != -1) { close(audio_socket_); audio_socket_ = -1; }
            return false;
        }
        std::cout << "[ScrcpyDecoder] Audio socket connected!" << std::endl;
    }

    usleep(50000); // 50ms delay
    std::cout << "[ScrcpyDecoder] Connecting to control socket..." << std::endl;
    int control_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (control_fd < 0) {
        std::cout << "[ScrcpyDecoder] Failed to create control socket. errno = " << errno << std::endl;
        std::lock_guard<std::mutex> lock(socket_mutex_);
        if (video_socket_ != -1) { close(video_socket_); video_socket_ = -1; }
        if (audio_socket_ != -1) { close(audio_socket_); audio_socket_ = -1; }
        return false;
    }
    setsockopt(control_fd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof(tv));
    setsockopt(control_fd, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof(tv));

    {
        std::lock_guard<std::mutex> lock(socket_mutex_);
        if (!running_) {
            if (video_socket_ != -1) { close(video_socket_); video_socket_ = -1; }
            if (audio_socket_ != -1) { close(audio_socket_); audio_socket_ = -1; }
            close(control_fd);
            return false;
        }
        control_socket_ = control_fd;
    }

    if (connect(control_socket_, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
        std::cout << "[ScrcpyDecoder] Failed to connect control socket. errno = " << errno << std::endl;
        std::lock_guard<std::mutex> lock(socket_mutex_);
        if (video_socket_ != -1) { close(video_socket_); video_socket_ = -1; }
        if (audio_socket_ != -1) { close(audio_socket_); audio_socket_ = -1; }
        if (control_socket_ != -1) { close(control_socket_); control_socket_ = -1; }
        return false;
    }
    std::cout << "[ScrcpyDecoder] Control socket connected!" << std::endl;

    return true;
}

void ScrcpyDecoder::DecodeLoop() {
    std::cout << "[ScrcpyDecoder] DecodeLoop started" << std::endl;
    
    bool connected = false;
    uint8_t dummy = 0;
    
    for (int retry = 0; retry < 30 && running_; ++retry) {
        std::cout << "[ScrcpyDecoder] Connection attempt #" << (retry + 1) << "..." << std::endl;
        if (!ConnectSockets()) {
            std::cout << "[ScrcpyDecoder] ConnectSockets failed, retrying in 200ms..." << std::endl;
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
            continue;
        }
        
        // Try reading the dummy byte
        if (!ReadExactly(video_socket_, &dummy, 1)) {
            std::cout << "[ScrcpyDecoder] Failed to read dummy byte, server probably not ready. Retrying in 200ms..." << std::endl;
            {
                std::lock_guard<std::mutex> lock(socket_mutex_);
                if (video_socket_ != -1) { close(video_socket_); video_socket_ = -1; }
                if (audio_socket_ != -1) { close(audio_socket_); audio_socket_ = -1; }
                if (control_socket_ != -1) { close(control_socket_); control_socket_ = -1; }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
            continue;
        }
        
        std::cout << "[ScrcpyDecoder] Dummy byte read: " << (int)dummy << std::endl;
        connected = true;
        break;
    }
    
    if (!connected) {
        std::cout << "[ScrcpyDecoder] Failed to establish valid connection to scrcpy server after multiple retries." << std::endl;
        running_ = false;
        return;
    }

    // Read metadata: Device Name (64 bytes), Codec ID (4 bytes), Unknown (4 bytes), Width (4 bytes), Height (4 bytes)
    uint8_t meta[80];
    std::cout << "[ScrcpyDecoder] Reading metadata (80 bytes)..." << std::endl;
    if (!ReadExactly(video_socket_, meta, 80)) {
        std::cout << "[ScrcpyDecoder] Failed to read metadata" << std::endl;
        Cleanup();
        return;
    }

    char device_name[65];
    std::memcpy(device_name, meta, 64);
    device_name[64] = '\0';
    std::cout << "[ScrcpyDecoder] Device Name: " << device_name << std::endl;

    uint32_t codec_id = ReadUint32BE(meta + 64);
    uint32_t unknown_field = ReadUint32BE(meta + 68);
    uint32_t width = ReadUint32BE(meta + 72);
    uint32_t height = ReadUint32BE(meta + 76);

    std::cout << "[ScrcpyDecoder] Metadata: codec_id = 0x" << std::hex << codec_id << std::dec
              << ", unknown = 0x" << std::hex << unknown_field << std::dec
              << ", width = " << width << ", height = " << height << std::endl;

    // Determine AVCodecID
    AVCodecID ffmpeg_codec_id = AV_CODEC_ID_H264; // Default to H.264
    if (codec_id == 0x68323635) { // "h265"
        ffmpeg_codec_id = AV_CODEC_ID_HEVC;
    }

    codec_ = avcodec_find_decoder(ffmpeg_codec_id);
    if (!codec_) {
        std::cout << "[ScrcpyDecoder] Failed to find FFmpeg decoder" << std::endl;
        Cleanup();
        return;
    }

    codec_ctx_ = avcodec_alloc_context3(codec_);
    if (!codec_ctx_) {
        std::cout << "[ScrcpyDecoder] Failed to alloc context" << std::endl;
        Cleanup();
        return;
    }

    if (avcodec_open2(codec_ctx_, codec_, nullptr) < 0) {
        std::cout << "[ScrcpyDecoder] Failed to open codec" << std::endl;
        Cleanup();
        return;
    }

    parser_ = av_parser_init(ffmpeg_codec_id);
    if (!parser_) {
        std::cout << "[ScrcpyDecoder] Failed to init parser" << std::endl;
        Cleanup();
        return;
    }

    std::cout << "[ScrcpyDecoder] FFmpeg contexts initialized. Starting stream reading..." << std::endl;

    // Buffer to read incoming video packet from socket
    std::vector<uint8_t> packet_data;
    int frame_count = 0;

    while (running_) {
        // Read 12-byte packet header: PTS (8 bytes), Size (4 bytes)
        uint8_t header[12];
        if (!ReadExactly(video_socket_, header, 12)) {
            std::cout << "[ScrcpyDecoder] Socket read error or closed during header read" << std::endl;
            break;
        }

        uint64_t pts = ReadUint64BE(header);
        uint32_t size = ReadUint32BE(header + 8);

        if (size == 0) continue;

        if (packet_data.size() < size) {
            packet_data.resize(size);
        }

        if (!ReadExactly(video_socket_, packet_data.data(), size)) {
            std::cout << "[ScrcpyDecoder] Socket read error during packet data read (size = " << size << ")" << std::endl;
            break;
        }

        // Parse and decode raw H264/H265 frame data
        uint8_t* parse_in = packet_data.data();
        int parse_in_len = size;

        while (parse_in_len > 0 && running_) {
            int parsed = av_parser_parse2(
                parser_, codec_ctx_,
                &packet_->data, &packet_->size,
                parse_in, parse_in_len,
                pts, AV_NOPTS_VALUE, 0
            );

            parse_in += parsed;
            parse_in_len -= parsed;

            if (packet_->size > 0) {
                int send_res = avcodec_send_packet(codec_ctx_, packet_);
                if (send_res < 0) {
                    std::cout << "[ScrcpyDecoder] avcodec_send_packet error: " << send_res << std::endl;
                    continue;
                }

                while (avcodec_receive_frame(codec_ctx_, frame_) >= 0) {
                    int w = frame_->width;
                    int h = frame_->height;

                    // Initialize or update SwsContext if dimension changes
                    sws_ctx_ = sws_getCachedContext(
                        sws_ctx_,
                        w, h, (AVPixelFormat)frame_->format,
                        w, h, AV_PIX_FMT_BGRA,
                        SWS_BILINEAR, nullptr, nullptr, nullptr
                    );

                    if (sws_ctx_) {
                        size_t rgba_size = w * h * 4;
                        if (rgba_buffer_.size() < rgba_size) {
                            rgba_buffer_.resize(rgba_size);
                        }

                        uint8_t* dest[4] = { rgba_buffer_.data(), nullptr, nullptr, nullptr };
                        int dest_linesize[4] = { w * 4, 0, 0, 0 };

                        sws_scale(
                            sws_ctx_,
                            frame_->data, frame_->linesize, 0, h,
                            dest, dest_linesize
                        );

                        frame_count++;
                        if (frame_count % 100 == 1) {
                            std::cout << "[ScrcpyDecoder] Decoded frame #" << frame_count << " (w = " << w << ", h = " << h << ")" << std::endl;
                        }

                        if (callback_) {
                            callback_(opaque_, rgba_buffer_.data(), w, h);
                        }
                    }
                }
            }
        }
    }

    std::cout << "[ScrcpyDecoder] DecodeLoop ending" << std::endl;
    Cleanup();
}

void ScrcpyDecoder::AudioLoop() {
    std::cout << "[ScrcpyDecoder] AudioLoop started" << std::endl;
    
    // Wait until sockets are connected
    while (running_ && audio_socket_ == -1) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    
    if (!running_) return;

    // 1. Read 4-byte codec ID
    uint8_t codec_header[4];
    if (!ReadExactly(audio_socket_, codec_header, 4)) {
        std::cout << "[ScrcpyDecoder] Failed to read audio codec ID" << std::endl;
        return;
    }
    uint32_t codec_id = ReadUint32BE(codec_header);
    std::cout << "[ScrcpyDecoder] Audio Codec ID: 0x" << std::hex << codec_id << std::dec << std::endl;

    // Determine Audio Codec
    AVCodecID ffmpeg_codec_id = AV_CODEC_ID_OPUS; // Default to Opus
    if (codec_id == 0x6f707573) { // "opus"
        ffmpeg_codec_id = AV_CODEC_ID_OPUS;
    } else if (codec_id == 0x61616300 || codec_id == 0x61616320) { // "aac"
        ffmpeg_codec_id = AV_CODEC_ID_AAC;
    } else if (codec_id == 0x72617700) { // "raw" (PCM)
        ffmpeg_codec_id = AV_CODEC_ID_NONE;
    }

    bool raw_pcm = (ffmpeg_codec_id == AV_CODEC_ID_NONE);
    
    if (!raw_pcm) {
        audio_codec_ = avcodec_find_decoder(ffmpeg_codec_id);
        if (!audio_codec_) {
            std::cout << "[ScrcpyDecoder] Failed to find FFmpeg audio decoder" << std::endl;
            return;
        }

        audio_codec_ctx_ = avcodec_alloc_context3(audio_codec_);
        if (!audio_codec_ctx_) {
            std::cout << "[ScrcpyDecoder] Failed to alloc audio context" << std::endl;
            return;
        }

        audio_codec_ctx_->sample_rate = 48000;
        audio_codec_ctx_->request_sample_fmt = AV_SAMPLE_FMT_FLTP;

        if (avcodec_open2(audio_codec_ctx_, audio_codec_, nullptr) < 0) {
            std::cout << "[ScrcpyDecoder] Failed to open audio codec" << std::endl;
            CleanupAudio();
            return;
        }
    }

    // 3. Initialize AudioQueue Basic Description
    AudioStreamBasicDescription asbd;
    std::memset(&asbd, 0, sizeof(asbd));
    asbd.mSampleRate = 48000.0;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    asbd.mBytesPerPacket = 4;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerFrame = 4;
    asbd.mChannelsPerFrame = 2;
    asbd.mBitsPerChannel = 16;

    // Create AudioQueue
    OSStatus status = AudioQueueNewOutput(&asbd, ScrcpyAudioQueueCallback, this, nullptr, nullptr, 0, &audio_queue_);
    if (status != noErr) {
        std::cout << "[ScrcpyDecoder] AudioQueueNewOutput failed. status = " << status << std::endl;
        CleanupAudio();
        return;
    }

    // Allocate Buffers
    for (int i = 0; i < 3; ++i) {
        AudioQueueBufferRef buf = nullptr;
        AudioQueueAllocateBuffer(audio_queue_, 8192, &buf);
        if (buf) {
            free_audio_buffers_.push_back(buf);
        }
    }

    // Start AudioQueue
    AudioQueueStart(audio_queue_, nullptr);
    std::cout << "[ScrcpyDecoder] macOS AudioQueue started successfully!" << std::endl;

    std::vector<uint8_t> packet_data;
    
    while (running_) {
        // Read 12-byte header
        uint8_t header[12];
        if (!ReadExactly(audio_socket_, header, 12)) {
            std::cout << "[ScrcpyDecoder] Audio socket read error or closed during header read" << std::endl;
            break;
        }

        uint64_t pts = ReadUint64BE(header);
        uint32_t size = ReadUint32BE(header + 8);

        if (size == 0) continue;

        if (packet_data.size() < size) {
            packet_data.resize(size);
        }

        if (!ReadExactly(audio_socket_, packet_data.data(), size)) {
            std::cout << "[ScrcpyDecoder] Audio socket read error during packet data read" << std::endl;
            break;
        }

        bool is_config = (pts & (1ULL << 63)) != 0 || (pts & (1ULL << 62)) != 0;
        uint64_t clean_pts = pts & ~(3ULL << 62);

        if (is_config) {
            std::cout << "[ScrcpyDecoder] Audio config packet received, size = " << size << std::endl;
            if (audio_codec_ctx_) {
                avcodec_free_context(&audio_codec_ctx_);
                audio_codec_ctx_ = avcodec_alloc_context3(audio_codec_);
                if (audio_codec_ctx_) {
                    audio_codec_ctx_->sample_rate = 48000;
                    audio_codec_ctx_->request_sample_fmt = AV_SAMPLE_FMT_FLTP;
                    audio_codec_ctx_->extradata = (uint8_t*)av_mallocz(size + AV_INPUT_BUFFER_PADDING_SIZE);
                    std::memcpy(audio_codec_ctx_->extradata, packet_data.data(), size);
                    audio_codec_ctx_->extradata_size = size;

                    if (avcodec_open2(audio_codec_ctx_, audio_codec_, nullptr) < 0) {
                        std::cout << "[ScrcpyDecoder] Failed to re-open audio codec with extradata" << std::endl;
                    }
                } else {
                    std::cout << "[ScrcpyDecoder] Failed to re-alloc audio context with extradata" << std::endl;
                }
            }
            continue;
        }

        if (raw_pcm) {
            // Raw PCM signed 16-bit LE, directly play it (assume stereo 48000Hz)
            AudioQueueBufferRef buf = nullptr;
            {
                std::unique_lock<std::mutex> lock(audio_buf_mutex_);
                audio_buf_cond_.wait(lock, [this]() { return !free_audio_buffers_.empty() || !running_; });
                if (!running_ || free_audio_buffers_.empty()) break;
                buf = free_audio_buffers_.back();
                free_audio_buffers_.pop_back();
            }

            if (buf) {
                size_t copy_size = std::min((size_t)size, (size_t)buf->mAudioDataBytesCapacity);
                std::memcpy(buf->mAudioData, packet_data.data(), copy_size);
                buf->mAudioDataByteSize = (UInt32)copy_size;
                AudioQueueEnqueueBuffer(audio_queue_, buf, 0, nullptr);
            }
        } else {
            // Send to FFmpeg decoder
            audio_packet_->data = packet_data.data();
            audio_packet_->size = size;
            audio_packet_->pts = clean_pts;

            int send_res = avcodec_send_packet(audio_codec_ctx_, audio_packet_);
            if (send_res < 0) continue;

            while (avcodec_receive_frame(audio_codec_ctx_, audio_frame_) >= 0) {
                // Initialize/Update SwrContext
                if (!swr_ctx_) {
                    AVChannelLayout out_ch_layout;
                    av_channel_layout_default(&out_ch_layout, 2); // stereo
                    
                    AVChannelLayout in_ch_layout;
                    if (audio_frame_->ch_layout.nb_channels > 0) {
                        av_channel_layout_copy(&in_ch_layout, &audio_frame_->ch_layout);
                    } else {
                        av_channel_layout_default(&in_ch_layout, 2);
                    }

                    int swr_init_res = swr_alloc_set_opts2(
                        &swr_ctx_,
                        &out_ch_layout, AV_SAMPLE_FMT_S16, 48000,
                        &in_ch_layout, (AVSampleFormat)audio_frame_->format, audio_frame_->sample_rate,
                        0, nullptr
                    );
                    
                    av_channel_layout_uninit(&out_ch_layout);
                    av_channel_layout_uninit(&in_ch_layout);

                    if (swr_init_res < 0 || swr_init(swr_ctx_) < 0) {
                        std::cout << "[ScrcpyDecoder] Failed to init SwrContext" << std::endl;
                        break;
                    }
                }

                if (swr_ctx_) {
                    int out_samples = swr_get_out_samples(swr_ctx_, audio_frame_->nb_samples);
                    std::vector<uint8_t> pcm_buf(out_samples * 4); // stereo S16 = 4 bytes per sample
                    uint8_t* out_data[1] = { pcm_buf.data() };
                    
                    int converted = swr_convert(
                        swr_ctx_,
                        out_data, out_samples,
                        (const uint8_t**)audio_frame_->data, audio_frame_->nb_samples
                    );

                    if (converted > 0) {
                        int pcm_len = converted * 4;
                        
                        // Enqueue to AudioQueue
                        AudioQueueBufferRef buf = nullptr;
                        {
                            std::unique_lock<std::mutex> lock(audio_buf_mutex_);
                            audio_buf_cond_.wait(lock, [this]() { return !free_audio_buffers_.empty() || !running_; });
                            if (!running_ || free_audio_buffers_.empty()) break;
                            buf = free_audio_buffers_.back();
                            free_audio_buffers_.pop_back();
                        }

                        if (buf) {
                            size_t copy_size = std::min((size_t)pcm_len, (size_t)buf->mAudioDataBytesCapacity);
                            std::memcpy(buf->mAudioData, pcm_buf.data(), copy_size);
                            buf->mAudioDataByteSize = (UInt32)copy_size;
                            AudioQueueEnqueueBuffer(audio_queue_, buf, 0, nullptr);
                        }
                    }
                }
            }
        }
    }

    std::cout << "[ScrcpyDecoder] AudioLoop ending" << std::endl;
    CleanupAudio();
}

void ScrcpyDecoder::ReleaseAudioBuffer(AudioQueueBufferRef buffer) {
    std::lock_guard<std::mutex> lock(audio_buf_mutex_);
    free_audio_buffers_.push_back(buffer);
    audio_buf_cond_.notify_one();
}

void ScrcpyDecoder::Cleanup() {
    if (sws_ctx_) {
        sws_freeContext(sws_ctx_);
        sws_ctx_ = nullptr;
    }
    if (parser_) {
        av_parser_close(parser_);
        parser_ = nullptr;
    }
    if (codec_ctx_) {
        avcodec_free_context(&codec_ctx_);
        codec_ctx_ = nullptr;
    }
    codec_ = nullptr;
}

void ScrcpyDecoder::CleanupAudio() {
    if (audio_queue_) {
        AudioQueueStop(audio_queue_, true);
        for (auto buf : free_audio_buffers_) {
            AudioQueueFreeBuffer(audio_queue_, buf);
        }
        free_audio_buffers_.clear();
        AudioQueueDispose(audio_queue_, true);
        audio_queue_ = nullptr;
    }
    if (swr_ctx_) {
        swr_free(&swr_ctx_);
        swr_ctx_ = nullptr;
    }
    if (audio_codec_ctx_) {
        avcodec_free_context(&audio_codec_ctx_);
        audio_codec_ctx_ = nullptr;
    }
    audio_codec_ = nullptr;
}
