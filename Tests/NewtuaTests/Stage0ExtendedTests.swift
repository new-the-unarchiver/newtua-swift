import Foundation
import Testing
import os.lock

@testable import Newtua
import CNewtua

/// Stage 0 extended pack: unit, integration, end-to-end, and edge cases.
@Suite("Stage 0 — extended (unit/integration/e2e/edge)")
struct Stage0ExtendedTests {

    // MARK: - Unit

    @Test("ErrorCode falls back to .panic for an unknown raw status value")
    func errorCode_unknownRawMapsToPanic() {
        let synthetic = NtuaStatus(rawValue: 9_999)
        #expect(ErrorCode(synthetic) == .panic)
    }

    @Test("CancellationToken starts uncancelled and becomes cancelled once")
    func cancellationToken_lifecycle() {
        let t = CancellationToken()
        #expect(t.isCancelled == false)
        t.cancel()
        #expect(t.isCancelled == true)
        t.cancel()
        #expect(t.isCancelled == true)
    }

    @Test("version() returns a non-empty string")
    func version_isNonEmpty() {
        #expect(Newtua.version().isEmpty == false)
    }

    @Test("Sync read returns the exact stored bytes")
    func read_sync_returnsCorrectBytes() throws {
        let ar = try Archive(path: TestSupport.fixture("hello.7z").path)
        let data = try ar.read(0)
        #expect(data == Data("hello 7z".utf8))
    }

    @Test("Async read returns the exact stored bytes")
    func read_async_returnsCorrectBytes() async throws {
        let ar = try Archive(path: TestSupport.fixture("hello.7z").path)
        let data: Data = try await ar.read(0)
        #expect(data == Data("hello 7z".utf8))
    }

    // MARK: - Integration

    @Test("RAR archive opens, lists, and extracts via sync API")
    func rar_opensListsExtracts() throws {
        let ar = try Archive(path: TestSupport.fixture("hello.rar").path)
        #expect(ar.count >= 1)
        #expect(ar.entry(at: 0)?.path == "a.txt")
        let dir = try TestSupport.makeTempDir(prefix: "newtua-stage0x")
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = try ar.extract(to: dir.path, wrapper: false)
        #expect(report.extracted >= 1)
        #expect(report.failed == 0)
        let written = try Data(contentsOf: dir.appendingPathComponent("a.txt"))
        #expect(written == Data("hello rar".utf8))
    }

    @Test("Multi-entry 7z fires started for every entry and extracts them all")
    func multiEntry_extractsAll_andFiresStartedPerEntry() async throws {
        let ar = try Archive(path: TestSupport.fixture("multi.7z").path)
        let total = ar.count
        #expect(total >= 2)
        let dir = try TestSupport.makeTempDir(prefix: "newtua-stage0x")
        defer { try? FileManager.default.removeItem(at: dir) }

        let startedCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let report = try await ar.extract(to: dir.path, wrapper: false) { p in
            if p.started { startedCount.withLock { $0 += 1 } }
        }
        #expect(report.extracted == UInt64(total))
        #expect(report.failed == 0)
        #expect(startedCount.withLock { $0 } == total)
    }

    @Test("Symlink fixture exposes .symlink kind")
    func symlink_listed_with_symlinkKind() throws {
        let ar = try Archive(path: TestSupport.fixture("symlink.7z").path)
        let kinds = ar.entries().map(\.kind)
        #expect(kinds.contains(.symlink), "expected at least one symlink entry, got \(kinds)")
    }

    // MARK: - E2E

    @Test("Full cycle on hello.7z: open → entries → read → extract → on-disk content")
    func e2e_openEntriesReadExtract() async throws {
        let ar = try Archive(path: TestSupport.fixture("hello.7z").path)
        let entries = ar.entries()
        #expect(entries.count == 1)
        #expect(entries[0].path == "a.txt")
        #expect(entries[0].kind == .file)
        #expect(entries[0].size == 8)

        let blob: Data = try await ar.read(0)
        #expect(blob == Data("hello 7z".utf8))

        let dir = try TestSupport.makeTempDir(prefix: "newtua-stage0x")
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = try await ar.extract(to: dir.path, wrapper: false)
        #expect(report.extracted == 1)
        #expect(report.aborted == false)
        let onDisk = try Data(contentsOf: dir.appendingPathComponent("a.txt"))
        #expect(onDisk == blob)
    }

    // MARK: - Edge

    @Test("Opening a non-existent path raises NewtuaError")
    func nonexistentPath_throws() {
        let bogus = "/var/empty/definitely-not-here-\(UUID().uuidString).zip"
        #expect(throws: NewtuaError.self) {
            _ = try Archive(path: bogus)
        }
    }

    @Test("Header-encrypted 7z opened without password throws .encrypted or .wrongPassword")
    func encryptedHeader_throws_withoutPassword() {
        do {
            _ = try Archive(path: TestSupport.fixture("secret.7z").path)
            Issue.record("expected open() to throw on header-encrypted archive without password")
        } catch let e as NewtuaError {
            #expect(e.code == .encrypted || e.code == .wrongPassword)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("Wrong password on header-encrypted 7z throws .wrongPassword (or .encrypted)")
    func wrongPassword_throws() {
        do {
            _ = try Archive(path: TestSupport.fixture("secret.7z").path, password: "definitely-not-pw")
            Issue.record("expected wrong-password open to throw")
        } catch let e as NewtuaError {
            #expect(e.code == .wrongPassword || e.code == .encrypted)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("Correct password opens header-encrypted 7z and lets us extract it")
    func correctPassword_opens_andExtracts() async throws {
        let ar = try Archive(path: TestSupport.fixture("secret.7z").path, password: "pw")
        #expect(ar.count >= 1)
        let dir = try TestSupport.makeTempDir(prefix: "newtua-stage0x")
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = try await ar.extract(to: dir.path, wrapper: false)
        #expect(report.failed == 0)
        #expect(report.extracted >= 1)
    }

    @Test("entries() can be called repeatedly without crashing")
    func entries_repeatedCalls_areStable() throws {
        let ar = try Archive(path: TestSupport.fixture("multi.7z").path)
        let a = ar.entries()
        let b = ar.entries()
        let c = ar.entries()
        #expect(a.map(\.path) == b.map(\.path))
        #expect(b.map(\.path) == c.map(\.path))
        #expect(!a.isEmpty)
    }

    @Test("Two independent archives can be read concurrently")
    func twoArchives_inParallel() async throws {
        async let lhs: Data = {
            let ar = try Archive(path: TestSupport.fixture("hello.7z").path)
            return try await ar.read(0)
        }()
        async let rhs: Data = {
            let ar = try Archive(path: TestSupport.fixture("hello.rar").path)
            return try await ar.read(0)
        }()
        let (a, b) = try await (lhs, rhs)
        #expect(a == Data("hello 7z".utf8))
        #expect(b == Data("hello rar".utf8))
    }
}
