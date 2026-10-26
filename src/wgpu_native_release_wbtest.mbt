// SPDX-License-Identifier: Apache-2.0

///|
test "native release preserves caller pool order and reverses entries inside each pool" {
  let first = AutoReleasePool::new()
  let second = AutoReleasePool::new()
  // WhyNot: these synthetic placeholders test ordering only. They never enter
  // native preparation, execution or ordinary release.
  ignore(first.track_texture_view({ raw: @c.null_texture_view(), }))
  ignore(first.track_pipeline_layout({ raw: @c.null_pipeline_layout(), }))
  ignore(
    second.track_surface({
      raw: @c.null_surface(),
      layer: @c.null_opaque_ptr(),
      layer_owner: @c.null_opaque_ptr(),
      owner_window_handle: None,
      owner_display_handle: None,
    }),
  )
  ignore(second.track_texture_view({ raw: @c.null_texture_view(), }))
  let (sources, count) = capture_native_release_sources([first, second]).unwrap()
  assert_eq(count, 4)
  let seen : Array[Int32] = []
  assert_true(
    visit_native_release_sources(sources, entry => {
      seen.push(
        match entry {
          TrackTextureView(_) => 1
          TrackPipelineLayout(_) => 2
          TrackSurface(_) => 3
          _ => 0
        },
      )
      true
    }),
  )
  assert_eq(seen, [2, 1, 1, 3])
  assert_eq(first.state.val.phase, Open)
  assert_eq(second.state.val.phase, Open)
}

///|
test "native release refuses alias duplicates and stale sources without partial transfer" {
  let first = AutoReleasePool::new()
  let second = AutoReleasePool::new()
  let same_pool = first
  assert_true(PreparedNativeReleaseBatch::prepare([first, same_pool]) is None)
  assert_true(first.state.val.id != second.state.val.id)
  let plan = PreparedNativeReleaseBatch::prepare([first, second]).unwrap()
  second.release()
  assert_false(plan.commit())
  assert_eq(first.state.val.phase, Open)
  assert_eq(second.state.val.phase, Released)
  assert_true(plan.discard_prepared())
  let appended = AutoReleasePool::new()
  let stale = PreparedNativeReleaseBatch::prepare([first, appended]).unwrap()
  // WhyNot: only the append guard is under test; this placeholder is never
  // captured into a descriptor or sent to native release.
  ignore(appended.track_texture_view({ raw: @c.null_texture_view(), }))
  assert_false(stale.commit())
  assert_eq(first.state.val.phase, Open)
  assert_eq(appended.state.val.phase, Open)
  assert_eq(appended.state.val.entries.length(), 1)
  assert_true(stale.discard_prepared())
  first.state.val.phase = Releasing
  assert_true(PreparedNativeReleaseBatch::prepare([first]) is None)
  first.state.val.phase = Open
}

///|
test "native release commit execution and owner finalization are separate once-only transitions" {
  let first = AutoReleasePool::new()
  let second = AutoReleasePool::new()
  let discarded = PreparedNativeReleaseBatch::prepare([first]).unwrap()
  assert_true(discarded.discard_prepared())
  assert_false(discarded.commit())
  assert_eq(first.state.val.phase, Open)
  let plan = PreparedNativeReleaseBatch::prepare([first, second]).unwrap()
  assert_true(plan.commit())
  assert_false(plan.commit())
  assert_false(plan.discard_prepared())
  assert_eq(first.state.val.phase, Transferred)
  assert_eq(second.state.val.phase, Transferred)
  first.release()
  assert_eq(first.state.val.phase, Transferred)
  assert_false(plan.finish_after_join())
  let native = plan.native_batch()
  // Synchronous empty execution has returned here; there is no foreign worker
  // to join in this resource-free transition control.
  assert_true(@c.native_release_batch_execute(native))
  assert_eq(@c.native_release_batch_returned_count(native), 0)
  assert_false(@c.native_release_batch_execute(native))
  assert_true(plan.finish_after_join())
  assert_false(plan.finish_after_join())
  assert_eq(first.state.val.phase, Released)
  assert_eq(second.state.val.phase, Released)
}
