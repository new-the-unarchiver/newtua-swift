import Foundation
import Testing
import os.lock

@testable import Newtua
import CNewtua

/// Stage 0 TDD: ErrorCode, Progress, CancellationToken, async API.
/// Tests fail until the new public types and async wrappers exist.
@Suite("Stage 0 — Newtua wrapper modernization")
struct Stage0Tests {

    // MARK: - ErrorCode mapping

    @Test("ErrorCode covers every non-Ok NtuaStatus value")
    func errorCode_mapsAllNtuaStatusValues() {
        let pairs: [(NtuaStatus, ErrorCode)] = [
            (NtuaStatus_Io, .io),
            (NtuaStatus_UnknownFormat, .unknownFormat),
            (NtuaStatus_Unsupported, .unsupported),
            (NtuaStatus_Encrypted, .encrypted),
            (NtuaStatus_WrongPassword, .wrongPassword),
            (NtuaStatus_Corrupt, .corrupt),
            (NtuaStatus_PathTraversal, .pathTraversal),
            (NtuaStatus_MissingVolume, .missingVolume),
            (NtuaStatus_InvalidIndex, .invalidIndex),
            (NtuaStatus_NullArg, .nullArg),
            (NtuaStatus_Utf8, .utf8),
            (NtuaStatus_Panic, .panic),
        ]
        for (status, expected) in pairs {
            #expect(ErrorCode(status) == expected, "status raw=\(status.rawValue)")
        }
        #expect(ErrorCode(NtuaStatus_Ok) == nil)
    }

    @Test("NewtuaError.code is Swift ErrorCode, not the C type")
    func newtuaError_exposesSwiftErrorCode() throws {
        let bogus = NSTemporaryDirectory() + "stage0-bogus-\(UUID().uuidString).bin"
        try Data("not an archive".utf8).write(to: URL(fileURLWithPath: bogus))
        defer { try? FileManager.default.removeItem(atPath: bogus) }

        do {
            _ = try Archive(path: bogus)
            Issue.record("expected Archive(path:) to throw on non-archive input")
        } catch let e as NewtuaError {
            let code: ErrorCode = e.code
            #expect(code == .unknownFormat || code == .io || code == .corrupt)
        }
    }

    // MARK: - Async extract

    @Test("async extract succeeds on the hello.7z fixture")
    func extract_async_succeedsOnFixture() async throws {
        let ar = try Archive(path: TestSupport.fixture("hello.7z").path)
        let dir = try TestSupport.makeTempDir(prefix: "newtua-stage0")
        defer { try? FileManager.default.removeItem(at: dir) }

        let report = try await ar.extract(to: dir.path, wrapper: false)
        #expect(report.extracted == 1)
        #expect(report.failed == 0)
        #expect(report.aborted == false)
        let written = try Data(contentsOf: dir.appendingPathComponent("a.txt"))
        #expect(written == Data("hello 7z".utf8))
    }

    // MARK: - Cancellation

    @Test("CancellationToken triggered from progress aborts extraction")
    func extract_async_cancellationStopsMidWay() async throws {
        let ar = try Archive(path: TestSupport.fixture("multi.7z").path)
        let dir = try TestSupport.makeTempDir(prefix: "newtua-stage0")
        defer { try? FileManager.default.removeItem(at: dir) }

        let token = CancellationToken()
        let report = try await ar.extract(
            to: dir.path,
            wrapper: false,
            cancellation: token
        ) { p in
            if p.started { token.cancel() }
        }
        #expect(report.aborted == true)
    }

    // MARK: - Main-actor hop for progress

    @Test("async extract delivers progress on the main actor")
    func progressCallback_isOnMainActor() async throws {
        let ar = try Archive(path: TestSupport.fixture("hello.7z").path)
        let dir = try TestSupport.makeTempDir(prefix: "newtua-stage0")
        defer { try? FileManager.default.removeItem(at: dir) }

        let state = OSAllocatedUnfairLock<(wasAlwaysMain: Bool, calls: Int)>(
            initialState: (wasAlwaysMain: true, calls: 0)
        )

        _ = try await ar.extract(to: dir.path, wrapper: false) { _ in
            let onMain = Thread.isMainThread
            state.withLock { s in
                s.wasAlwaysMain = s.wasAlwaysMain && onMain
                s.calls += 1
            }
        }

        let (wasAlwaysMain, calls) = state.withLock { ($0.wasAlwaysMain, $0.calls) }
        #expect(calls > 0, "progress callback was never invoked")
        #expect(wasAlwaysMain, "progress callback fired off the main thread")
    }
}
