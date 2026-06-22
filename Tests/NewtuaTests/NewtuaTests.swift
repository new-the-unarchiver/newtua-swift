import Foundation
import XCTest

@testable import Newtua

final class NewtuaTests: XCTestCase {
    /// Path to newtua-core's committed 7z fixture, relative to this file.
    private var fixture: String {
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }  // -> repo root
        return repo.appendingPathComponent("crates/newtua-core/tests/fixtures/hello.7z").path
    }

    func testOpenListRead() throws {
        let ar = try Archive(path: fixture)
        XCTAssertEqual(ar.count, 1)
        let entries = ar.entries()
        XCTAssertEqual(entries.first?.path, "a.txt")
        XCTAssertEqual(entries.first?.kind, "file")
        XCTAssertEqual(entries.first?.isEncrypted, false)
        XCTAssertEqual(try ar.read(0), Data("hello 7z".utf8))
    }

    func testExtract() throws {
        let ar = try Archive(path: fixture)
        let dir = NSTemporaryDirectory() + "newtua-swift-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        var sawStart = false
        let report = try ar.extract(to: dir, wrapper: false) { prog in
            if prog.started { sawStart = true }
            return true
        }
        XCTAssertEqual(report.extracted, 1)
        XCTAssertFalse(report.aborted)
        XCTAssertTrue(sawStart, "progress callback was never invoked")
        let content = try Data(contentsOf: URL(fileURLWithPath: dir + "/a.txt"))
        XCTAssertEqual(content, Data("hello 7z".utf8))
    }

    func testUnknownFormatThrows() throws {
        let bad = NSTemporaryDirectory() + "bad-\(UUID().uuidString).bin"
        try Data("not an archive at all".utf8).write(to: URL(fileURLWithPath: bad))
        defer { try? FileManager.default.removeItem(atPath: bad) }
        XCTAssertThrowsError(try Archive(path: bad))
    }

    func testVersion() {
        XCTAssertFalse(Newtua.version().isEmpty)
    }
}
