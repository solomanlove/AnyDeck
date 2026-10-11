#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <pthread.h>
#include <stdatomic.h>
#include <errno.h>
#include <sys/select.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>

/* AnyDeck 接入层：只借用回调数据，停止时先 join 再释放上下文。 */

#include "raop.h"
#include "dnssd.h"
#include "stream.h"
#include "logger.h"

typedef struct {
    raop_t *raop;
    dnssd_t *dnssd;
    unsigned short port;
    void *rust_context;
    void (*video_callback)(void *ctx, const uint8_t *data, int len, uint64_t ntp_time);
    void (*reset_callback)(void *ctx);
    void (*log_callback)(void *ctx, int level, const char *msg);
    pthread_t dnssd_thread;
    atomic_bool running;
    bool worker_started;
} anydeck_uxplay_handle_t;

/* AirPlay 只在可路由 LAN 上广播，避免 iPhone 通过 USB 169.254 链路建连后 UDP timing 断流。 */
static uint32_t find_lan_interface_index(void) {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return 0;
    uint32_t selected = 0;
    for (struct ifaddrs *entry = interfaces; entry; entry = entry->ifa_next) {
        if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET) continue;
        if (!(entry->ifa_flags & IFF_UP) || !(entry->ifa_flags & IFF_RUNNING) ||
            (entry->ifa_flags & IFF_LOOPBACK) || strncmp(entry->ifa_name, "utun", 4) == 0) continue;
        uint32_t address = ntohl(((struct sockaddr_in *)entry->ifa_addr)->sin_addr.s_addr);
        if ((address & 0xffff0000u) == 0xa9fe0000u || (address & 0xff000000u) == 0x7f000000u) continue;
        uint32_t index = if_nametoindex(entry->ifa_name);
        if (!index) continue;
        selected = index;
        if (strncmp(entry->ifa_name, "en", 2) == 0) break;
    }
    freeifaddrs(interfaces);
    return selected;
}

static void on_audio_process(void *cls, raop_ntp_t *ntp, audio_decode_struct *data) {
    (void)cls;
    (void)ntp;
    (void)data;
}

static double on_audio_set_client_volume(void *cls) {
    (void)cls;
    return 0.0;
}

static void on_audio_set_volume(void *cls, float volume) {
    (void)cls;
    (void)volume;
}

static void on_conn_feedback(void *cls) {
    (void)cls;
}

static void on_conn_init(void *cls) {
    (void)cls;
}

static void on_conn_destroy(void *cls) {
    (void)cls;
}

static void on_audio_flush(void *cls) {
    (void)cls;
}

static void on_video_flush(void *cls) {
    (void)cls;
}

static void on_video_pause(void *cls) {
    (void)cls;
}

static void on_video_resume(void *cls) {
    (void)cls;
}

static int on_video_set_codec(void *cls, video_codec_t codec) {
    (void)cls;
    return codec == VIDEO_CODEC_H264 ? 0 : -1; // 当前只提供 H.264 解码
}

static void on_audio_get_format(void *cls, unsigned char *ct, unsigned short *spf, bool *usingScreen, bool *isMedia, uint64_t *audioFormat) {
    (void)cls;
    (void)ct;
    (void)spf;
    (void)usingScreen;
    (void)isMedia;
    (void)audioFormat;
}

static void on_video_report_size(void *cls, float *width_source, float *height_source, float *width, float *height) {
    (void)cls;
    (void)width_source;
    (void)height_source;
    (void)width;
    (void)height;
}

static void on_audio_set_metadata(void *cls, const void *buffer, int buflen) {
    (void)cls;
    (void)buffer;
    (void)buflen;
}

static void on_audio_set_coverart(void *cls, const void *buffer, int buflen) {
    (void)cls;
    (void)buffer;
    (void)buflen;
}

static void on_audio_stop_coverart_rendering(void *cls) {
    (void)cls;
}

static void on_audio_remote_control_id(void *cls, const char *dacp_id, const char *active_remote_header) {
    (void)cls;
    (void)dacp_id;
    (void)active_remote_header;
}

static void on_audio_set_progress(void *cls, uint32_t *start, uint32_t *curr, uint32_t *end) {
    (void)cls;
    (void)start;
    (void)curr;
    (void)end;
}

static void on_mirror_video_running(void *cls, bool is_running) {
    anydeck_uxplay_handle_t *h = cls;
    if (!is_running && h->reset_callback) h->reset_callback(h->rust_context);
}

static void on_report_client_request(void *cls, char *deviceid, char *model, char *name, bool *admit) {
    (void)cls;
    (void)deviceid;
    (void)model;
    (void)name;
    if (admit) *admit = true;
}

static bool on_check_register(void *cls, const char *pk_str) {
    (void)cls;
    (void)pk_str;
    return true; // 允许连接
}

static const char *on_passwd(void *cls, int *len) {
    (void)cls;
    if (len) *len = 0;
    return NULL;
}

static void on_export_dacp(void *cls, const char *active_remote, const char *dacp_id) {
    (void)cls;
    (void)active_remote;
    (void)dacp_id;
}

static void on_video_process(void *cls, raop_ntp_t *ntp, video_decode_struct *data) {
    (void)ntp;
    anydeck_uxplay_handle_t *h = (anydeck_uxplay_handle_t *)cls;
    if (h && h->video_callback && data && data->data && data->data_len > 0 &&
        data->data_len <= 10 * 1024 * 1024 && !data->is_h265) {
        h->video_callback(h->rust_context, data->data, data->data_len, data->ntp_time_local / 1000); // ns → VideoToolbox µs
    }
}

static void on_video_reset(void *cls, reset_type_t reset_type) {
    (void)reset_type;
    anydeck_uxplay_handle_t *h = (anydeck_uxplay_handle_t *)cls;
    if (h && h->reset_callback) {
        h->reset_callback(h->rust_context);
    }
}

static void on_conn_reset(void *cls, int reason) {
    (void)reason;
    anydeck_uxplay_handle_t *h = (anydeck_uxplay_handle_t *)cls;
    if (h && h->reset_callback) {
        h->reset_callback(h->rust_context);
    }
}

static void on_raop_log(void *cls, int level, const char *msg) {
    anydeck_uxplay_handle_t *h = (anydeck_uxplay_handle_t *)cls;
    if (h && h->log_callback) {
        h->log_callback(h->rust_context, level, msg);
    }
}

static int parse_mac_bytes(const char *mac_str, uint8_t *out_mac) {
    unsigned int values[6];
    if (sscanf(mac_str, "%x:%x:%x:%x:%x:%x",
               &values[0], &values[1], &values[2],
               &values[3], &values[4], &values[5]) == 6) {
        for (int i = 0; i < 6; i++) {
            if (values[i] > 255) return -1;
            out_mac[i] = (uint8_t)values[i];
        }
        return 0;
    }
    return -1;
}

static void *dnssd_worker(void *arg) {
    anydeck_uxplay_handle_t *h = (anydeck_uxplay_handle_t *)arg;
    while (h && atomic_load(&h->running) && h->dnssd) {
        fd_set read_fds;
        FD_ZERO(&read_fds);
        int max_fd = -1;
        for (int i = 0; i < 2; i++) {
            int fd = dnssd_get_service_fd(h->dnssd, i);
            if (fd >= FD_SETSIZE) {
                on_raop_log(h, LOGGER_ERR, "Bonjour descriptor exceeds FD_SETSIZE");
                return NULL;
            }
            if (fd >= 0) {
                FD_SET(fd, &read_fds);
                if (fd > max_fd) max_fd = fd;
            }
        }
        if (max_fd >= 0) {
            struct timeval tv;
            tv.tv_sec = 0;
            tv.tv_usec = 200000; // 200ms
            int ret = select(max_fd + 1, &read_fds, NULL, NULL, &tv);
            if (ret < 0 && errno != EINTR) {
                on_raop_log(h, LOGGER_ERR, "Bonjour socket select failed");
                return NULL;
            }
            if (ret > 0) {
                for (int i = 0; i < 2; i++) {
                    int fd = dnssd_get_service_fd(h->dnssd, i);
                    if (fd >= 0 && FD_ISSET(fd, &read_fds)) {
                        if (dnssd_process_service(h->dnssd, i) != 0) {
                            on_raop_log(h, LOGGER_ERR, "Bonjour service processing failed");
                            return NULL;
                        }
                    }
                }
            }
        } else {
            usleep(200000);
        }
    }
    return NULL;
}

void anydeck_uxplay_stop(void *handle);

void *anydeck_uxplay_start(
    const char *name,
    const char *mac,
    const char *keyfile,
    unsigned short port,
    bool publish,
    void *context,
    void (*video)(void *ctx, const uint8_t *data, int len, uint64_t ntp_time),
    void (*reset)(void *ctx),
    void (*log_fn)(void *ctx, int level, const char *msg)
) {
    anydeck_uxplay_handle_t *h = (anydeck_uxplay_handle_t *)calloc(1, sizeof(anydeck_uxplay_handle_t));
    if (!h) return NULL;

    h->rust_context = context;
    h->video_callback = video;
    h->reset_callback = reset;
    h->log_callback = log_fn;
    atomic_init(&h->running, true);

    raop_callbacks_t cbs;
    memset(&cbs, 0, sizeof(cbs));
    cbs.cls = h;
    cbs.audio_process = on_audio_process;
    cbs.video_process = on_video_process;
    cbs.video_reset = on_video_reset;
    cbs.conn_reset = on_conn_reset;
    cbs.conn_feedback = on_conn_feedback;
    cbs.conn_init = on_conn_init;
    cbs.conn_destroy = on_conn_destroy;
    cbs.audio_flush = on_audio_flush;
    cbs.video_flush = on_video_flush;
    cbs.video_pause = on_video_pause;
    cbs.video_resume = on_video_resume;
    cbs.audio_set_client_volume = on_audio_set_client_volume;
    cbs.audio_set_volume = on_audio_set_volume;
    cbs.audio_get_format = on_audio_get_format;
    cbs.video_report_size = on_video_report_size;
    cbs.audio_set_metadata = on_audio_set_metadata;
    cbs.audio_set_coverart = on_audio_set_coverart;
    cbs.audio_stop_coverart_rendering = on_audio_stop_coverart_rendering;
    cbs.audio_remote_control_id = on_audio_remote_control_id;
    cbs.audio_set_progress = on_audio_set_progress;
    cbs.mirror_video_running = on_mirror_video_running;
    cbs.report_client_request = on_report_client_request;
    cbs.check_register = on_check_register;
    cbs.passwd = on_passwd;
    cbs.export_dacp = on_export_dacp;
    cbs.video_set_codec = on_video_set_codec;

    h->raop = raop_init(&cbs);
    if (!h->raop) {
        free(h);
        return NULL;
    }

    if (log_fn) {
        raop_set_log_callback(h->raop, on_raop_log, h);
        raop_set_log_level(h->raop, LOGGER_INFO);
    }

    if (raop_init2(h->raop, 1, mac, keyfile) != 0) {
        anydeck_uxplay_stop(h);
        return NULL;
    }

    raop_set_plist(h->raop, "width", 1920);
    raop_set_plist(h->raop, "height", 1080);
    raop_set_plist(h->raop, "refreshRate", 60);
    raop_set_plist(h->raop, "maxFPS", 60);

    // /info 会访问 DNS-SD 元数据，必须在开放监听前初始化（测试也一样）。
    uint8_t mac_bytes[6];
    int dnssd_err = 0;
    if (parse_mac_bytes(mac, mac_bytes) != 0) goto fail;
    h->dnssd = dnssd_init(name, (int)strlen(name), (const char *)mac_bytes, 6, 0, &dnssd_err);
    if (!h->dnssd || dnssd_err) goto fail;
    if (publish) {
        uint32_t interface_index = find_lan_interface_index();
        if (!interface_index) {
            on_raop_log(h, LOGGER_ERR, "No routable LAN interface available for AirPlay Bonjour");
            goto fail;
        }
        dnssd_set_interface_index(h->dnssd, interface_index);
    }
    dnssd_set_airplay_features(h->dnssd, 0, 0); // 不支持 HLS
    dnssd_set_airplay_features(h->dnssd, 4, 0);
    dnssd_set_airplay_features(h->dnssd, 42, 0); // 不支持 HEVC
    raop_set_dnssd(h->raop, h->dnssd);

    unsigned short chosen_port = port;
    if (raop_start_httpd(h->raop, &chosen_port) <= 0) {
        // 请求端口被占用时让系统分配空闲端口，随后广播实际值。
        chosen_port = 0;
        if (raop_start_httpd(h->raop, &chosen_port) <= 0) goto fail;
    }
    raop_set_port(h->raop, chosen_port);
    h->port = chosen_port;
    if (publish) {
        if (dnssd_register_raop(h->dnssd, chosen_port) != 0 ||
            dnssd_register_airplay(h->dnssd, chosen_port) != 0) goto fail;
        if (pthread_create(&h->dnssd_thread, NULL, dnssd_worker, h) != 0) goto fail;
        h->worker_started = true;
    }

    return (void *)h;
fail:
    on_raop_log(h, LOGGER_ERR, "AirPlay listener or Bonjour initialization failed");
    anydeck_uxplay_stop(h);
    return NULL;
}

void anydeck_uxplay_stop(void *handle) {
    if (!handle) return;
    anydeck_uxplay_handle_t *h = (anydeck_uxplay_handle_t *)handle;
    atomic_store(&h->running, false);
    if (h->worker_started) pthread_join(h->dnssd_thread, NULL);

    // HTTP /info 仍然借用 dnssd；所有协议线程退出后才销毁 DNS 元数据。
    if (h->raop) raop_destroy(h->raop);
    if (h->dnssd) {
        dnssd_unregister_airplay(h->dnssd);
        dnssd_unregister_raop(h->dnssd);
        dnssd_destroy(h->dnssd);
    }

    free(h);
}

unsigned short anydeck_uxplay_port(void *handle) {
    if (!handle) return 0;
    anydeck_uxplay_handle_t *h = (anydeck_uxplay_handle_t *)handle;
    return h->port;
}
