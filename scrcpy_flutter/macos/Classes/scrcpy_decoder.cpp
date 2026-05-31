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

static uint32_t ReadUint32BE(const uint8_t* buf) {
    return (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3];
}

static uint64_t ReadUint64BE(const uint8_t* buf) {
    return ((uint64_t)ReadUint32BE(buf) << 32) | ReadUint32BE(buf + 4);
}

ScrcpyDecoder::ScrcpyDecoder(const std::string& host, int port, ScrcpyFrameCallback callback, void* opaque)
    : host_(host), port_(port), callback_(callback), opaque_(opaque) {
    packet_ = av_packet_alloc();
    frame_ = av_frame_alloc();
    std::cout << "[ScrcpyDecoder] Constructor called for " << host << ":" << port << std::endl;
}

ScrcpyDecoder::~ScrcpyDecoder() {
    std::cout << "[ScrcpyDecoder] Destructor called" << std::endl;
    Stop();
    Cleanup();
    if (packet_) av_packet_free(&packet_);
    if (frame_) av_frame_free(&frame_);
}

bool ScrcpyDecoder::Start() {
    if (running_) return false;
    std::cout << "[ScrcpyDecoder] Starting decoder thread..." << std::endl;
    running_ = true;
    thread_ = std::thread(&ScrcpyDecoder::DecodeLoop, this);
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
        if (control_socket_ != -1) {
            shutdown(control_socket_, SHUT_RDWR);
            close(control_socket_);
            control_socket_ = -1;
        }
    }

    if (thread_.joinable()) {
        thread_.join();
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

    std::cout << "[ScrcpyDecoder] Connecting to video socket on " << host_ << ":" << port_ << "..." << std::endl;
    int video_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (video_fd < 0) {
        std::cout << "[ScrcpyDecoder] Failed to create video socket. errno = " << errno << std::endl;
        return false;
    }

    if (connect(video_fd, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
        std::cout << "[ScrcpyDecoder] Failed to connect video socket. errno = " << errno << std::endl;
        close(video_fd);
        return false;
    }
    std::cout << "[ScrcpyDecoder] Video socket connected!" << std::endl;

    usleep(50000); // 50ms delay
    std::cout << "[ScrcpyDecoder] Connecting to control socket..." << std::endl;
    int control_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (control_fd < 0) {
        std::cout << "[ScrcpyDecoder] Failed to create control socket. errno = " << errno << std::endl;
        close(video_fd);
        return false;
    }

    if (connect(control_fd, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
        std::cout << "[ScrcpyDecoder] Failed to connect control socket. errno = " << errno << std::endl;
        close(video_fd);
        close(control_fd);
        return false;
    }
    std::cout << "[ScrcpyDecoder] Control socket connected!" << std::endl;

    {
        std::lock_guard<std::mutex> lock(socket_mutex_);
        video_socket_ = video_fd;
        control_socket_ = control_fd;
    }

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
