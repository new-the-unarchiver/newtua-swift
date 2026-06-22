// swift-tools-version:5.9
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
    products: [
        .library(name: "Newtua", targets: ["Newtua"])
    ],
    targets: [
        .systemLibrary(name: "CNewtua", path: "Sources/CNewtua"),
        .target(
            name: "Newtua",
            dependencies: ["CNewtua"],
            linkerSettings: [
                // The Rust static library + its native deps (see
                // `cargo rustc -- --print native-static-libs`).
                .unsafeFlags(["-L\(cargoTargetDebug)", "-lnewtua_ffi"]),
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
