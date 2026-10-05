import Foundation
import SQLite3

/// SQLITE_TRANSIENT tells SQLite to copy a bound string immediately.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum CaptureStoreError: Error, Equatable {
    case sqlite(String)
}

/// Owns capture.db: the store TimesheetHelper reads in native mode.
/// The schema is a cross-language contract; see docs/capture-store-v1.sql.
final class CaptureStore {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ActivityCapture/capture.db")
    }

    private var db: OpaquePointer?

    init(url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        // Create the file 0600 before SQLite opens it. SQLite gives the -wal and
        // -shm files the same mode as the database file.
        if !fm.fileExists(atPath: url.path) {
            _ = fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard rc == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            sqlite3_close(handle)
            throw CaptureStoreError.sqlite("open \(url.path): \(message)")
        }
        db = handle
        sqlite3_busy_timeout(handle, 5000)
        try exec("PRAGMA journal_mode = WAL")
        try migrate()
    }

    deinit { close() }

    func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    // MARK: - Schema

    func schemaVersion() throws -> Int {
        let exists = try query("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'schema_meta'") { _ in true }
        guard !exists.isEmpty else { return 0 }
        let values = try query("SELECT value FROM schema_meta WHERE key = 'schema_version'") { columnText($0, 0) }
        return Int(values.first.flatMap { $0 } ?? "0") ?? 0
    }

    func journalMode() throws -> String {
        try query("PRAGMA journal_mode") { columnText($0, 0) ?? "" }.first ?? ""
    }

    private func migrate() throws {
        var version = try schemaVersion()
        while version < CaptureSchema.migrations.count {
            try transaction {
                try exec(CaptureSchema.migrations[version])
                version += 1
                try exec("INSERT OR REPLACE INTO schema_meta (key, value) VALUES ('schema_version', '\(version)')")
            }
        }
    }

    // MARK: - Enrichers

    /// Rewritten at each launch from the monitors the app runs, so TimesheetHelper
    /// can find extraction gaps without a hard-coded app list.
    func replaceEnrichers(_ enrichers: [String: String]) throws {
        try transaction {
            try exec("DELETE FROM enrichers")
            for (program, name) in enrichers.sorted(by: { $0.key < $1.key }) {
                try run("INSERT INTO enrichers (program, name) VALUES (?, ?)") { stmt in
                    bindText(stmt, 1, program)
                    bindText(stmt, 2, name)
                }
            }
        }
    }

    func enrichers() throws -> [String: String] {
        let rows = try query("SELECT program, name FROM enrichers") { (columnText($0, 0) ?? "", columnText($0, 1) ?? "") }
        return Dictionary(uniqueKeysWithValues: rows)
    }

    // MARK: - SQLite helpers

    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            try body()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(err)
            throw CaptureStoreError.sqlite(message)
        }
    }

    func run(_ sql: String, _ bind: (OpaquePointer) -> Void = { _ in }) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CaptureStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    func query<T>(_ sql: String, _ row: (OpaquePointer) -> T) throws -> [T] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { out.append(row(stmt)); continue }
            if rc == SQLITE_DONE { return out }
            throw CaptureStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw CaptureStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }
}

private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
    if let value {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    } else {
        sqlite3_bind_null(stmt, index)
    }
}

private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
    guard let text = sqlite3_column_text(stmt, index) else { return nil }
    return String(cString: text)
}
