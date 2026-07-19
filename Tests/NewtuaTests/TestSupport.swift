import Foundation

/// Shared test scaffolding: fixture locations and temp-dir helpers.
enum TestSupport {
    /// Path to a committed fixture by name.
    ///
    /// The fixtures travel with this package rather than being read out of the
    /// engine's own test tree: the package is distributed on its own, and the
    /// published `newtua-core` crate excludes its tests entirely.
    static func fixture(_ name: String) -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
        else {
            fatalError("missing test fixture: \(name)")
        }
        return url
    }

    /// A fresh temporary directory the caller owns. Caller is responsible for
    /// deletion (use `defer { try? FileManager.default.removeItem(at: dir) }`).
    static func makeTempDir(prefix: String = "newtua-test") throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
