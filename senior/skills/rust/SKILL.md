---
name: rust
version: 1.0.0
description: "Deep Rust patterns for project structure, async, error handling, unsafe, FFI, embedded, and testing"
---

# Rust

## Project Structure

### Workspace
```toml
[workspace]
members = ["crates/*"]
resolver = "2"
```

### Cargo.toml
```toml
[package]
name = "my-crate"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
thiserror = "1"
serde = { version = "1", features = ["derive"] }
```

## Async Patterns (Tokio)

### JoinSet
```rust
use tokio::task::JoinSet;

async fn run_tasks() {
    let mut set = JoinSet::new();
    for i in 0..10 {
        set.spawn(async move { process(i).await });
    }
    while let Some(res) = set.join_next().await {
        let result = res?;
    }
}
```

### CancellationToken
```rust
use tokio_util::sync::CancellationToken;

async fn worker(token: CancellationToken) {
    tokio::select! {
        _ = token.cancelled() => return,
        result = do_work() => { /* handle result */ }
    }
}

async fn main() {
    let token = CancellationToken::new();
    let h = tokio::spawn(worker(token.clone()));
    token.cancel();
    h.await;
}
```

## Error Handling

### thiserror
```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("not found: {0}")]
    NotFound(String),
    #[error("validation failed")]
    Validation { field: String, msg: String },
    #[error(transparent)]
    Io(#[from] std::io::Error),
}
```

### anyhow
```rust
use anyhow::{Result, Context};

fn parse_config(path: &str) -> Result<Config> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read {path}"))?;
    Ok(serde_json::from_str(&content)?)
}
```

## Unsafe Guidelines

- Minimize `unsafe` blocks. Extract into safe abstractions.
- Document safety invariants with `// SAFETY:` comments.
- Use `NonNull<T>` instead of raw pointers where possible.
- Validate references with `as_ref()` / `as_mut()`.

```rust
impl<T> MyVec<T> {
    pub fn get(&self, index: usize) -> Option<&T> {
        if index < self.len {
            // SAFETY: index verified within bounds
            Some(unsafe { &*self.ptr.add(index) })
        } else {
            None
        }
    }
}
```

## FFI Patterns

```rust
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

extern "C" fn my_callback(data: *mut c_char) {
    // SAFETY: C caller guarantees valid pointer
    let s = unsafe { CStr::from_ptr(data) };
}

#[no_mangle]
pub extern "C" fn rust_function(input: *const c_char) -> *mut c_char {
    let s = unsafe { CStr::from_ptr(input) }.to_str().unwrap();
    CString::new(format!("hello {s}")).unwrap().into_raw()
}
```

## Embedded (no_std)

```rust
#![no_std]
#![no_main]

use embedded_hal::digital::OutputPin;
use panic_halt as _;

#[arduino_hal::entry]
fn main() -> ! {
    let dp = arduino_hal::Peripherals::take().unwrap();
    let pins = arduino_hal::pins!(dp);
    let mut led = pins.d13.into_output();
    loop {
        led.set_high();
        arduino_hal::delay_ms(1000);
        led.set_low();
        arduino_hal::delay_ms(1000);
    }
}
```

## Testing

### proptest
```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn parse_doesnt_crash(s in ".*") {
        let _ = parse(&s);
    }
}
```

### criterion
```rust
use criterion::{black_box, Criterion};

fn bench_encode(c: &mut Criterion) {
    c.bench_function("encode", |b| b.iter(|| encode(black_box(&data))));
}
```

## Profiling

```bash
# Flamegraph
CARGO_PROFILE_RELEASE_DEBUG=true cargo flamegraph

# perf
perf record --call-graph dwarf target/release/mybin
perf report
```

- Use `cargo-flamegraph` for quick flamegraphs.
- Use `perf` for detailed CPU analysis.
- Valgrind for memory issues.
