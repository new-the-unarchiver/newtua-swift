// Idiomatic Swift wrapper over the newtua C ABI (CNewtua / newtua.h).
// The engine logic lives in newtua-core; this layer only marshals types.
// CNewtua is an implementation detail — apps should `import Newtua` only.

import CNewtua
import Foundation
import os.lock

// MARK: - Error code

/// A Swift-native error code for newtua engine failures.
/// One case per non-Ok NtuaStatus. Unknown future codes map to `.panic`.
public enum ErrorCode: Sendable, Equatable {
    case io
    case unknownFormat
    case unsupported
    case encrypted
    case wrongPassword
    case corrupt
    case pathTraversal
    case missingVolume
    case invalidIndex
    case nullArg
    case utf8
    case panic

    /// Map a C status to a Swift case. `Ok` returns nil — it is not an error.
    /// Internal so app code never needs `import CNewtua` to construct one.
    init?(_ status: NtuaStatus) {
        switch status {
        case NtuaStatus_Ok: return nil
        case NtuaStatus_Io: self = .io
        case NtuaStatus_UnknownFormat: self = .unknownFormat
        case NtuaStatus_Unsupported: self = .unsupported
        case NtuaStatus_Encrypted: self = .encrypted
        case NtuaStatus_WrongPassword: self = .wrongPassword
        case NtuaStatus_Corrupt: self = .corrupt
        case NtuaStatus_PathTraversal: self = .pathTraversal
        case NtuaStatus_MissingVolume: self = .missingVolume
        case NtuaStatus_InvalidIndex: self = .invalidIndex
        case NtuaStatus_NullArg: self = .nullArg
        case NtuaStatus_Utf8: self = .utf8
        case NtuaStatus_Panic: self = .panic
        default: self = .panic
        }
    }
}

/// An error reported by the newtua engine.
public struct NewtuaError: Error, CustomStringConvertible, Sendable, Equatable {
    public let code: ErrorCode
    public let message: String
    public var description: String { message }
}

// MARK: - Entry

/// Kind of an archive entry.
public enum EntryKind: Sendable, Equatable {
    case file
    case dir
    case symlink
}

/// One archive entry's metadata.
public struct Entry: Sendable {
    public let path: String
    public let kind: EntryKind
    public let size: UInt64
    public let isEncrypted: Bool
    public let mode: UInt32?
    public let mtime: Int64?
}

// MARK: - Progress

/// A snapshot of extraction progress, delivered to the progress callback.
public struct Progress: Sendable {
    public let index: Int
    public let path: String?
    public let bytesWritten: UInt64
    public let entrySize: UInt64
    public let started: Bool
    public let finished: Bool

    fileprivate init(_ raw: NtuaProgress) {
        self.index = Int(raw.index)
        self.path = raw.path.map { String(cString: $0) }
        self.bytesWritten = raw.bytes_written
        self.entrySize = raw.entry_size
        self.started = raw.started
        self.finished = raw.finished
    }
}

// MARK: - Cancellation

/// Cooperative cancellation handle for `extract`. Callers may invoke `cancel()`
/// from any thread; the engine checks it on the next progress tick.
public final class CancellationToken: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<Bool>(initialState: false)

    public init() {}

    public var isCancelled: Bool { state.withLock { $0 } }

    public func cancel() { state.withLock { $0 = true } }
}

// MARK: - ExtractReport

/// Result of an extraction.
public struct ExtractReport: Sendable, Equatable {
    public let extracted: UInt64
    public let failed: UInt64
    public let aborted: Bool

    public init(extracted: UInt64, failed: UInt64, aborted: Bool) {
        self.extracted = extracted
        self.failed = failed
        self.aborted = aborted
    }
}

// MARK: - Version

/// Crate version of the underlying engine.
public func version() -> String {
    String(cString: ntua_version())
}

// MARK: - Internal helpers

private func message(for status: NtuaStatus, lang: String? = nil) -> String {
    let cmsg = withOptionalCString(lang) { ntua_error_message(status, $0) }
    guard let cmsg else { return "newtua error" }
    defer { ntua_string_free(cmsg) }
    return String(cString: cmsg)
}

private func withOptionalCString<R>(_ s: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
    guard let s else { return body(nil) }
    return s.withCString { body($0) }
}

private func withSelection<R>(_ sel: [Int]?, _ body: (UnsafePointer<UInt>?, UInt) -> R) -> R {
    guard let sel else { return body(nil, 0) }
    let u = sel.map { UInt($0) }
    return u.withUnsafeBufferPointer { body($0.baseAddress, UInt($0.count)) }
}

/// Throw a `NewtuaError` matching the given non-Ok status. Centralises the
/// status → ErrorCode mapping + localized message lookup.
private func throwNewtuaError(_ status: NtuaStatus) throws -> Never {
    let code = ErrorCode(status) ?? .panic
    throw NewtuaError(code: code, message: message(for: status))
}

/// Boxed payload for the C progress callback. Holds the user's Swift closure,
/// the optional cancellation token, and a flag controlling main-actor hopping.
private final class ProgressBox {
    let callback: (@Sendable (Progress) -> Void)?
    let token: CancellationToken?
    let hopToMain: Bool
    init(
        callback: (@Sendable (Progress) -> Void)?,
        token: CancellationToken?,
        hopToMain: Bool
    ) {
        self.callback = callback
        self.token = token
        self.hopToMain = hopToMain
    }
}

/// Bridge a Swift progress closure to the C callback + context pair.
/// Returns nonzero from the trampoline to signal abort.
private func withProgress<R>(
    callback: (@Sendable (Progress) -> Void)?,
    token: CancellationToken?,
    hopToMain: Bool,
    _ body: (NtuaProgressFn?, UnsafeMutableRawPointer?) -> R
) -> R {
    if callback == nil && token == nil {
        return body(nil, nil)
    }
    let box = ProgressBox(callback: callback, token: token, hopToMain: hopToMain)
    let ctx = Unmanaged.passRetained(box).toOpaque()
    defer { Unmanaged<ProgressBox>.fromOpaque(ctx).release() }
    let trampoline: NtuaProgressFn = { ctx, prog in
        guard let ctx, let prog else { return 0 }
        let box = Unmanaged<ProgressBox>.fromOpaque(ctx).takeUnretainedValue()
        if let token = box.token, token.isCancelled {
            return 1
        }
        guard let callback = box.callback else { return 0 }
        let swiftProg = Progress(prog.pointee)
        if box.hopToMain {
            let token = box.token
            DispatchQueue.main.async {
                // Suppress UI-bound progress if the user cancelled while this
                // hop was in flight.
                if let token, token.isCancelled { return }
                callback(swiftProg)
            }
        } else {
            callback(swiftProg)
        }
        return 0
    }
    return body(trampoline, ctx)
}

// MARK: - Archive

/// An open archive. Iterate `entries()` or call `read`/`extract`.
///
/// `Archive` is NOT thread-safe: each instance owns a single-threaded engine
/// reader. Caller contract: never invoke methods on one `Archive` from two
/// threads concurrently. Sync methods block the caller's thread; async methods
/// serialize internally on a private dispatch queue. Use one queue (or `Task`)
/// per `Archive`.
///
/// Sendable is `@unchecked` because the engine pointer is an opaque C handle
/// that the type system can't reason about — Swift can't prove the contract
/// above, so we assert it manually.
public final class Archive: @unchecked Sendable {
    private let handle: OpaquePointer
    private let queue: DispatchQueue

    /// Open an archive for listing and extraction.
    public init(path: String, password: String? = nil, encoding: String? = nil) throws {
        var h: OpaquePointer?
        let status = path.withCString { cpath in
            withOptionalCString(password) { pw in
                withOptionalCString(encoding) { enc in
                    var opts = NtuaOpenOptions(password: pw, encoding: enc)
                    return ntua_open(cpath, &opts, &h)
                }
            }
        }
        guard status == NtuaStatus_Ok, let h else {
            try throwNewtuaError(status)
        }
        self.handle = h
        self.queue = DispatchQueue(label: "newtua.archive.\(UUID().uuidString)")
    }

    deinit { ntua_free(handle) }

    /// Number of entries.
    public var count: Int { Int(ntua_entry_count(handle)) }

    /// All entries.
    public func entries() -> [Entry] {
        (0..<count).compactMap { entry(at: $0) }
    }

    /// One entry's metadata by index.
    public func entry(at index: Int) -> Entry? {
        var e = NtuaEntry()
        guard ntua_entry_at(handle, UInt(index), &e) == NtuaStatus_Ok else { return nil }
        let kind: EntryKind
        if e.kind == NtuaEntryKind_Dir {
            kind = .dir
        } else if e.kind == NtuaEntryKind_Symlink {
            kind = .symlink
        } else {
            kind = .file
        }
        return Entry(
            path: String(cString: e.path),
            kind: kind,
            size: e.size,
            isEncrypted: e.is_encrypted,
            mode: e.has_mode ? e.mode : nil,
            mtime: e.has_mtime ? e.mtime_unix : nil
        )
    }

    /// Read one entry's bytes synchronously. Blocks the calling thread.
    public func read(_ index: Int) throws -> Data {
        var buf: UnsafeMutablePointer<UInt8>?
        var len: UInt = 0
        let status = ntua_read_entry(handle, UInt(index), &buf, &len)
        guard status == NtuaStatus_Ok, let buf else {
            try throwNewtuaError(status)
        }
        defer { ntua_buffer_free(buf, len) }
        return Data(bytes: buf, count: Int(len))
    }

    /// Read one entry's bytes off the main thread.
    public func read(_ index: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            queue.async {
                do {
                    let data: Data = try self.read(index)
                    cont.resume(returning: data)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Extract entries to `dest` synchronously. The progress callback runs on the
    /// engine's thread (not the main thread). Pass a `CancellationToken` for
    /// cooperative cancellation.
    @discardableResult
    public func extract(
        to dest: String,
        selection: [Int]? = nil,
        wrapper: Bool = true,
        strict: Bool = false,
        preserve: Bool = true,
        cancellation: CancellationToken? = nil,
        progress: (@Sendable (Progress) -> Void)? = nil
    ) throws -> ExtractReport {
        try _extract(
            to: dest, selection: selection, wrapper: wrapper, strict: strict,
            preserve: preserve, cancellation: cancellation,
            progress: progress, hopProgressToMain: false
        )
    }

    /// Extract entries to `dest` off the main thread. The progress callback is
    /// delivered on the main actor automatically.
    @discardableResult
    public func extract(
        to dest: String,
        selection: [Int]? = nil,
        wrapper: Bool = true,
        strict: Bool = false,
        preserve: Bool = true,
        cancellation: CancellationToken? = nil,
        progress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> ExtractReport {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ExtractReport, Error>) in
            queue.async {
                do {
                    let report = try self._extract(
                        to: dest, selection: selection, wrapper: wrapper,
                        strict: strict, preserve: preserve,
                        cancellation: cancellation,
                        progress: progress, hopProgressToMain: true
                    )
                    cont.resume(returning: report)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func _extract(
        to dest: String,
        selection: [Int]?,
        wrapper: Bool,
        strict: Bool,
        preserve: Bool,
        cancellation: CancellationToken?,
        progress: (@Sendable (Progress) -> Void)?,
        hopProgressToMain: Bool
    ) throws -> ExtractReport {
        var report = NtuaReport()
        let status: NtuaStatus = dest.withCString { cdest in
            withProgress(callback: progress, token: cancellation, hopToMain: hopProgressToMain) { cb, ctx in
                withSelection(selection) { selPtr, selLen in
                    var opts = NtuaExtractOptions(
                        dest: cdest,
                        wrapper: wrapper,
                        strict: strict,
                        preserve: preserve,
                        selection: selPtr,
                        selection_len: selLen
                    )
                    return ntua_extract(handle, &opts, cb, ctx, &report)
                }
            }
        }
        guard status == NtuaStatus_Ok else {
            try throwNewtuaError(status)
        }
        return ExtractReport(
            extracted: report.extracted,
            failed: report.failed,
            aborted: report.aborted
        )
    }
}
