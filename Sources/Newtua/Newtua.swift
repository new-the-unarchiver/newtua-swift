// Idiomatic Swift wrapper over the newtua C ABI (CNewtua / newtua.h).
// The engine logic lives in newtua-core; this layer only marshals types.

import CNewtua
import Foundation

/// An error reported by the newtua engine.
public struct NewtuaError: Error, CustomStringConvertible {
    public let code: NtuaStatus
    public let message: String
    public var description: String { message }
}

/// One archive entry's metadata.
public struct Entry {
    public let path: String
    public let kind: String  // "file" | "dir" | "symlink"
    public let size: UInt64
    public let isEncrypted: Bool
    public let mode: UInt32?
    public let mtime: Int64?
}

/// Result of an extraction.
public struct ExtractReport {
    public let extracted: UInt64
    public let failed: UInt64
    public let aborted: Bool
}

/// crate version of the underlying engine.
public func version() -> String {
    String(cString: ntua_version())
}

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

private final class ProgressBox {
    let cb: (NtuaProgress) -> Bool
    init(_ cb: @escaping (NtuaProgress) -> Bool) { self.cb = cb }
}

/// Bridge a Swift progress closure to the C callback + context pair.
private func withProgress<R>(
    _ progress: ((NtuaProgress) -> Bool)?,
    _ body: (NtuaProgressFn?, UnsafeMutableRawPointer?) -> R
) -> R {
    guard let progress else { return body(nil, nil) }
    let box = ProgressBox(progress)
    let ctx = Unmanaged.passRetained(box).toOpaque()
    defer { Unmanaged<ProgressBox>.fromOpaque(ctx).release() }
    let trampoline: NtuaProgressFn = { ctx, prog in
        guard let ctx, let prog else { return 0 }
        let box = Unmanaged<ProgressBox>.fromOpaque(ctx).takeUnretainedValue()
        return box.cb(prog.pointee) ? 0 : 1  // false -> nonzero -> abort
    }
    return body(trampoline, ctx)
}

/// An open archive. Iterate `entries()` or call `read`/`extract`.
public final class Archive {
    private let handle: OpaquePointer

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
            throw NewtuaError(code: status, message: message(for: status))
        }
        self.handle = h
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
        let kind: String
        if e.kind == NtuaEntryKind_Dir {
            kind = "dir"
        } else if e.kind == NtuaEntryKind_Symlink {
            kind = "symlink"
        } else {
            kind = "file"
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

    /// Read one entry's bytes.
    public func read(_ index: Int) throws -> Data {
        var buf: UnsafeMutablePointer<UInt8>?
        var len: UInt = 0
        let status = ntua_read_entry(handle, UInt(index), &buf, &len)
        guard status == NtuaStatus_Ok, let buf else {
            throw NewtuaError(code: status, message: message(for: status))
        }
        defer { ntua_buffer_free(buf, len) }
        return Data(bytes: buf, count: Int(len))
    }

    /// Extract entries to `dest`. `progress` returns false to cancel.
    @discardableResult
    public func extract(
        to dest: String,
        selection: [Int]? = nil,
        wrapper: Bool = true,
        strict: Bool = false,
        preserve: Bool = true,
        progress: ((NtuaProgress) -> Bool)? = nil
    ) throws -> ExtractReport {
        var report = NtuaReport()
        let status: NtuaStatus = dest.withCString { cdest in
            withProgress(progress) { cb, ctx in
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
            throw NewtuaError(code: status, message: message(for: status))
        }
        return ExtractReport(
            extracted: report.extracted,
            failed: report.failed,
            aborted: report.aborted
        )
    }
}
