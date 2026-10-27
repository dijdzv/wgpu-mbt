// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
fn wait_for_queue_map_read(
  instance : @wgpu.Instance,
  device : @wgpu.Device,
  future_id : UInt64,
) -> Bool {
  ignore(device.poll(wait=true))
  let completed : Ref[Bool] = Ref(false)
  for _i = 0; _i < 4000 && !completed.val; _i = _i + 1 {
    ignore(device.poll())
    let wait = instance.wait_any_one(future_id)
    completed.val = wait.completed
    if !completed.val {
      instance.process_events()
    }
  }
  completed.val
}

///|
test "windows D3D12 destroyed pending map future clears and recovers" {
  if @wgpu.platform_is_windows() {
    // WhyNot: an unfinished future or queued write can still use native handles.
    let outstanding = Ref(false)
    let instance = @wgpu.Instance::create()
    defer (if !outstanding.val { instance.release() })
    let fallback = @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1")
    let adapter = instance.request_adapter_sync_options_u32(
      backend_type_u32=@wgpu.BACKEND_TYPE_D3_D12,
      force_fallback_adapter=fallback,
    )
    defer (if !outstanding.val { adapter.release() })
    assert_eq(adapter.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
    let device = adapter.request_device_sync(instance)
    defer (if !outstanding.val { device.release() })
    assert_eq(device.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
    let queue = device.queue()
    defer (if !outstanding.val { queue.release() })
    println(
      "RAW_MAP_D3D12 adapter=" +
      adapter.info_device() +
      " fallback_requested=" +
      fallback.to_string(),
    )
    let source = device.create_buffer(
      size=8UL,
      usage=bu(@wgpu.BUFFER_USAGE_COPY_SRC | @wgpu.BUFFER_USAGE_COPY_DST),
    )
    defer (if !outstanding.val { source.release() })
    let bytes = u32le_pack([0x01020304U, 0x05060708U])
    outstanding.val = true
    queue.write_buffer(source, 0UL, bytes)
    let usage = bu(@wgpu.BUFFER_USAGE_MAP_READ | @wgpu.BUFFER_USAGE_COPY_DST)
    let doomed = device.create_buffer(size=8UL, usage~)
    defer (if !outstanding.val { doomed.release() })
    let encoder = device.create_command_encoder()
    defer (if !outstanding.val { encoder.release() })
    encoder.copy_buffer_to_buffer(source, 0UL, doomed, 0UL, 8UL)
    let command = encoder.finish()
    defer (if !outstanding.val { command.release() })
    let future = queue.submit_one_and_map_read_async(command, doomed, 0UL, 8UL)
    assert_true(future != 0UL)
    assert_eq(queue.map_read_async_status_u32(future), 0U)
    doomed.destroy()
    let after_destroy = queue.map_read_async_status_u32(future)
    assert_true(
      after_destroy == 0U || after_destroy == @wgpu.MAP_ASYNC_STATUS_ABORTED,
    )
    assert_true(wait_for_queue_map_read(instance, device, future))
    assert_eq(
      queue.map_read_async_status_u32(future),
      @wgpu.MAP_ASYNC_STATUS_ABORTED,
    )
    queue.map_read_async_clear(future)
    outstanding.val = false
    assert_eq(queue.map_read_async_status_u32(future), 0U)
    assert_eq(queue.map_read_async_read(future), [])

    let fresh = device.create_buffer(size=8UL, usage~)
    defer (if !outstanding.val { fresh.release() })
    let recovery_encoder = device.create_command_encoder()
    defer (if !outstanding.val { recovery_encoder.release() })
    recovery_encoder.copy_buffer_to_buffer(source, 0UL, fresh, 0UL, 8UL)
    let recovery_command = recovery_encoder.finish()
    defer (if !outstanding.val { recovery_command.release() })
    outstanding.val = true
    let recovery = queue.submit_one_and_map_read_async(
      recovery_command, fresh, 0UL, 8UL,
    )
    assert_true(recovery != 0UL)
    assert_true(wait_for_queue_map_read(instance, device, recovery))
    assert_eq(
      queue.map_read_async_status_u32(recovery),
      @wgpu.MAP_ASYNC_STATUS_SUCCESS,
    )
    assert_eq(queue.map_read_async_read(recovery), bytes)
    queue.map_read_async_clear(recovery)
    outstanding.val = false
    assert_eq(queue.map_read_async_status_u32(recovery), 0U)
    assert_eq(queue.map_read_async_read(recovery), [])
  }
}

///|
test "wgpu queue.on_submitted_work_done_sync" {
  let instance = @wgpu.Instance::create()
  let adapter = instance.request_adapter_sync()
  let device = adapter.request_device_sync(instance)
  let queue = device.queue()

  // Submit an empty command buffer so there's definitely work tracked by the queue.
  let encoder = device.create_command_encoder()
  let cmd = encoder.finish()
  queue.submit_one(cmd)
  let status = queue.on_submitted_work_done_sync(instance)
  inspect(status == @wgpu.QUEUE_WORK_DONE_STATUS_SUCCESS, content="true")

  let encoder2 = device.create_command_encoder()
  let cmd2 = encoder2.finish()
  queue.submit_one(cmd2)
  queue.on_submitted_work_done_sync_or_raise(instance)

  let encoder3 = device.create_command_encoder()
  let cmd3 = encoder3.finish()
  queue.submit_one(cmd3)
  queue.on_submitted_work_done_wait_or_raise(instance)

  let encoder4 = device.create_command_encoder()
  let cmd4 = encoder4.finish()
  queue.submit_one(cmd4)
  let timeout_raised_msg : Ref[String] = Ref("")
  queue.on_submitted_work_done_wait_or_raise(instance, timeout_ns=1UL) catch {
    e => timeout_raised_msg.val = e.message()
  }
  inspect(
    timeout_raised_msg.val.contains("UnsupportedTimeout"[:]),
    content="true",
  )

  cmd4.release()
  encoder4.release()
  cmd3.release()
  encoder3.release()
  cmd2.release()
  encoder2.release()
  cmd.release()
  encoder.release()
  queue.release()
  device.release()
  adapter.release()
  instance.release()
}

///|
test "wgpu queue: submit one and map read async" {
  let instance = @wgpu.Instance::create()
  let adapter = instance.request_adapter_sync()
  let device = adapter.request_device_sync(instance)
  let queue = device.queue()

  let src = device.create_buffer(
    size=8UL,
    usage=bu(@wgpu.BUFFER_USAGE_COPY_SRC | @wgpu.BUFFER_USAGE_COPY_DST),
  )
  let staging = device.create_buffer(
    size=8UL,
    usage=bu(@wgpu.BUFFER_USAGE_MAP_READ | @wgpu.BUFFER_USAGE_COPY_DST),
  )
  queue.write_buffer(src, 0UL, u32le_pack([0x11223344U, 0x55667788U]))

  let encoder = device.create_command_encoder()
  encoder.copy_buffer_to_buffer(src, 0UL, staging, 0UL, 8UL)
  let cmd = encoder.finish()
  let future_id = queue.submit_one_and_map_read_async(cmd, staging, 0UL, 8UL)
  inspect(future_id != 0UL, content="true")
  inspect(wait_for_queue_map_read(instance, device, future_id), content="true")
  inspect(
    queue.map_read_async_status_u32(future_id) == @wgpu.MAP_ASYNC_STATUS_SUCCESS,
    content="true",
  )
  let out = queue.map_read_async_read(future_id)
  @debug.debug_inspect(
    [u32le_at(out, 0), u32le_at(out, 4)],
    content="[287454020, 1432778632]",
  )
  inspect(@wgpu_c.buffer_map_state_u32(staging.get_map_state()), content="3")
  queue.map_read_async_clear(future_id)
  inspect(@wgpu_c.buffer_map_state_u32(staging.get_map_state()), content="1")

  queue.write_buffer(src, 0UL, u32le_pack([0xaabbccddU, 0x10203040U]))
  let encoder2 = device.create_command_encoder()
  encoder2.copy_buffer_to_buffer(src, 0UL, staging, 0UL, 8UL)
  let cmd2 = encoder2.finish()
  let future_id2 = queue.submit_one_and_map_read_async(cmd2, staging, 0UL, 8UL)
  inspect(future_id2 != 0UL, content="true")
  inspect(wait_for_queue_map_read(instance, device, future_id2), content="true")
  let out2 = queue.map_read_async_read(future_id2)
  @debug.debug_inspect(
    [u32le_at(out2, 0), u32le_at(out2, 4)],
    content="[2864434397, 270544960]",
  )
  queue.map_read_async_clear(future_id2)

  cmd2.release()
  encoder2.release()
  cmd.release()
  encoder.release()
  staging.release()
  src.release()
  queue.release()
  device.release()
  adapter.release()
  instance.release()
}

///|
test "wgpu queue: submit map read owns pending user handles" {
  let instance = @wgpu.Instance::create()
  let adapter = instance.request_adapter_sync()
  let device = adapter.request_device_sync(instance)
  let queue = device.queue()
  let report0 = instance.generate_report()
  let kept0_buffers = report0.hub_buffers_num_kept_from_user()
  let rel0_buffers = report0.hub_buffers_num_released_from_user()
  report0.release()

  let src = device.create_buffer(
    size=8UL,
    usage=bu(@wgpu.BUFFER_USAGE_COPY_SRC | @wgpu.BUFFER_USAGE_COPY_DST),
  )
  let staging = device.create_buffer(
    size=8UL,
    usage=bu(@wgpu.BUFFER_USAGE_MAP_READ | @wgpu.BUFFER_USAGE_COPY_DST),
  )
  queue.write_buffer(src, 0UL, u32le_pack([0x01020304U, 0x05060708U]))

  let encoder = device.create_command_encoder()
  encoder.copy_buffer_to_buffer(src, 0UL, staging, 0UL, 8UL)
  let cmd = encoder.finish()
  let future_id = queue.submit_one_and_map_read_async(cmd, staging, 0UL, 8UL)
  inspect(future_id != 0UL, content="true")

  queue.map_read_async_clear(future_id)
  cmd.release()
  encoder.release()
  staging.release()
  src.release()

  inspect(wait_for_queue_map_read(instance, device, future_id), content="true")
  inspect(
    queue.map_read_async_status_u32(future_id) == @wgpu.MAP_ASYNC_STATUS_SUCCESS,
    content="true",
  )
  let out = queue.map_read_async_read(future_id)
  @debug.debug_inspect(
    [u32le_at(out, 0), u32le_at(out, 4)],
    content="[16909060, 84281096]",
  )
  queue.map_read_async_clear(future_id)
  ignore(device.poll(wait=true))
  instance.process_events()

  let report1 = instance.generate_report()
  assert_eq(report1.hub_buffers_num_kept_from_user(), kept0_buffers)
  assert_eq(report1.hub_buffers_num_released_from_user() > rel0_buffers, true)
  report1.release()

  queue.release()
  device.release()
  adapter.release()
  instance.release()
}
