/* AnyDeck 使用真实 vendor 注册入口与状态机，替换系统 DNS-SD 应答以复现竞态。 */
#include <assert.h>
#include <dns_sd.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static DNSServiceErrorType mock_register(DNSServiceRef *, DNSServiceFlags,
    uint32_t, const char *, const char *, const char *, const char *, uint16_t,
    uint16_t, const void *, DNSServiceRegisterReply, void *);
static void mock_deallocate(DNSServiceRef);
#define DNSServiceRegister mock_register
#define DNSServiceRefDeallocate mock_deallocate
#include "../../rust/device_bridge/vendor/uxplay/lib/dns_sd/dns_sd.c"
#include "../../rust/device_bridge/vendor/uxplay/lib/dnssd.c"
#include "../../rust/device_bridge/native/uxplay_publication.h"

struct _DNSServiceRef_t {
    char name[256];
    char type[32];
    DNSServiceRegisterReply callback;
    void *context;
    int alive;
};

static DNSServiceRef registrations[64];
static int registration_count;

static DNSServiceErrorType mock_register(DNSServiceRef *ref, DNSServiceFlags flags,
    uint32_t interface, const char *name, const char *type, const char *domain,
    const char *host, uint16_t port, uint16_t length, const void *txt,
    DNSServiceRegisterReply callback, void *context) {
    (void)interface; (void)domain; (void)host; (void)port; (void)length; (void)txt;
    assert(flags & kDNSServiceFlagsNoAutoRename);
    assert(registration_count < 64);
    *ref = calloc(1, sizeof(**ref));
    assert(*ref);
    snprintf((*ref)->name, sizeof((*ref)->name), "%s", name);
    snprintf((*ref)->type, sizeof((*ref)->type), "%s", type);
    (*ref)->callback = callback;
    (*ref)->context = context;
    (*ref)->alive = 1;
    registrations[registration_count++] = *ref;
    return 0; /* 注册成功尚不代表异步发布成功。 */
}

static void mock_deallocate(DNSServiceRef ref) { ref->alive = 0; }

static void reply(int index, int error, const char *override_name) {
    DNSServiceRef ref = registrations[index];
    assert(ref->alive);
    ref->callback(ref, 0, error, override_name ? override_name : ref->name,
        ref->type, "local.", ref->context);
}

static dnssd_t *receiver(anydeck_publication_t *publication, unsigned char last,
    const char *short_name, const char *long_name, const char *full_name) {
    const char mac[6] = { 2, 0, 0, 0, 0, last };
    int error = 0;
    const char *name = "AnyDeck-Meeting-AirPlay";
    dnssd_t *dnssd = dnssd_init(name, (int)strlen(name), mac, 6, 0, &error);
    assert(dnssd && !error);
    dnssd_set_pk(dnssd, "test-public-key");
    assert(!dnssd_set_fallback_names(dnssd, short_name, long_name, full_name));
    anydeck_publication_init(publication);
    publication->dnssd = dnssd;
    publication->port = 7000;
    dnssd_set_registration_callback(dnssd, anydeck_publication_registered, publication);
    anydeck_publication_register(publication);
    return dnssd;
}

static void expect_name(anydeck_publication_t *publication, const char *name) {
    unsigned char bytes[256] = {0};
    size_t length = anydeck_publication_copy_name(publication, bytes, sizeof(bytes) - 1);
    assert(length == strlen(name));
    assert(!strcmp((const char *)bytes, name));
}

int main(void) {
    anydeck_publication_t first = {0}, second = {0}, unexpected = {0};
    dnssd_t *one = receiver(&first, 1, "AnyDeck-Meeting-AABBCC-AirPlay",
        "AnyDeck-Meeting-AABBCC111111-AirPlay", "AnyDeck-Meeting-AABBCC11111100000000000000000000-AirPlay");
    dnssd_t *two = receiver(&second, 2, "AnyDeck-Meeting-AABBCC-AirPlay",
        "AnyDeck-Meeting-AABBCC222222-AirPlay", "AnyDeck-Meeting-AABBCC22222200000000000000000000-AirPlay");
    /* 两台先同时注册，再由系统异步报告冲突；不会依赖启动前扫描。 */
    expect_name(&first, "");
    expect_name(&second, "");
    reply(0, 0, NULL);
    reply(1, 0, NULL);
    expect_name(&first, "AnyDeck-Meeting-AirPlay");
    reply(2, 0, NULL);
    reply(3, kDNSServiceErr_NameConflict, NULL);
    expect_name(&second, "");
    const char *original = two->name;
    int txt_length = 0;
    const char *txt = dnssd_get_airplay_txt(two, &txt_length);
    assert(txt && txt_length > 0);
    char *txt_copy = malloc(txt_length);
    memcpy(txt_copy, txt, txt_length);
    anydeck_publication_process(&second);
    assert(registration_count == 6);
    assert(!registrations[2]->alive && !registrations[3]->alive);
    reply(4, 0, NULL);
    reply(5, 0, NULL);
    expect_name(&second, "AnyDeck-Meeting-AABBCC-AirPlay");

    /* 已经发布/建立媒体连接后晚到冲突，只切换记录与 /info 的名称。 */
    reply(5, kDNSServiceErr_NameConflict, NULL);
    anydeck_publication_process(&second);
    assert(second.dnssd == two && two->name == original);
    assert(!strcmp(original, "AnyDeck-Meeting-AirPlay"));
    reply(6, 0, NULL);
    reply(7, 0, NULL);
    expect_name(&second, "AnyDeck-Meeting-AABBCC222222-AirPlay");
    int current_length = 0;
    assert(dnssd_get_airplay_txt(two, &current_length) == txt);
    assert(current_length == txt_length && !memcmp(txt, txt_copy, txt_length));
    int name_length = 0;
    assert(!strcmp(dnssd_get_name(two, &name_length), "AnyDeck-Meeting-AABBCC222222-AirPlay"));
    expect_name(&first, "AnyDeck-Meeting-AirPlay");

    /* 12 位仍冲突则用完整稳定身份；最终冲突明确失败，禁止无限 (2)/(3)。 */
    reply(7, kDNSServiceErr_NameConflict, NULL);
    anydeck_publication_process(&second);
    reply(8, 0, NULL);
    reply(9, 0, NULL);
    expect_name(&second, "AnyDeck-Meeting-AABBCC22222200000000000000000000-AirPlay");
    reply(9, kDNSServiceErr_NameConflict, NULL);
    assert(atomic_load(&second.status) == 2);
    anydeck_publication_process(&second);
    assert(registration_count == 10);
    expect_name(&second, "");

    /* 兼容系统意外自动改名的回调，绝不把请求值当作手机实际列表值。 */
    dnssd_t *three = receiver(&unexpected, 3, "AnyDeck-Meeting-DD0011-AirPlay", NULL, NULL);
    reply(10, 0, NULL);
    reply(11, 0, "AnyDeck-Meeting-AirPlay (2)");
    expect_name(&unexpected, "");
    anydeck_publication_process(&unexpected);
    reply(12, 0, NULL);
    reply(13, 0, NULL);
    expect_name(&unexpected, "AnyDeck-Meeting-DD0011-AirPlay");

    dnssd_unregister_airplay(one); dnssd_unregister_raop(one); dnssd_destroy(one);
    dnssd_unregister_airplay(two); dnssd_unregister_raop(two); dnssd_destroy(two);
    dnssd_unregister_airplay(three); dnssd_unregister_raop(three); dnssd_destroy(three);
    pthread_mutex_destroy(&first.lock);
    pthread_mutex_destroy(&second.lock);
    pthread_mutex_destroy(&unexpected.lock);
    for (int i = 0; i < registration_count; i++) free(registrations[i]);
    free(txt_copy);
    puts("AnyDeck Bonjour registration regression passed");
    return 0;
}
