# Newtua (Swift package)

Idiomatic Swift bindings for [newtua](../../README.md) — a fast, in-process Rust
archive extractor (a rewrite of The Unarchiver). Thin wrapper over the C ABI
(`newtua-ffi`). This package is the foundation for the macOS SwiftUI GUI.

```swift
import Newtua

let archive = try Archive(path: "photos.zip")   // password:, encoding: optional
print(archive.count, "entries")
for entry in archive.entries() {
    print(entry.path, entry.kind, entry.size, entry.isEncrypted)
}

let data = try archive.read(0)                  // Data of one entry

let report = try archive.extract(to: "out/") { progress in
    // progress.started / .finished / .index / .bytesWritten ...
    return true                                  // return false to cancel
}
print(report.extracted, report.failed, report.aborted)
```

Errors are thrown as `NewtuaError` (carries `code` and a localized `message`).

## Build & test

The package links the Rust static library, so build it first:

```bash
cargo build -p newtua-ffi          # produces target/debug/libnewtua_ffi.a
cd bindings/swift
swift test
```

`Package.swift` computes the absolute path to `target/debug` from its own
location, and links the native deps the Rust static lib needs
(`CoreFoundation`, `c++`, `pthread`, `lzma`, `iconv`, `bz2` — from
`cargo rustc -- --print native-static-libs`). For a release build, point the
`-L` flag at `target/release` instead.

## Layout

- `Sources/CNewtua/` — module map + `newtua.h` (a copy of the cbindgen-generated
  `crates/newtua-ffi/include/newtua.h`; refresh it by copying when the C ABI
  changes).
- `Sources/Newtua/` — the idiomatic Swift wrapper.
- `Tests/NewtuaTests/` — `swift test` over a committed fixture.
