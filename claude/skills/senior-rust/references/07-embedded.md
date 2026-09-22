# Embedded and `no_std`

Scope: `no_std` fundamentals, embedded-hal traits, the embassy async ecosystem, defmt/probe-rs debugging, memory constraints, and target/build configuration.

## `no_std` Fundamentals

- `#![no_std]` links `core` (and optionally `alloc`); you lose `std` types, `std::io`, panics-with-unwind, and the default global allocator.
- `#![no_main]` plus a runtime crate's entry macro (`#[cortex_m_rt::entry]`, `#[esp_hal::main]`, `#[embassy_executor::main]`) replaces the standard start code.
- Every binary needs a panic handler and (on bare metal) a memory layout. Pick:
  - `panic-halt`: stop execution; smallest.
  - `panic-probe` (defmt): prints the panic over RTT; best for debugging.
  - `panic-reset` / custom `#[panic_handler]`.
- `default-features = false` everywhere in the dependency tree; verify each crate supports `no_std` (many do behind a `std` feature).
- `alloc` needs a `#[global_allocator]`; on MCUs prefer `embedded-alloc` or `linked_list_allocator`, but treat dynamic allocation as exceptional.
- `core::fmt` is available but pulls formatting code (~10s of KiB); avoid `format!` in hot or size-critical paths.
- Replace `std` tooling with `core` equivalents: `core::fmt::Write`, `core::cell::RefCell`/`Cell`, `core::sync::atomic`, `spin::Mutex` or `critical-section` for locks.

```rust
#![no_std]
#![no_main]
use panic_probe as _;
use cortex_m_rt::entry;

#[entry]
fn main() -> ! {
    loop { core::hint::spin_loop(); }
}
```

## Target and Build Configuration

- Common targets: `thumbv6m-none-eabi` (Cortex-M0), `thumbv7em-none-eabihf` (M4F/M7), `thumbv8m.main-none-eabihf` (M33+), `riscv32imac-unknown-none-elf`, `riscv32imc-unknown-none-elf` (ESP32-C3), `xtensa-esp32-none-elf`.
- Pin the toolchain in `rust-toolchain.toml` with the target and components; commit it.
- `build-std` (rebuilding `core`/`alloc`) is still nightly-only in practice; use it for custom targets or when a dependency requires it. Verify upstream for stable support.

```toml
# .cargo/config.toml
[build]
target = "thumbv7em-none-eabihf"
rustflags = ["-C", "link-arg=-Tlink.x"]

[target.thumbv7em-none-eabihf]
runner = "probe-rs run --chip STM32F411CEUx"

[env]
DEFMT_LOG = "info"
```

- `memory.x` declares FLASH/RAM origins and lengths for `cortex-m-rt`; a wrong value silently corrupts links. Custom memory layouts need matching linker scripts and stack placement.
- `build.rs` copies `memory.x` into `OUT_DIR` (typical `cortex-m-rt` boilerplate) or sets link search paths.
- Probe/runner setup: `probe-rs run`, OpenOCD, or vendor tools; `cargo embed` wraps flashing + RTT.
- For RP2040/ESP, use the vendor HAL's build flow (`embassy-rp`, `esp-hal` + `espflash`); bootloader and partition concerns differ from Cortex-M.
- Size checks in CI: `cargo size --release -- -A`, `cargo bloat`, `cargo nm` for symbol sizes; fail on regressions.

## embedded-hal (1.0 line)

- Traits are the portability layer between drivers and HALs. Implement HAL traits; write drivers against traits.
- Core traits (verify exact signatures upstream for the 1.0 line):
  - `OutputPin` (`set_high`, `set_low`), `InputPin` (`is_high`).
  - `SpiDevice`/`SpiBus` (transaction-based), `I2c` (`write`, `read`, `write_read`).
  - `DelayNs` (`delay_ns`/`delay_ms`/`delay_us`), `Pwm`, `Adc`, `Serial`.
- Async twins in `embedded-hal-async` (`SpiDevice`, `I2c`, `DelayNs` as `Future`) enable interrupt-driven drivers without blocking.
- `embedded-io`/`embedded-io-async` for byte-stream abstractions; `embedded-can`, `embedded-graphics`, `embedded-nal` for other domains.
- Driver crates should be generic over traits (`pub struct Mpu6050<I: I2c> { i2c: I }`) and return `Result<_, I::Error>` or a driver-defined error.
- Do not implement `embedded-hal` traits for types whose errors are unrepresentable; use `Infallible` where no failure exists.

```rust
use embedded_hal::digital::OutputPin;
use embedded_hal::delay::DelayNs;

fn blink<P: OutputPin, D: DelayNs>(pin: &mut P, delay: &mut D) {
    loop {
        let _ = pin.set_high();
        delay.delay_ms(500);
        let _ = pin.set_low();
        delay.delay_ms(500);
    }
}
```

## Async Embedded (embassy and friends)

- `embassy-executor` is the de-facto async executor: cooperative, interrupt-driven wakers, static task allocation via `#[embassy_executor::task]` and `Spawner`.
- `embassy-time` provides timers (`Timer::after`, `Ticker`); configure a time driver from the HAL.
- `embassy-sync` mirrors async sync primitives for `no_std`: `Mutex`, `Signal`, `Channel`, `Watch`, `PubSubChannel`.
- `embassy-stm32`/`embassy-nrf`/`embassy-rp` combine HAL + interrupt integration; `esp-hal` has its own async executor support.
- Tasks are statically allocated with pool sizes; the executor is a future scheduler, not a preemptive RTOS. Reentrancy safety comes from interrupt priorities and critical sections.
- Interrupt handlers must be cooperative: no blocking waits, minimal work, wake a task instead.
- Cancellation and drop semantics match `std` async: dropping a future cancels at await points. See `./03-async-concurrency.md` for the mental model.
- Priorities: hardware interrupts preempt tasks; use `critical-section` to protect shared state shared with ISRs.

```rust
#[embassy_executor::task]
async fn heartbeat(mut led: Output<'static>) {
    loop {
        led.toggle();
        embassy_time::Timer::after_millis(500).await;
    }
}
```

## Memory Constraints

- RAM is measured in tens/hundreds of KiB; stack overflow is silent corruption, not a clean panic. Estimate the deepest call chain and async state sizes (`core::mem::size_of_val` on futures at compile time via tests).
- Static allocation first: `static` buffers, `heapless::{Vec, String, Deque, Map}` with fixed capacities.
- If using `alloc`: single-threaded allocator, set aside a fixed arena, and either make allocation failure fatal or avoid it in steady state.
- Watch sizes: `size_of` on futures, `cargo bloat`, `nm --size-sort`; a single `format!` can add kilobytes.
- `defmt` strings live in flash, not RAM; still avoid formatting in hot loops.
- Use `#[inline]` selectively; flash is finite too. `opt-level = "s"` or `"z"`, `lto = true`, `codegen-units = 1`, `panic = "abort"` for release.
- Stack placement and interrupt stack: on some targets interrupts use the main stack; on others (e.g., RP2040) there are per-core stacks. Know your chip.
- Data in flash: `static` immutable data, `#[link_section = ".rodata"]`; DMA buffers must be in RAM and often aligned.
- Avoid recursion; use explicit state machines or `heapless::Vec`-based stacks.

## Debugging and Logging (defmt + probe-rs)

- `defmt` compresses log strings into flash and sends binary frames over RTT/SWO; far cheaper than `log`+UART.
- Setup: `defmt = "0.3"` (verify current line), `defmt-rtt` transport, `panic-probe` with the `defmt` feature, and `DEFMT_LOG=info` in `.cargo/config.toml`.
- `defmt::info!`, `warn!`, `error!`, `debug!`, `trace!`, `assert!`; derive `defmt::Format` for custom types (or use `{=[u8]:a}` hints for slices).
- Global logger: depend on `defmt-rtt`; only one global logger per firmware.
- `probe-rs` reads RTT: `probe-rs run --chip <CHIP>`, `probe-rs attach`, `probe-rs gdb`; `defmt-print` decodes captured streams.
- Timestamps/sequences: `defmt` supports timestamping (elapsed time) when the HAL provides a timer; verify integration for your HAL.
- Alternatives: `rtt-target` for plain RTT, UART logging when a probe is unavailable (costly), `tracing` on host-emulated targets.
- Debugging: `probe-rs gdb` or `arm-none-eabi-gdb` plus `openocd`; hardware breakpoints are limited (typically 2-6); flash breakpoints can be used.
- `embedded-test` runs unit tests on hardware; keep a `#[cfg(test)]` harness that doesn't require `std::test`.

## One Professional Embedded Crate

```text
firmware/
  Cargo.toml
  build.rs            # memory.x
  memory.x
  .cargo/config.toml  # target, runner, defmt env
  rust-toolchain.toml # pinned nightly/channel + target
  src/main.rs         # entry, tasks
  src/net.rs          # ...
crates/
  sensor-driver/      # no_std driver over embedded-hal traits
```

- Split hardware-independent logic (state machines, protocols) into portable crates tested on the host; keep HAL coupling in the firmware crate.
- Run host tests on the portable crates; hardware tests stay minimal and manual or on a bench rig.

## Anti-Patterns

- `std`-only crates pulled in by accident (often via default features).
- Overflowing the stack silently by recursion or deep async chains.
- Blocking `Delay` inside async tasks (`embassy-time` or `embedded-hal-async` instead).
- Using a heap in interrupt context or from multiple cores without synchronization.
- Ignoring `critical-section` around shared state accessed by ISRs.
- Shipping with `panic-halt` and no boot-time watchdog when field resets are required.
- Building for the wrong target/features and only noticing a crash in the field.
- Logging through a blocking UART in a timing-critical loop.

## Checklist

- [ ] `no_std` gate verified (`cargo check --target <t>`) in CI; no accidental `std` dependency.
- [ ] Panic handler chosen and documented; watchdog strategy defined for field devices.
- [ ] Drivers written against `embedded-hal` traits; async twins where appropriate.
- [ ] Memory budget measured (`.bss/.data/.text`, stack high-water) and enforced in CI.
- [ ] `defmt` used with RTT; log level configurable per build.
- [ ] Shared state with ISRs protected (`critical-section` or atomics with correct ordering).
- [ ] Toolchain, target, and runner pinned in-repo.
- [ ] Portable logic host-tested; hardware tests documented.
