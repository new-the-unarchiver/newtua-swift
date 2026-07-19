// swift-tools-version:6.0
import PackageDescription

// CNewtua is the newtua C ABI, shipped as a prebuilt XCFramework so that using
// this package requires no Rust toolchain. The artefact is built from the
// published `newtua-ffi` crate by tools/build-xcframework.sh and attached to
// this repository's own releases.
//
// The framework's install_name is `@rpath/CNewtua.framework/Versions/A/CNewtua`,
// so the linker resolves it automatically; system dependencies (CoreFoundation,
// libc++, libSystem, liblzma, libiconv, libbz2) are baked into the dylib's
// LC_LOAD_DYLIB and propagate to consumers without extra `linkerSettings`.
let package = Package(
    name: "Newtua",
    // Matches MACOSX_DEPLOYMENT_TARGET in tools/build-xcframework.sh: the
    // framework cannot be loaded by anything older than it was built for.
    platforms: [.macOS(.v14)],
    products: [
        // Dynamic so a consuming Xcode target gets the "Embed" dropdown, and a
        // single framework is embedded into the .app once, shared with any app
        // extension through @rpath. A static product would be duplicated into
        // every linker, which defeats the point of an XCFramework.
        .library(name: "Newtua", type: .dynamic, targets: ["Newtua"])
    ],
    targets: [
        // Development build: run tools/build-xcframework.sh first. Released
        // tags carry the .binaryTarget(url:checksum:) form instead.
        .binaryTarget(name: "CNewtua", path: "Newtua.xcframework"),
        .target(name: "Newtua", dependencies: ["CNewtua"]),
        .testTarget(
            name: "NewtuaTests",
            dependencies: ["Newtua"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
