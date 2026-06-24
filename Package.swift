// swift-tools-version:6.0
import PackageDescription

// CNewtua is provided as a prebuilt XCFramework (a release-optimized
// aarch64-apple-darwin dynamic library wrapped in a versioned macOS
// framework). Build/regenerate it before `swift build`/`swift test`:
//
//     apps/macos/tools/build-newtua-xcframework.sh
//
// The script is also wired into the macOS Xcode app's "Run Script" build
// phase, so the XCFramework is rebuilt automatically there.
//
// The framework's install_name is `@rpath/CNewtua.framework/Versions/A/CNewtua`,
// so the linker handles `-framework CNewtua -F<path>` automatically; system
// dependencies (CoreFoundation, libc++, libSystem, liblzma, libiconv, libbz2)
// are baked into the dylib's LC_LOAD_DYLIB and propagate to consumers without
// any extra `linkerSettings` here.
let package = Package(
    name: "Newtua",
    // The package floor is .v14 for SwiftPM tooling compatibility; the real
    // floor (26.0) is set by the consuming Xcode target and matches what
    // CNewtua.framework was built with. `swift build` here emits a benign
    // version-skew warning that does not surface in the Xcode build.
    platforms: [.macOS(.v14)],
    products: [
        // Dynamic so Xcode shows the "Embed" dropdown for the consumer
        // target and so a single .framework is embedded into the .app once,
        // shared between the app and the Quick Look extension via @rpath.
        // Static (the SwiftPM default) gets duplicated into every linker,
        // which defeats the whole point of using an XCFramework here.
        .library(name: "Newtua", type: .dynamic, targets: ["Newtua"])
    ],
    targets: [
        .binaryTarget(name: "CNewtua", path: "Newtua.xcframework"),
        .target(
            name: "Newtua",
            dependencies: ["CNewtua"]
        ),
        .testTarget(name: "NewtuaTests", dependencies: ["Newtua"]),
    ]
)
