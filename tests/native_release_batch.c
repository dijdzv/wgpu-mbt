// SPDX-License-Identifier: Apache-2.0
#include "wgpu_stub_release_batch.c"
#include <stdio.h>

typedef struct Recorded { int kind; void *handle; } Recorded;
static Recorded calls[26];
static int called;

static void require(int condition, const char *message) {
  if (!condition) { fprintf(stderr, "native release: %s\n", message); exit(1); }
}
static void record(int kind, void *handle) {
  require(called < 26, "unexpected extra release");
  calls[called++] = (Recorded){kind, handle};
}
#define RECORD(name, type, kind) void name(type handle) { record(kind, handle); }
RECORD(mbt_wgpu_buffer_release_tracked, WGPUBuffer, 0)
RECORD(wgpuShaderModuleRelease, WGPUShaderModule, 1)
RECORD(wgpuComputePipelineRelease, WGPUComputePipeline, 2)
RECORD(wgpuTextureRelease, WGPUTexture, 3)
RECORD(wgpuTextureViewRelease, WGPUTextureView, 4)
RECORD(mbt_wgpu_surface_release_safe, WGPUSurface, 5)
RECORD(mbt_wgpu_cametallayer_owner_release, void *, 99)
RECORD(wgpuSamplerRelease, WGPUSampler, 6)
RECORD(wgpuRenderPipelineRelease, WGPURenderPipeline, 7)
RECORD(wgpuRenderBundleEncoderRelease, WGPURenderBundleEncoder, 8)
RECORD(wgpuRenderBundleRelease, WGPURenderBundle, 9)
RECORD(wgpuBindGroupLayoutRelease, WGPUBindGroupLayout, 10)
RECORD(wgpuBindGroupRelease, WGPUBindGroup, 11)
RECORD(wgpuPipelineLayoutRelease, WGPUPipelineLayout, 12)
RECORD(wgpuQuerySetRelease, WGPUQuerySet, 13)
RECORD(wgpuCommandEncoderRelease, WGPUCommandEncoder, 14)
RECORD(wgpuCommandBufferRelease, WGPUCommandBuffer, 15)
RECORD(wgpuComputePassEncoderRelease, WGPUComputePassEncoder, 16)
RECORD(wgpuRenderPassEncoderRelease, WGPURenderPassEncoder, 17)
RECORD(wgpuQueueRelease, WGPUQueue, 18)
RECORD(wgpuDeviceRelease, WGPUDevice, 19)
RECORD(wgpuAdapterRelease, WGPUAdapter, 20)
RECORD(wgpuInstanceRelease, WGPUInstance, 21)
RECORD(wgpuSurfaceUnconfigure, WGPUSurface, 22)
#undef RECORD

int main(void) {
  static int handles[23];
  require(mbt_wgpu_native_release_batch_new(-1) == NULL, "negative capacity accepted");
  MbtWgpuNativeReleaseBatch *unused = mbt_wgpu_native_release_batch_new(0);
  require(unused && mbt_wgpu_native_release_batch_discard(unused), "discard failed");
  MbtWgpuNativeReleaseBatch *invalid = mbt_wgpu_native_release_batch_new(2);
  require(invalid != NULL, "invalid-case allocation failed");
  require(!mbt_wgpu_native_release_batch_add_surface_unconfigure(invalid, 0),
          "non-later occurrence accepted");
  require(!mbt_wgpu_native_release_batch_add_surface_unconfigure(invalid, 2),
          "out-of-range occurrence accepted");
  require(mbt_wgpu_native_release_batch_add_surface_unconfigure(invalid, 1),
          "later occurrence refused prematurely");
  require(mbt_wgpu_native_release_batch_add_shader(invalid, (WGPUShaderModule)&handles[1]),
          "invalid-target descriptor append failed");
  require(!mbt_wgpu_native_release_batch_validate(invalid) &&
          !mbt_wgpu_native_release_batch_commit(invalid), "non-Surface occurrence committed");
  require(mbt_wgpu_native_release_batch_discard(invalid), "invalid plan lost preparation");
  MbtWgpuNativeReleaseBatch *batch = mbt_wgpu_native_release_batch_new(25);
  require(batch != NULL, "allocation failed");
  require(!mbt_wgpu_native_release_batch_execute(batch), "uncommitted execution accepted");
  require(!mbt_wgpu_native_release_batch_commit(batch), "incomplete batch committed");
  require(mbt_wgpu_native_release_batch_add_surface_unconfigure(batch, 6),
          "specific later Surface occurrence refused");
#define ADD(name, type, index) \
  require(mbt_wgpu_native_release_batch_add_##name(batch, (type)&handles[index]), "append failed")
  ADD(buffer, WGPUBuffer, 0);
  ADD(shader, WGPUShaderModule, 1);
  ADD(compute_pipeline, WGPUComputePipeline, 2);
  ADD(texture, WGPUTexture, 3);
  ADD(texture_view, WGPUTextureView, 4);
  require(mbt_wgpu_native_release_batch_add_surface(batch, (WGPUSurface)&handles[5],
          &handles[18]), "surface append failed");
  ADD(sampler, WGPUSampler, 6);
  ADD(render_pipeline, WGPURenderPipeline, 7);
  ADD(render_bundle_encoder, WGPURenderBundleEncoder, 8);
  ADD(render_bundle, WGPURenderBundle, 9);
  ADD(bind_group_layout, WGPUBindGroupLayout, 10);
  ADD(bind_group, WGPUBindGroup, 11);
  ADD(pipeline_layout, WGPUPipelineLayout, 12);
  ADD(query_set, WGPUQuerySet, 13);
  ADD(command_encoder, WGPUCommandEncoder, 14);
  ADD(command_buffer, WGPUCommandBuffer, 15);
  ADD(compute_pass, WGPUComputePassEncoder, 16);
  ADD(render_pass, WGPURenderPassEncoder, 17);
  ADD(buffer, WGPUBuffer, 0);
  ADD(buffer, WGPUBuffer, 0);
  ADD(queue, WGPUQueue, 19);
  ADD(device, WGPUDevice, 20);
  ADD(adapter, WGPUAdapter, 21);
  ADD(instance, WGPUInstance, 22);
#undef ADD
  require(mbt_wgpu_native_release_batch_commit(batch), "commit failed");
  require(!mbt_wgpu_native_release_batch_commit(batch), "commit repeated");
  require(!mbt_wgpu_native_release_batch_discard(batch), "transferred batch discarded");
  require(!mbt_wgpu_native_release_batch_add_buffer(batch, (WGPUBuffer)&handles[0]),
          "transferred batch changed");
  require(mbt_wgpu_native_release_batch_execute(batch), "execution refused");
  require(!mbt_wgpu_native_release_batch_execute(batch), "execution repeated");
  require(mbt_wgpu_native_release_batch_returned_count(batch) == 25, "count differs");
  require(calls[0].kind == 22 && calls[0].handle == &handles[5],
          "unconfigure did not borrow the specified future occurrence");
  int call = 1;
  for (int index = 0; index < 18; ++index) {
    require(calls[call].kind == index && calls[call].handle == &handles[index],
            "dispatch/order differs");
    ++call;
    if (index == 5) {
      require(calls[call].kind == 99 && calls[call].handle == &handles[18],
              "surface auxiliary obligation lost");
      ++call;
    }
  }
  for (int index = 0; index < 2; ++index) {
    require(calls[call].kind == 0 && calls[call].handle == &handles[0],
            "independent identical pointer obligation lost");
    ++call;
  }
  for (int index = 18; index < 22; ++index) {
    require(calls[call].kind == index && calls[call].handle == &handles[index + 1],
            "explicit parent reference lost or reordered");
    ++call;
  }
  require(call == called && called == 26, "release count differs");
  require(mbt_wgpu_native_release_batch_finish_after_join(batch), "finalization failed");
  puts("NATIVE_RELEASE_DISPATCH_OK entries=25 calls=26 kinds=22 unconfigure=1");
  return 0;
}
