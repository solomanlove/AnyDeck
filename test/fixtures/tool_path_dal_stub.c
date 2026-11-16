// 路径覆盖回归专用 DAL：返回成功结果，确保测试不能依赖原生失败后再回退。
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static int native_calls = 0;

uint8_t *anydeck_alloc(size_t size) { return calloc(1, size); }
void anydeck_free(uint8_t *value, size_t size) { (void)size; free(value); }
void anydeck_free_string(char *value) { free(value); }

char *anydeck_batch_execute_shell(uint8_t platform, const char *devices,
                                const char *command, uint32_t concurrency) {
  (void)platform; (void)devices; (void)command; (void)concurrency;
  native_calls++;
  return strdup("[]");
}

char *anydeck_dal_execute_shell(uint8_t platform, const char *device,
                              const char *command) {
  (void)platform; (void)device; (void)command;
  native_calls++;
  return strdup("{\"success\":true,\"payload\":\"native-path-used\"}");
}

int test_native_calls(void) { return native_calls; }
