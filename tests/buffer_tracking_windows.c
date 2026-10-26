#define wgpuBufferRelease fixture_native_release
#define wgpuBufferAddRef fixture_native_add_ref
#include "wgpu_stub_map.c"
#include <windows.h>
#include <stdio.h>

static volatile LONG reuse_address;
static volatile LONG native_releases;
static volatile LONG native_add_refs;

static void require(int condition, const char *message) {
  if (!condition) { fprintf(stderr, "buffer tracking: %s\n", message); exit(1); }
}

// WhyNot: including the real translation unit retains other native symbols in
// some linkers. They must fail closed here instead of linking a GPU library.
__declspec(noreturn) static void unexpected_native(void) {
  fputs("unexpected real native operation in isolated metadata test\n", stderr);
  exit(2);
}
void wgpuBufferDestroy(WGPUBuffer b) { (void)b; unexpected_native(); }
void wgpuBufferUnmap(WGPUBuffer b) { (void)b; unexpected_native(); }
void const *wgpuBufferGetConstMappedRange(WGPUBuffer b, size_t o, size_t n) {
  (void)b; (void)o; (void)n; unexpected_native();
}
void *wgpuBufferGetMappedRange(WGPUBuffer b, size_t o, size_t n) {
  (void)b; (void)o; (void)n; unexpected_native();
}
WGPUFuture wgpuBufferMapAsync(WGPUBuffer b, WGPUMapMode m, size_t o, size_t n,
                            WGPUBufferMapCallbackInfo c) {
  (void)b; (void)m; (void)o; (void)n; (void)c; unexpected_native();
}
WGPUCommandBuffer wgpuCommandEncoderFinish(WGPUCommandEncoder e,
                                           WGPUCommandBufferDescriptor const *d) {
  (void)e; (void)d; unexpected_native();
}
void wgpuComputePassEncoderSetBindGroup(WGPUComputePassEncoder e, uint32_t i,
                                       WGPUBindGroup g, size_t n, uint32_t const *o) {
  (void)e; (void)i; (void)g; (void)n; (void)o; unexpected_native();
}
WGPUBindGroup wgpuDeviceCreateBindGroup(WGPUDevice d, WGPUBindGroupDescriptor const *v) {
  (void)d; (void)v; unexpected_native();
}
WGPUBindGroupLayout wgpuDeviceCreateBindGroupLayout(WGPUDevice d,
                                                  WGPUBindGroupLayoutDescriptor const *v) {
  (void)d; (void)v; unexpected_native();
}
WGPUBuffer wgpuDeviceCreateBuffer(WGPUDevice d, WGPUBufferDescriptor const *v) {
  (void)d; (void)v; unexpected_native();
}
WGPUComputePipeline wgpuDeviceCreateComputePipeline(WGPUDevice d,
                                                   WGPUComputePipelineDescriptor const *v) {
  (void)d; (void)v; unexpected_native();
}
WGPUPipelineLayout wgpuDeviceCreatePipelineLayout(WGPUDevice d,
                                                 WGPUPipelineLayoutDescriptor const *v) {
  (void)d; (void)v; unexpected_native();
}
void wgpuInstanceProcessEvents(WGPUInstance i) { (void)i; unexpected_native(); }

// WhyNot: these handles belong only to the isolated metadata fixture. No
// synthetic handle may reach a real WGPU entry point.
void fixture_native_release(WGPUBuffer buffer) {
  InterlockedIncrement(&native_releases);
  if (InterlockedExchange(&reuse_address, 0))
    mbt_buffer_track_register_new(buffer, true);
}

void fixture_native_add_ref(WGPUBuffer buffer) {
  (void)buffer;
  InterlockedIncrement(&native_add_refs);
}

static void address_reuse(void) {
  static int identity;
  WGPUBuffer buffer = (WGPUBuffer)&identity;
  mbt_buffer_track_register_new(buffer, false);
  InterlockedExchange(&reuse_address, 1);
  mbt_wgpu_buffer_release_tracked(buffer);
  require(mbt_buffer_track_get_state(buffer) == WGPUBufferMapState_Mapped,
          "old release erased the newly registered address generation");
  mbt_wgpu_buffer_release_tracked(buffer);
  require(g_mbt_buffer_track_head == NULL, "new generation not retired");
}

typedef struct Participant {
  WGPUBuffer buffer;
  HANDLE ready;
  HANDLE resume;
  int shared;
} Participant;

static DWORD WINAPI registry_operations(void *context) {
  Participant *part = context;
  if (part->shared) {
    // The main owner retains its original reference across both AddRefs.
    mbt_wgpu_buffer_add_ref_tracked(part->buffer);
  } else {
    mbt_buffer_track_register_new(part->buffer, false);
    mbt_buffer_track_set_state(part->buffer, WGPUBufferMapState_Mapped);
    require(mbt_buffer_track_get_state(part->buffer) == WGPUBufferMapState_Mapped,
            "independent Buffer state changed");
  }
  require(SetEvent(part->ready), "ready event failed");
  require(WaitForSingleObject(part->resume, INFINITE) == WAIT_OBJECT_0,
          "resume event failed");
  mbt_wgpu_buffer_release_tracked(part->buffer);
  return 0;
}

static void parallel_owners(int shared) {
  static int identities[2];
  Participant parts[2] = {0};
  HANDLE workers[2] = {0}, ready[2] = {0};
  HANDLE resume = CreateEventW(NULL, TRUE, FALSE, NULL);
  require(resume != NULL, "create resume event failed");
  WGPUBuffer root = (WGPUBuffer)&identities[0];
  if (shared) mbt_buffer_track_register_new(root, false);
  for (int index = 0; index < 2; ++index) {
    ready[index] = CreateEventW(NULL, TRUE, FALSE, NULL);
    require(ready[index] != NULL, "create ready event failed");
    parts[index] = (Participant){shared ? root : (WGPUBuffer)&identities[index],
                                ready[index], resume, shared};
    workers[index] = CreateThread(NULL, 0, registry_operations, &parts[index], 0, NULL);
    require(workers[index] != NULL, "create participant failed");
  }
  require(WaitForMultipleObjects(2, ready, TRUE, INFINITE) == WAIT_OBJECT_0,
          "participants did not publish ready");
  // Both participants are blocked, so these fixture-only table inspections
  // do not overlap any table mutation or expose pointers to a caller.
  unsigned count = 0;
  for (mbt_buffer_track_entry_t *it = g_mbt_buffer_track_head; it; it = it->next) {
    ++count;
    require(it->refcount == (shared ? 3u : 1u), "owned reference count differs");
  }
  require(count == (shared ? 1u : 2u), "unexpected registry entries");
  require(SetEvent(resume), "resume failed");
  require(WaitForMultipleObjects(2, workers, TRUE, INFINITE) == WAIT_OBJECT_0,
          "participant join failed");
  if (shared) {
    require(g_mbt_buffer_track_head && !g_mbt_buffer_track_head->next &&
            g_mbt_buffer_track_head->refcount == 1, "main reference was lost");
    mbt_wgpu_buffer_release_tracked(root);
  }
  require(g_mbt_buffer_track_head == NULL, "retired metadata remains");
  for (int index = 0; index < 2; ++index) {
    require(CloseHandle(workers[index]), "worker handle close failed");
    require(CloseHandle(ready[index]), "ready handle close failed");
  }
  require(CloseHandle(resume), "resume handle close failed");
}

int main(int argc, char **argv) {
  require(argc == 2, "expected reuse or parallel");
  if (strcmp(argv[1], "reuse") == 0) {
    address_reuse();
    require(native_releases == 2, "release count differs");
    puts("BUFFER_TRACKING_REUSE_OK");
  } else {
    require(strcmp(argv[1], "parallel") == 0, "unknown case");
    parallel_owners(0);
    parallel_owners(1);
    require(native_releases == 5 && native_add_refs == 2, "native calls differ");
    puts("BUFFER_TRACKING_PARALLEL_OK");
  }
  return 0;
}
