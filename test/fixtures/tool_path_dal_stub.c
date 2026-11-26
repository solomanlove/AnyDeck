// DAL 测试替身，支持路径覆盖、Isolate 响应性和 timeout 传递验证。
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static atomic_int native_calls;
static atomic_int hold_next;
static atomic_int blocked_call;
static atomic_uint_fast64_t shell_timeout;

static void sleep_micros(uint64_t micros) {
  struct timespec delay = {micros / 1000000, (micros % 1000000) * 1000};
  nanosleep(&delay, NULL);
}

static void enter_native(void) {
  native_calls++;
  if (!atomic_exchange(&hold_next, 0)) return;
  blocked_call = 1;
  // 若回归为主线程同步执行，测试仍会在有界时间内恢复并失败。
  for (int i = 0; i < 2000 && blocked_call; i++) sleep_micros(1000);
  blocked_call = 0;
}

uint8_t *anydeck_alloc(size_t size) { return calloc(1, size); }
void anydeck_free(uint8_t *value, size_t size) { (void)size; free(value); }
void anydeck_free_string(char *value) { free(value); }

char *anydeck_batch_execute_shell(uint8_t platform, const char *devices,
                                const char *command, uint32_t concurrency) {
  (void)platform; (void)devices; (void)command; (void)concurrency;
  enter_native();
  return strdup("[]");
}

char *anydeck_dal_execute_shell(uint8_t platform, const char *device,
                              const char *command) {
  (void)platform; (void)device; (void)command;
  enter_native();
  return strdup("{\"success\":true,\"payload\":\"native-path-used\"}");
}

#ifndef ANYDECK_LEGACY_DAL
char *anydeck_dal_execute_shell_with_timeout(uint8_t platform, const char *device,
                                           const char *command, uint64_t micros) {
  (void)platform; (void)device;
  shell_timeout = micros;
  enter_native();
  if (strcmp(command, "test-native-timeout") == 0) {
    sleep_micros(micros < 1000000 ? micros : 1000000);
    return strdup("{\"success\":false,\"payload\":\"fixture timeout\"}");
  }
  if (strcmp(command, "test-native-failure") == 0) {
    return strdup("{\"success\":false,\"payload\":\"fixture failure\"}");
  }
  return strdup("{\"success\":true,\"payload\":\"native-path-used\"}");
}
#endif

char *anydeck_harmony_list_devices(void) {
  enter_native();
  return strdup("[{\"serial\":\"harmony-fixture\",\"status\":\"Connected\"}]");
}

char *anydeck_ios_list_devices(void) {
  enter_native();
  return strdup("[{\"udid\":\"ios-fixture\",\"connection_type\":\"USB\"}]");
}

int test_native_calls(void) { return native_calls; }
void test_hold_next_call(void) { hold_next = 1; }
int test_is_native_blocked(void) { return blocked_call; }
void test_release_call(void) { blocked_call = 0; }
uint64_t test_shell_timeout(void) { return shell_timeout; }
