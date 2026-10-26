// SPDX-License-Identifier: Apache-2.0
#include "wgpu_stub.h"
#include <stdatomic.h>

extern void mbt_wgpu_surface_release_safe(WGPUSurface surface);
extern void mbt_wgpu_cametallayer_owner_release(void *owner);

enum ReleaseKind {
  BufferEntry, ShaderEntry, ComputePipelineEntry, TextureEntry, TextureViewEntry,
  SurfaceEntry, SamplerEntry, RenderPipelineEntry, RenderBundleEncoderEntry,
  RenderBundleEntry, BindGroupLayoutEntry, BindGroupEntry, PipelineLayoutEntry,
  QuerySetEntry, CommandEncoderEntry, CommandBufferEntry, ComputePassEntry,
  RenderPassEntry, QueueEntry, DeviceEntry, AdapterEntry, InstanceEntry,
  SurfaceUnconfigureEntry
};

typedef struct NativeReleaseEntry {
  enum ReleaseKind kind;
  void *handle;
  void *auxiliary;
  int32_t target;
} NativeReleaseEntry;

enum BatchPhase { Building, Transferred, Executing, Returned, Discarded, Finished };

typedef struct MbtWgpuNativeReleaseBatch {
  atomic_int phase;
  atomic_int returned_count;
  int32_t capacity;
  int32_t count;
  NativeReleaseEntry entries[];
} MbtWgpuNativeReleaseBatch;

MbtWgpuNativeReleaseBatch *mbt_wgpu_native_release_batch_new(int32_t capacity) {
  if (capacity < 0 || (size_t)capacity >
      (SIZE_MAX - sizeof(MbtWgpuNativeReleaseBatch)) / sizeof(NativeReleaseEntry))
    return NULL;
  MbtWgpuNativeReleaseBatch *batch = calloc(1, sizeof(*batch) +
      (size_t)capacity * sizeof(NativeReleaseEntry));
  if (batch == NULL) return NULL;
  atomic_init(&batch->phase, Building);
  atomic_init(&batch->returned_count, 0);
  batch->capacity = capacity;
  return batch;
}

int32_t mbt_wgpu_native_release_batch_is_null(MbtWgpuNativeReleaseBatch *batch) {
  return batch == NULL;
}

static int32_t append(MbtWgpuNativeReleaseBatch *batch, enum ReleaseKind kind,
                       void *handle, void *auxiliary) {
  if (atomic_load(&batch->phase) != Building || batch->count == batch->capacity ||
      handle == NULL) return 0;
  batch->entries[batch->count++] = (NativeReleaseEntry){kind, handle, auxiliary, -1};
  return 1;
}

#define APPEND(name, kind, type) \
  int32_t mbt_wgpu_native_release_batch_add_##name( \
      MbtWgpuNativeReleaseBatch *batch, type value) { \
    return append(batch, kind, value, NULL); \
  }
APPEND(buffer, BufferEntry, WGPUBuffer)
APPEND(shader, ShaderEntry, WGPUShaderModule)
APPEND(compute_pipeline, ComputePipelineEntry, WGPUComputePipeline)
APPEND(texture, TextureEntry, WGPUTexture)
APPEND(texture_view, TextureViewEntry, WGPUTextureView)
APPEND(sampler, SamplerEntry, WGPUSampler)
APPEND(render_pipeline, RenderPipelineEntry, WGPURenderPipeline)
APPEND(render_bundle_encoder, RenderBundleEncoderEntry, WGPURenderBundleEncoder)
APPEND(render_bundle, RenderBundleEntry, WGPURenderBundle)
APPEND(bind_group_layout, BindGroupLayoutEntry, WGPUBindGroupLayout)
APPEND(bind_group, BindGroupEntry, WGPUBindGroup)
APPEND(pipeline_layout, PipelineLayoutEntry, WGPUPipelineLayout)
APPEND(query_set, QuerySetEntry, WGPUQuerySet)
APPEND(command_encoder, CommandEncoderEntry, WGPUCommandEncoder)
APPEND(command_buffer, CommandBufferEntry, WGPUCommandBuffer)
APPEND(compute_pass, ComputePassEntry, WGPUComputePassEncoder)
APPEND(render_pass, RenderPassEntry, WGPURenderPassEncoder)
APPEND(queue, QueueEntry, WGPUQueue)
APPEND(device, DeviceEntry, WGPUDevice)
APPEND(adapter, AdapterEntry, WGPUAdapter)
APPEND(instance, InstanceEntry, WGPUInstance)
#undef APPEND

int32_t mbt_wgpu_native_release_batch_add_surface(MbtWgpuNativeReleaseBatch *batch,
                                                  WGPUSurface surface,
                                                  void *layer_owner) {
  return append(batch, SurfaceEntry, surface, layer_owner);
}

int32_t mbt_wgpu_native_release_batch_add_surface_unconfigure(
    MbtWgpuNativeReleaseBatch *batch, int32_t surface_entry) {
  if (atomic_load(&batch->phase) != Building || batch->count == batch->capacity ||
      surface_entry <= batch->count || surface_entry >= batch->capacity) return 0;
  batch->entries[batch->count++] = (NativeReleaseEntry){
      SurfaceUnconfigureEntry, NULL, NULL, surface_entry};
  return 1;
}

int32_t mbt_wgpu_native_release_batch_validate(MbtWgpuNativeReleaseBatch *batch) {
  if (atomic_load(&batch->phase) != Building || batch->count != batch->capacity)
    return 0;
  for (int32_t index = 0; index < batch->count; ++index) {
    NativeReleaseEntry entry = batch->entries[index];
    if (entry.kind == SurfaceUnconfigureEntry &&
        (entry.target <= index || entry.target >= batch->count ||
         batch->entries[entry.target].kind != SurfaceEntry)) return 0;
  }
  return 1;
}

int32_t mbt_wgpu_native_release_batch_commit(MbtWgpuNativeReleaseBatch *batch) {
  if (!mbt_wgpu_native_release_batch_validate(batch)) return 0;
  int expected = Building;
  return atomic_compare_exchange_strong(&batch->phase, &expected, Transferred);
}

int32_t mbt_wgpu_native_release_batch_discard(MbtWgpuNativeReleaseBatch *batch) {
  int expected = Building;
  if (!atomic_compare_exchange_strong(&batch->phase, &expected, Discarded)) return 0;
  free(batch);
  return 1;
}

int32_t mbt_wgpu_native_release_batch_execute(MbtWgpuNativeReleaseBatch *batch) {
  int expected = Transferred;
  if (!atomic_compare_exchange_strong(&batch->phase, &expected, Executing)) return 0;
  for (int32_t index = 0; index < batch->count; ++index) {
    NativeReleaseEntry entry = batch->entries[index];
    switch (entry.kind) {
    case BufferEntry: mbt_wgpu_buffer_release_tracked(entry.handle); break;
    case ShaderEntry: wgpuShaderModuleRelease(entry.handle); break;
    case ComputePipelineEntry: wgpuComputePipelineRelease(entry.handle); break;
    case TextureEntry: wgpuTextureRelease(entry.handle); break;
    case TextureViewEntry: wgpuTextureViewRelease(entry.handle); break;
    case SurfaceEntry:
      mbt_wgpu_surface_release_safe(entry.handle);
      mbt_wgpu_cametallayer_owner_release(entry.auxiliary);
      break;
    case SamplerEntry: wgpuSamplerRelease(entry.handle); break;
    case RenderPipelineEntry: wgpuRenderPipelineRelease(entry.handle); break;
    case RenderBundleEncoderEntry: wgpuRenderBundleEncoderRelease(entry.handle); break;
    case RenderBundleEntry: wgpuRenderBundleRelease(entry.handle); break;
    case BindGroupLayoutEntry: wgpuBindGroupLayoutRelease(entry.handle); break;
    case BindGroupEntry: wgpuBindGroupRelease(entry.handle); break;
    case PipelineLayoutEntry: wgpuPipelineLayoutRelease(entry.handle); break;
    case QuerySetEntry: wgpuQuerySetRelease(entry.handle); break;
    case CommandEncoderEntry: wgpuCommandEncoderRelease(entry.handle); break;
    case CommandBufferEntry: wgpuCommandBufferRelease(entry.handle); break;
    case ComputePassEntry: wgpuComputePassEncoderRelease(entry.handle); break;
    case RenderPassEntry: wgpuRenderPassEncoderRelease(entry.handle); break;
    case QueueEntry: wgpuQueueRelease(entry.handle); break;
    case DeviceEntry: wgpuDeviceRelease(entry.handle); break;
    case AdapterEntry: wgpuAdapterRelease(entry.handle); break;
    case InstanceEntry: wgpuInstanceRelease(entry.handle); break;
    case SurfaceUnconfigureEntry:
      // WhyNot: reference a specific later ownership occurrence, not an equal
      // pointer or an implicit AddRef that changes the release obligations.
      wgpuSurfaceUnconfigure(batch->entries[entry.target].handle);
      break;
    }
    atomic_store(&batch->returned_count, index + 1);
  }
  // WhyNot: only native data crosses execution threads. The owner retains Moon
  // snapshots and must join its execution before reclaiming this descriptor.
  atomic_store(&batch->phase, Returned);
  return 1;
}

int32_t mbt_wgpu_native_release_batch_returned_count(MbtWgpuNativeReleaseBatch *batch) {
  return atomic_load(&batch->returned_count);
}

int32_t mbt_wgpu_native_release_batch_finish_after_join(MbtWgpuNativeReleaseBatch *batch) {
  int expected = Returned;
  if (!atomic_compare_exchange_strong(&batch->phase, &expected, Finished)) return 0;
  free(batch);
  return 1;
}
