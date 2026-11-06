// 测试专用 FFI 底座：模拟慢原生调用，并记录分配/释放是否对称。
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <unistd.h>

typedef struct { uint32_t id; float usage, frequency; } Core;
typedef struct {
  float overall, total, used, percent, fps;
  int32_t battery;
  bool charging;
  uint64_t uptime;
  uint32_t count;
  Core cores[32];
  uint8_t package[256];
} Snapshot;
static _Atomic int allocations = 0, polls = 0;
uint8_t *anydeck_alloc(size_t size) { allocations++; return calloc(1, size); }
void anydeck_free(uint8_t *bytes, size_t size) { (void)size; allocations--; free(bytes); }
void anydeck_clear_performance_cache(const char *serial) { (void)serial; }
bool anydeck_poll_performance(const char *serial, Snapshot *snapshot) {
  polls++;
  if (!strcmp(serial, "slow")) usleep(250000);
  if (!strcmp(serial, "missing")) return false;
  memset(snapshot, 0, sizeof(*snapshot));
  snapshot->total = 8000; snapshot->used = 3000; snapshot->percent = 37.5;
  snapshot->battery = 90; snapshot->count = 1; snapshot->fps = 60;
  snapshot->cores[0].frequency = 1800;
  strcpy((char *)snapshot->package, "com.example.app");
  return true;
}
int test_allocations(void) { return allocations; }
int test_polls(void) { return polls; }
