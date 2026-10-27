// Copyright 2026 International Digital Economy Academy
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
fn wait_for_raw_future(instance : @wgpu.Instance, future_id : UInt64) -> Bool {
  let done : Ref[Bool] = Ref(false)
  for _i = 0; _i < 4000 && !done.val; _i = _i + 1 {
    let wait = instance.wait_any_one(future_id)
    if wait.completed {
      done.val = true
    } else {
      instance.process_events()
    }
  }
  done.val
}

///|
test "wgpu async future API: request adapter and device" {
  run_on_supported_native_platform(() => {
    let instance = @wgpu.Instance::create()
    let adapter_future = instance.request_adapter_future_id_u64()
    assert_eq(adapter_future == 0UL, false)

    let adapter_done = wait_for_raw_future(instance, adapter_future)
    inspect(adapter_done, content="true")
    if !adapter_done {
      instance.request_adapter_async_clear(adapter_future)
      instance.release()
      return
    }

    let adapter = instance.request_adapter_async_take_or_raise(adapter_future)
    let device_future = adapter.request_device_future_id_u64()
    assert_eq(device_future == 0UL, false)

    let device_done = wait_for_raw_future(instance, device_future)
    inspect(device_done, content="true")
    if !device_done {
      adapter.request_device_async_clear(device_future)
      adapter.release()
      instance.release()
      return
    }

    let device = adapter.request_device_async_take_or_raise(device_future)
    let backend = device.info_backend_type_u32()
    inspect(backend != @wgpu.BACKEND_TYPE_NULL, content="true")
    let vendor = device.info_vendor()
    ignore(vendor.length())
    let queue = device.queue()
    queue.release()
    device.release()
    adapter.release()
    instance.release()
  })
}

///|
fn request_dx12_future_adapter(
  instance : @wgpu.Instance,
  fallback : Bool,
  outstanding : Ref[Bool],
) -> @wgpu.Adapter raise Error {
  let options = @wgpu_c.request_adapter_options_new_u32(
    @wgpu.FEATURE_LEVEL_CORE,
    @wgpu.POWER_PREFERENCE_UNDEFINED,
    fallback,
    @wgpu.BACKEND_TYPE_D3_D12,
    @wgpu_c.null_surface(),
  )
  let future = instance.request_adapter_future_id_u64(options~)
  @wgpu_c.request_adapter_options_free(options)
  if future != 0UL {
    outstanding.val = true
  }
  assert_true(future != 0UL)
  assert_true(wait_for_raw_future(instance, future))
  let adapter = instance.request_adapter_async_take_or_raise(future)
  outstanding.val = false
  errdefer adapter.release()
  assert_eq(adapter.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
  adapter
}

///|
fn request_dx12_future_device(
  instance : @wgpu.Instance,
  adapter : @wgpu.Adapter,
  outstanding : Ref[Bool],
) -> @wgpu.Device raise Error {
  let future = adapter.request_device_future_id_u64()
  if future != 0UL {
    outstanding.val = true
  }
  assert_true(future != 0UL)
  assert_true(wait_for_raw_future(instance, future))
  let device = adapter.request_device_async_take_or_raise(future)
  outstanding.val = false
  errdefer device.release()
  assert_eq(device.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
  device
}

///|
test "windows D3D12 future initialization retains earlier results and recovers" {
  if @wgpu.platform_is_windows() {
    // WhyNot: a failed wait is not proof that a native callback has retired.
    let outstanding = Ref(false)
    let instance = @wgpu.Instance::create()
    defer (if !outstanding.val { instance.release() })
    let fallback = @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1")
    {
      let first = request_dx12_future_adapter(instance, fallback, outstanding)
      defer (if !outstanding.val { first.release() })
      let device1 = request_dx12_future_device(instance, first, outstanding)
      defer (if !outstanding.val { device1.release() })
      let queue1 = device1.queue()
      defer (if !outstanding.val { queue1.release() })
      assert_true(first.info_device().length() > 0)
      let second = request_dx12_future_adapter(instance, fallback, outstanding)
      defer (if !outstanding.val { second.release() })
      let device2 = request_dx12_future_device(instance, second, outstanding)
      defer (if !outstanding.val { device2.release() })
      let queue2 = device2.queue()
      defer (if !outstanding.val { queue2.release() })
      println(
        "RAW_INIT_D3D12 adapter=" +
        first.info_device() +
        " fallback_requested=" +
        fallback.to_string(),
      )
    }
    let recovered = request_dx12_future_adapter(instance, fallback, outstanding)
    defer (if !outstanding.val { recovered.release() })
    let device = request_dx12_future_device(instance, recovered, outstanding)
    defer (if !outstanding.val { device.release() })
    let queue = device.queue()
    defer (if !outstanding.val { queue.release() })
  }
}
