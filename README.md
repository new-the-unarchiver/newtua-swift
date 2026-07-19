# Newtua for Swift

> Swift bindings for **New The Unarchiver** — a fast, in-process archive
> extractor. No Rust toolchain required: the engine ships as a prebuilt
> XCFramework.

[![License: LGPL v3](https://img.shields.io/badge/License-LGPLv3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014+-lightgrey.svg)](#requirements)

---

Reads some three dozen archive formats — zip, 7z, rar, tar and the modern
container family, plus the legacy Mac, Amiga and DOS formats The Unarchiver was
known for. Everything happens inside your process: no bundled `unar`, `7z` or
`tar` to shell out to, and nothing to install alongside your app.

Extraction is **read-only by design**. Nothing here creates archives.

## Install

Add the package in Xcode (*File ▸ Add Package Dependencies…*) with the URL
`https://github.com/new-the-unarchiver/newtua-swift`, or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/new-the-unarchiver/newtua-swift", from: "0.1.0")
]
```

The engine arrives as a prebuilt universal (arm64 + x86_64) XCFramework
attached to the release, so nothing is compiled from Rust on your machine.

## Use

```swift
import Newtua

let archive = try Archive(path: "photos.zip")   // password:, encoding: optional
print(archive.count, "entries")

for entry in archive.entries() {
    print(entry.path, entry.kind, entry.size, entry.isEncrypted)
}

let data = try archive.read(0)                  // one entry, as Data

let report = try archive.extract(to: "out/") { progress in
    // progress.started / .finished / .index / .bytesWritten …
}
print(report.extracted, report.failed, report.aborted)
```

Both `read` and `extract` also come in `async` form; there, progress callbacks
are delivered on the main actor, so you can drive SwiftUI state from them
directly. Cancellation goes through a `CancellationToken`.

Failures throw `NewtuaError`, carrying a `code` (`.unknownFormat`,
`.encrypted`, `.wrongPassword`, `.corrupt`, `.pathTraversal`, …) and a
localized `message`. A Rust panic never crosses the boundary — it surfaces as
`.panic`.

A password belongs to an open archive, not to an extraction: on `.encrypted`,
ask the user and create a new `Archive(path:password:)`.

## Requirements

- **macOS 14+**, Swift 6 tools.
- An `Archive` instance is not thread-safe — one instance per thread or queue.
  The `async` methods serialize onto the package's own queue.

## Developing this package

The binary target normally points at a release asset. To work on the wrapper
itself, build the framework locally and switch the target to the local form:

```sh
tools/build-xcframework.sh          # fetches the published newtua-ffi crate
                                    # and builds Newtua.xcframework
# then in Package.swift:
#   .binaryTarget(name: "CNewtua", path: "Newtua.xcframework")
swift test
```

The script takes the crate version as its argument (`tools/build-xcframework.sh
0.2.0`) and needs a Rust toolchain plus Xcode. It builds from the crate
published on crates.io, never from a neighbouring checkout — the artefact must
correspond to a version anyone can inspect.

### Releasing

The archive attached to a release must be *the very archive* the checksum was
computed from. Rust builds are not reproducible byte-for-byte, so rebuilding
during a release job would yield a different checksum than the one recorded in
`Package.swift` and break the package for everyone. Hence the order:

1. `tools/build-xcframework.sh <ffi-version>` — prints the checksum
2. put that checksum and the release URL into `Package.swift`
3. commit, then create the release and upload **that** `Newtua.xcframework.zip`

## License

**LGPL-3.0-or-later.** The Swift wrapper and the engine it embeds both carry
it: the engine's legacy-format decoders are ported from **XADMaster** (The
Unarchiver) by Dag Ågren and contributors, LGPL from the start.

For an application this is workable: link the package, embed the framework, and
keep a license of your own choosing. What the LGPL asks in return is that users
can replace the library itself — which the dynamic framework used here already
allows.

- Full text: [`LICENSE`](LICENSE), incorporating the GNU GPL v3 in
  [`GPL-3.0.txt`](GPL-3.0.txt).
- Copyright and provenance: [`NOTICE`](NOTICE).

## Part of New The Unarchiver

One layer of **[New The Unarchiver](https://github.com/new-the-unarchiver)** —
a ground-up, cross-platform Rust reincarnation of The Unarchiver. This package
wraps [`newtua-ffi`](https://github.com/new-the-unarchiver/newtua-ffi), the C
ABI over the [`newtua-core`](https://github.com/new-the-unarchiver/newtua-core)
engine. The command line lives in
[`newtua-cli`](https://github.com/new-the-unarchiver/newtua-cli).
