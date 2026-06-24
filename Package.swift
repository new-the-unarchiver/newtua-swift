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
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Newtua", targets: ["Newtua"])
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
