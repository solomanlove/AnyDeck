#ifndef ANYDECK_UXPLAY_PUBLICATION_H
#define ANYDECK_UXPLAY_PUBLICATION_H

#include <pthread.h>
#include <stdatomic.h>
#include <string.h>
#include <stdio.h>
#include <dns_sd.h>
#include "dnssd.h"

/* 名称发布与媒体连接分离；异步冲突只替换 Bonjour 记录，不关闭 listener。 */
typedef struct {
    dnssd_t *dnssd;
    unsigned short port;
    atomic_int status; /* 0: 探测/重试，1: 两种记录均确认，2: 发布失败。 */
    atomic_int retry;
    int ready_mask;
    pthread_mutex_t lock;
    char published_name[256];
    void (*error)(void *, const char *);
    void *context;
} anydeck_publication_t;

static void anydeck_publication_fail(anydeck_publication_t *p, const char *message) {
    atomic_store(&p->status, 2);
    if (p->error) p->error(p->context, message);
}

static void anydeck_publication_conflict(anydeck_publication_t *p) {
    atomic_store(&p->status, 0);
    if (!dnssd_can_retry_name(p->dnssd)) {
        anydeck_publication_fail(p, "Bonjour stable fallback name is already in use");
    } else {
        atomic_store(&p->retry, 1);
    }
}

static void anydeck_publication_registered(void *context, int error,
    const char *name, const char *regtype) {
    anydeck_publication_t *p = context;
    if (atomic_load(&p->status) == 2) return;
    if (error == kDNSServiceErr_NameConflict) {
        anydeck_publication_conflict(p);
        return;
    }
    if (error || !name || !regtype) {
        anydeck_publication_fail(p, "Bonjour registration callback failed");
        return;
    }
    int length = 0;
    const char *expected = dnssd_get_name(p->dnssd, &length);
    const int airplay = strcmp(regtype, "_airplay._tcp") == 0 ||
        strcmp(regtype, "_airplay._tcp.") == 0;
    const int raop = strcmp(regtype, "_raop._tcp") == 0 ||
        strcmp(regtype, "_raop._tcp.") == 0;
    const size_t prefix = p->dnssd->hw_addr_len * 2 + 1;
    const char *actual = raop && strlen(name) >= prefix ? name + prefix : name;
    /* 即使系统意外返回 (2)，也不能把请求名当作成功发布名。 */
    if ((!airplay && !raop) || strcmp(actual, expected) != 0) {
        anydeck_publication_conflict(p);
        return;
    }
    p->ready_mask |= airplay ? 1 : 2;
    if (p->ready_mask == 3 && !atomic_load(&p->retry)) {
        pthread_mutex_lock(&p->lock);
        snprintf(p->published_name, sizeof(p->published_name), "%s", expected);
        pthread_mutex_unlock(&p->lock);
        atomic_store(&p->status, 1);
    }
}

static void anydeck_publication_init(anydeck_publication_t *p) {
    atomic_init(&p->status, 0);
    atomic_init(&p->retry, 0);
    pthread_mutex_init(&p->lock, NULL);
}

static void anydeck_publication_register(anydeck_publication_t *p) {
    p->ready_mask = 0;
    atomic_store(&p->status, 0);
    int error = dnssd_register_raop(p->dnssd, p->port);
    if (!error) error = dnssd_register_airplay(p->dnssd, p->port);
    if (error == kDNSServiceErr_NameConflict) anydeck_publication_conflict(p);
    else if (error) anydeck_publication_fail(p, "Bonjour registration failed");
}

/* 必须在 DNSServiceProcessResult 返回后调用，不能在回调中释放当前 sdRef。 */
static void anydeck_publication_process(anydeck_publication_t *p) {
    if (atomic_load(&p->status) == 2) {
        dnssd_unregister_airplay(p->dnssd);
        dnssd_unregister_raop(p->dnssd);
        atomic_store(&p->retry, 0);
        return;
    }
    if (!atomic_exchange(&p->retry, 0)) return;
    dnssd_unregister_airplay(p->dnssd);
    dnssd_unregister_raop(p->dnssd);
    if (dnssd_use_fallback_name(p->dnssd) != 0) {
        anydeck_publication_fail(p, "Bonjour stable fallback unavailable");
        return;
    }
    anydeck_publication_register(p);
}

static size_t anydeck_publication_copy_name(anydeck_publication_t *p,
    unsigned char *out, size_t capacity) {
    if (!out || !capacity || atomic_load(&p->status) != 1) return 0;
    pthread_mutex_lock(&p->lock);
    size_t length = strlen(p->published_name);
    if (length > capacity) length = 0;
    if (length) memcpy(out, p->published_name, length);
    pthread_mutex_unlock(&p->lock);
    return length;
}

#endif
