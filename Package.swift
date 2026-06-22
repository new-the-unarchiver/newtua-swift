// swift-tools-version:6.0
import Foundation
import PackageDescription

// Absolute path to the Cargo target dir (where libnewtua_ffi.a lives), computed
// from this manifest's location so `swift build`/`swift test` link regardless of
// the working directory. Build the static lib first: `cargo build -p newtua-ffi`.
let pkgDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let cargoTargetDebug = pkgDir
    .appendingPathComponent("../../target/debug")
    .standardizedFileURL.path

let package = Package(
    name: "Newtua",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Newtua", targets: ["Newtua"])
    ],
    targets: [
        .systemLibrary(name: "CNewtua", path: "Sources/CNewtua"),
        .target(
            name: "Newtua",
            dependencies: ["CNewtua"],
            linkerSettings: [
                // Link the Rust *static* library by full path. Do NOT use
                // `-L<dir> -lnewtua_ffi`: cargo also emits libnewtua_ffi.dylib in
                // the same dir, and the linker prefers the .dylib over the .a —
                // the binary then links dynamically and dyld fails to load it at
                // runtime (wrong baked-in path + Team ID / hardened-runtime
                // mismatch). Giving the .a path forces static linking. Native
                // deps follow (see `cargo rustc -- --print native-static-libs`).
                .unsafeFlags(["\(cargoTargetDebug)/libnewtua_ffi.a"]),
                .linkedFramework("CoreFoundation"),
                .linkedLibrary("c++"),
                .linkedLibrary("pthread"),
                .linkedLibrary("lzma"),
                .linkedLibrary("iconv"),
                .linkedLibrary("bz2"),
            ]
        ),
        .testTarget(name: "NewtuaTests", dependencies: ["Newtua"]),
    ]
)
