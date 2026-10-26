// SPDX-License-Identifier: Apache-2.0

///|
/// Native-only ordered release descriptors. Construction/commit/discard are
/// owner-thread operations. Execution may move to a native worker; the owner
/// must retain the high-level plan and join that worker before finalization.
#external
pub type NativeReleaseBatch

///|
pub extern "C" fn native_release_batch_new(
  capacity : Int32,
) -> NativeReleaseBatch = "mbt_wgpu_native_release_batch_new"

///|
pub extern "C" fn native_release_batch_is_null(
  batch : NativeReleaseBatch,
) -> Bool = "mbt_wgpu_native_release_batch_is_null"

///|
pub extern "C" fn native_release_batch_commit(
  batch : NativeReleaseBatch,
) -> Bool = "mbt_wgpu_native_release_batch_commit"

///|
pub extern "C" fn native_release_batch_discard(
  batch : NativeReleaseBatch,
) -> Bool = "mbt_wgpu_native_release_batch_discard"

///|
pub extern "C" fn native_release_batch_execute(
  batch : NativeReleaseBatch,
) -> Bool = "mbt_wgpu_native_release_batch_execute"

///|
pub extern "C" fn native_release_batch_returned_count(
  batch : NativeReleaseBatch,
) -> Int32 = "mbt_wgpu_native_release_batch_returned_count"

///|
pub extern "C" fn native_release_batch_finish_after_join(
  batch : NativeReleaseBatch,
) -> Bool = "mbt_wgpu_native_release_batch_finish_after_join"

///|
pub extern "C" fn native_release_batch_add_buffer(
  batch : NativeReleaseBatch,
  value : Buffer,
) -> Bool = "mbt_wgpu_native_release_batch_add_buffer"

///|
pub extern "C" fn native_release_batch_add_shader(
  batch : NativeReleaseBatch,
  value : ShaderModule,
) -> Bool = "mbt_wgpu_native_release_batch_add_shader"

///|
pub extern "C" fn native_release_batch_add_compute_pipeline(
  batch : NativeReleaseBatch,
  value : ComputePipeline,
) -> Bool = "mbt_wgpu_native_release_batch_add_compute_pipeline"

///|
pub extern "C" fn native_release_batch_add_texture(
  batch : NativeReleaseBatch,
  value : Texture,
) -> Bool = "mbt_wgpu_native_release_batch_add_texture"

///|
pub extern "C" fn native_release_batch_add_texture_view(
  batch : NativeReleaseBatch,
  value : TextureView,
) -> Bool = "mbt_wgpu_native_release_batch_add_texture_view"

///|
pub extern "C" fn native_release_batch_add_surface(
  batch : NativeReleaseBatch,
  value : WGPUSurface,
  layer_owner : OpaquePtr,
) -> Bool = "mbt_wgpu_native_release_batch_add_surface"

///|
pub extern "C" fn native_release_batch_add_sampler(
  batch : NativeReleaseBatch,
  value : Sampler,
) -> Bool = "mbt_wgpu_native_release_batch_add_sampler"

///|
pub extern "C" fn native_release_batch_add_render_pipeline(
  batch : NativeReleaseBatch,
  value : RenderPipeline,
) -> Bool = "mbt_wgpu_native_release_batch_add_render_pipeline"

///|
pub extern "C" fn native_release_batch_add_render_bundle_encoder(
  batch : NativeReleaseBatch,
  value : WGPURenderBundleEncoder,
) -> Bool = "mbt_wgpu_native_release_batch_add_render_bundle_encoder"

///|
pub extern "C" fn native_release_batch_add_render_bundle(
  batch : NativeReleaseBatch,
  value : WGPURenderBundle,
) -> Bool = "mbt_wgpu_native_release_batch_add_render_bundle"

///|
pub extern "C" fn native_release_batch_add_bind_group_layout(
  batch : NativeReleaseBatch,
  value : BindGroupLayout,
) -> Bool = "mbt_wgpu_native_release_batch_add_bind_group_layout"

///|
pub extern "C" fn native_release_batch_add_bind_group(
  batch : NativeReleaseBatch,
  value : BindGroup,
) -> Bool = "mbt_wgpu_native_release_batch_add_bind_group"

///|
pub extern "C" fn native_release_batch_add_pipeline_layout(
  batch : NativeReleaseBatch,
  value : PipelineLayout,
) -> Bool = "mbt_wgpu_native_release_batch_add_pipeline_layout"

///|
pub extern "C" fn native_release_batch_add_query_set(
  batch : NativeReleaseBatch,
  value : QuerySet,
) -> Bool = "mbt_wgpu_native_release_batch_add_query_set"

///|
pub extern "C" fn native_release_batch_add_command_encoder(
  batch : NativeReleaseBatch,
  value : CommandEncoder,
) -> Bool = "mbt_wgpu_native_release_batch_add_command_encoder"

///|
pub extern "C" fn native_release_batch_add_command_buffer(
  batch : NativeReleaseBatch,
  value : CommandBuffer,
) -> Bool = "mbt_wgpu_native_release_batch_add_command_buffer"

///|
pub extern "C" fn native_release_batch_add_compute_pass(
  batch : NativeReleaseBatch,
  value : ComputePassEncoder,
) -> Bool = "mbt_wgpu_native_release_batch_add_compute_pass"

///|
pub extern "C" fn native_release_batch_add_render_pass(
  batch : NativeReleaseBatch,
  value : RenderPassEncoder,
) -> Bool = "mbt_wgpu_native_release_batch_add_render_pass"
