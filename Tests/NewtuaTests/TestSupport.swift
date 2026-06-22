import Foundation

/// Shared test scaffolding: fixture locations and temp-dir helpers.
enum TestSupport {
    /// Repository root, derived from this file's location.
    /// Layout: <repo>/bindings/swift/Tests/NewtuaTests/TestSupport.swift
    static func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    /// Path to a committed engine fixture by name.
    static func fixture(_ name: String) -> URL {
        repoRoot()
            .appendingPathComponent("crates/newtua-core/tests/fixtures")
            .appendingPathComponent(name)
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
