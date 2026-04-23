import Foundation
import SQLite3
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "WindowTitleUpdater")

/// SQLITE_TRANSIENT tells SQLite to copy the bound string immediately.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class WindowTitleUpdater {

    private var db: OpaquePointer?
    private var updateStmt: OpaquePointer?

    /// The path to Memtime's SQLite database.
    private static let dbPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/memtime/user/core.db"
    }()

    // MARK: - Database

    /// Opens the Memtime database and prepares the update statement.
    private func openIfNeeded() -> Bool {
        if db != nil { return true }

        let path = Self.dbPath
        guard FileManager.default.fileExists(atPath: path) else {
            logger.error("Memtime DB not found at \(path, privacy: .public)")
            return false
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_WAL
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            logger.error("Failed to open Memtime DB: \(rc)")
            return false
        }

        sqlite3_busy_timeout(handle, 1000)

        let sql = """
            UPDATE TTracking SET title = ?1
            WHERE id = (
                SELECT id FROM TTracking
                WHERE program = ?2
                  AND end IS NULL
                ORDER BY start DESC
                LIMIT 1
            )
            """

        var stmt: OpaquePointer?
        let prepRc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard prepRc == SQLITE_OK else {
            logger.error("Failed to prepare statement: \(prepRc)")
            sqlite3_close(handle)
            return false
        }

        db = handle
        updateStmt = stmt
        logger.notice("Memtime DB opened successfully")
        return true
    }

    // MARK: - Applying the Title

    /// Updates the title of the most recent open entry for the given app in Memtime's database.
    @discardableResult
    func update(bundleID: String, title: String) -> Bool {
        guard openIfNeeded(), let stmt = updateStmt else { return false }

        sqlite3_reset(stmt)
        sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, bundleID, -1, SQLITE_TRANSIENT)

        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else {
            logger.error("DB update failed: \(rc)")
            close()
            return false
        }

        return sqlite3_changes(db) > 0
    }

    /// Closes the database connection.
    func close() {
        if let stmt = updateStmt {
            sqlite3_finalize(stmt)
            updateStmt = nil
        }
        if let handle = db {
            sqlite3_close(handle)
            db = nil
        }
    }

    deinit {
        close()
    }
}
