// SPDX-License-Identifier: Apache-2.0

///|
priv enum NativeReleasePlanPhase {
  Prepared
  Committed
  Completed
  Discarded
} derive(Eq)

///|
priv struct NativeReleaseSource {
  state : Ref[AutoReleasePoolState]
  id : UInt64
  entries : Array[AutoReleaseEntry]
  count : Int32
  replacement : Array[AutoReleaseEntry]
}

///|
/// A prepared ownership transaction for ordered resource pools. All methods
/// except native batch execution belong to the creating Moon owner thread.
/// Keep this plan alive until its worker is joined or permanently retained.
pub struct PreparedNativeReleaseBatch {
  priv native : @c.NativeReleaseBatch
  priv sources : Array[NativeReleaseSource]
  priv mut phase : NativeReleasePlanPhase
}

///|
fn append_native_release_entry(
  batch : @c.NativeReleaseBatch,
  entry : AutoReleaseEntry,
) -> Bool {
  match entry {
    TrackBuffer(value) => @c.native_release_batch_add_buffer(batch, value.raw)
    TrackShaderModule(value) =>
      @c.native_release_batch_add_shader(batch, value.raw)
    TrackComputePipeline(value) =>
      @c.native_release_batch_add_compute_pipeline(batch, value.raw)
    TrackTexture(value) => @c.native_release_batch_add_texture(batch, value.raw)
    TrackTextureView(value) =>
      @c.native_release_batch_add_texture_view(batch, value.raw)
    TrackSurface(value) =>
      @c.native_release_batch_add_surface(batch, value.raw, value.layer_owner)
    TrackSampler(value) => @c.native_release_batch_add_sampler(batch, value.raw)
    TrackRenderPipeline(value) =>
      @c.native_release_batch_add_render_pipeline(batch, value.raw)
    TrackRenderBundleEncoder(value) =>
      @c.native_release_batch_add_render_bundle_encoder(batch, value.raw)
    TrackRenderBundle(value) =>
      @c.native_release_batch_add_render_bundle(batch, value.raw)
    TrackBindGroupLayout(value) =>
      @c.native_release_batch_add_bind_group_layout(batch, value.raw)
    TrackBindGroup(value) =>
      @c.native_release_batch_add_bind_group(batch, value.raw)
    TrackPipelineLayout(value) =>
      @c.native_release_batch_add_pipeline_layout(batch, value.raw)
    TrackQuerySet(value) =>
      @c.native_release_batch_add_query_set(batch, value.raw)
    TrackCommandEncoder(value) =>
      @c.native_release_batch_add_command_encoder(batch, value.raw)
    TrackCommandBuffer(value) =>
      @c.native_release_batch_add_command_buffer(batch, value.raw)
    TrackComputePass(value) =>
      @c.native_release_batch_add_compute_pass(batch, value.raw)
    TrackRenderPass(value) =>
      @c.native_release_batch_add_render_pass(batch, value.raw)
  }
}

///|
/// Capture every pool before moving any owned reference. Pool order is the
/// execution order; entries inside each pool use its ordinary reverse order.
/// Pooled borrowed aliases must not be independently released or destroyed.
pub fn PreparedNativeReleaseBatch::prepare(
  pools : Array[AutoReleasePool],
) -> PreparedNativeReleaseBatch? {
  let (sources, capacity) = match capture_native_release_sources(pools) {
    Some(captured) => captured
    None => return None
  }
  let native = @c.native_release_batch_new(capacity)
  if @c.native_release_batch_is_null(native) {
    return None
  }
  if !visit_native_release_sources(sources, entry => {
      append_native_release_entry(native, entry)
    }) {
    guard @c.native_release_batch_discard(native) else {
      abort("native release preparation lost ownership")
    }
    return None
  }
  Some({ native, sources, phase: Prepared, })
}

///|
fn capture_native_release_sources(
  pools : Array[AutoReleasePool],
) -> (Array[NativeReleaseSource], Int32)? {
  let sources : Array[NativeReleaseSource] = []
  let mut capacity = 0
  for pool in pools {
    let state = pool.state
    if state.val.phase != Open {
      return None
    }
    for previous in sources {
      if previous.id == state.val.id {
        return None
      }
    }
    let count = state.val.entries.length()
    if count > 2147483647 - capacity {
      return None
    }
    capacity += count
    sources.push({
      state,
      id: state.val.id,
      entries: state.val.entries,
      count,
      replacement: [],
    })
  }
  Some((sources, capacity))
}

///|
fn visit_native_release_sources(
  sources : Array[NativeReleaseSource],
  visit : (AutoReleaseEntry) -> Bool,
) -> Bool {
  for source in sources {
    for index = source.count - 1; index >= 0; index = index - 1 {
      if !visit(source.entries[index]) {
        return false
      }
    }
  }
  true
}

///|
/// Commit without allocation, release or suspension. A false result leaves
/// every source owner unchanged. The successful return is a scalar Bool.
pub fn PreparedNativeReleaseBatch::commit(
  self : PreparedNativeReleaseBatch,
) -> Bool {
  if self.phase != Prepared {
    return false
  }
  // WhyNot: physical_equal is not a semantic identity contract. IDs never wrap
  // or recycle. Open entries are append-only; reset/remove/reorder or array
  // replacement would require revisiting this length-only mutation guard.
  for index = 0; index < self.sources.length(); index = index + 1 {
    let source = self.sources[index]
    if source.state.val.id != source.id ||
      source.state.val.phase != Open ||
      source.state.val.entries.length() != source.count {
      return false
    }
  }
  if !@c.native_release_batch_commit(self.native) {
    return false
  }
  for index = 0; index < self.sources.length(); index = index + 1 {
    let source = self.sources[index]
    source.state.val.entries = source.replacement
    source.state.val.phase = Transferred
  }
  self.phase = Committed
  true
}

///|
/// Borrow the opaque native descriptor after commit. It must not outlive this
/// plan or be used after finish_after_join. Native execution is once-only.
pub fn PreparedNativeReleaseBatch::native_batch(
  self : PreparedNativeReleaseBatch,
) -> @c.NativeReleaseBatch {
  guard self.phase == Committed else {
    abort("native release batch is not committed")
  }
  self.native
}

///|
/// Discard only preparation data. Original pools retain their owned references.
pub fn PreparedNativeReleaseBatch::discard_prepared(
  self : PreparedNativeReleaseBatch,
) -> Bool {
  if self.phase != Prepared {
    return false
  }
  if !@c.native_release_batch_discard(self.native) {
    return false
  }
  self.phase = Discarded
  self.sources.clear()
  true
}

///|
/// Call only after the native execution and its worker/observers have joined.
/// Native returned state alone does not establish a caller's thread join.
/// On uncertain retirement retain the complete plan instead of calling this.
pub fn PreparedNativeReleaseBatch::finish_after_join(
  self : PreparedNativeReleaseBatch,
) -> Bool {
  if self.phase != Committed {
    return false
  }
  if !@c.native_release_batch_finish_after_join(self.native) {
    return false
  }
  self.phase = Completed
  for source in self.sources {
    source.state.val.phase = Released
    for entry in source.entries {
      if entry is TrackSurface(surface) {
        surface.clear_native_release_metadata()
      }
    }
  }
  self.sources.clear()
  true
}
