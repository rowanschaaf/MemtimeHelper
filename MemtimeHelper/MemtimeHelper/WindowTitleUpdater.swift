import Foundation
import SQLite3
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "WindowTitleUpdater")

/// SQLITE_TRANSIENT tells SQLite to copy the bound string immediately.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class WindowTitleUpdater {

    private var db: OpaquePointer?
    private var updateStmt: OpaquePointer?
    private var closeStmt: OpaquePointer?
    private var insertStmt: OpaquePointer?

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

        // IMPORTANT: every statement filters open rows to those started within
        // the last hour. Memtime's DB contains many orphan `end IS NULL` rows
        // from past crashes/quits going back years. Without a recency clause
        // we'd silently mutate ancient rows (e.g. an April 1st Outlook row
        // when polling today), corrupting historical data and producing
        // bogus long blocks in Memtime's UI.
        let recentOpenWindowSeconds: Int64 = 3600

        // Update title on the currently open row, if it's recent.
        let updateSQL = """
            UPDATE TTracking SET title = ?1
            WHERE id = (
                SELECT id FROM TTracking
                WHERE program = ?2 AND end IS NULL
                  AND start > strftime('%s','now') - \(recentOpenWindowSeconds)
                ORDER BY start DESC LIMIT 1
            )
            """
        // Close recent open rows by setting `end`. Ancient orphans are left
        // alone — they're not ours to clean up.
        let closeSQL = """
            UPDATE TTracking SET end = ?1
            WHERE program = ?2 AND end IS NULL
              AND start > strftime('%s','now') - \(recentOpenWindowSeconds)
            """
        // Insert a fresh open row, copying type/programPath from the most
        // recent existing row so Memtime treats it as a continuation segment.
        let insertSQL = """
            INSERT INTO TTracking (type, title, program, programPath, start, end)
            SELECT type, ?1, program, programPath, ?2, NULL
            FROM TTracking
            WHERE program = ?3
            ORDER BY start DESC LIMIT 1
            """

        var update: OpaquePointer?
        var close: OpaquePointer?
        var insert: OpaquePointer?
        guard sqlite3_prepare_v2(handle, updateSQL, -1, &update, nil) == SQLITE_OK,
              sqlite3_prepare_v2(handle, closeSQL, -1, &close, nil) == SQLITE_OK,
              sqlite3_prepare_v2(handle, insertSQL, -1, &insert, nil) == SQLITE_OK else {
            logger.error("Failed to prepare statements")
            sqlite3_finalize(update); sqlite3_finalize(close); sqlite3_finalize(insert)
            sqlite3_close(handle)
            return false
        }

        db = handle
        updateStmt = update
        closeStmt = close
        insertStmt = insert
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

    /// Closes the open `TTracking` row for the given app and inserts a new
    /// open row with the new title. Use this when the conversation pane
    /// changes mid-session so Memtime segments time per conversation.
    /// Falls back to a plain UPDATE if there's no template row to copy from
    /// (e.g. very first observation).
    @discardableResult
    func splitSegment(bundleID: String, newTitle: String) -> Bool {
        guard openIfNeeded(), let db, let closeS = closeStmt, let insertS = insertStmt else { return false }
        let now = Int64(Date().timeIntervalSince1970)

        // Wrap close+insert in a single write transaction so Memtime cannot
        // interleave its own INSERT between them. Without this, we routinely
        // ended up with two `end IS NULL` rows for the same program.
        guard runSQL(db, "BEGIN IMMEDIATE") else { return false }

        sqlite3_reset(closeS)
        sqlite3_bind_int64(closeS, 1, now)
        sqlite3_bind_text(closeS, 2, bundleID, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(closeS) == SQLITE_DONE else {
            logger.error("Failed to close open row(s)")
            _ = runSQL(db, "ROLLBACK")
            return false
        }
        let closedRows = sqlite3_changes(db)
        if closedRows == 0 {
            // No recent open row existed — Memtime isn't tracking this app
            // right now, so we must NOT insert one ourselves (would create a
            // phantom tracking block). Just commit the no-op and bail.
            _ = runSQL(db, "COMMIT")
            return false
        }

        sqlite3_reset(insertS)
        sqlite3_bind_text(insertS, 1, newTitle, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(insertS, 2, now)
        sqlite3_bind_text(insertS, 3, bundleID, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(insertS) == SQLITE_DONE else {
            logger.error("Failed to insert new segment row")
            _ = runSQL(db, "ROLLBACK")
            return false
        }
        let insertedRows = sqlite3_changes(db)

        guard runSQL(db, "COMMIT") else {
            _ = runSQL(db, "ROLLBACK")
            return false
        }

        if insertedRows == 0 {
            // No template row existed — fall back to a plain UPDATE so we at
            // least set the title on whatever Memtime created.
            return update(bundleID: bundleID, title: newTitle)
        }
        return true
    }

    private func runSQL(_ handle: OpaquePointer, _ sql: String) -> Bool {
        if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK {
            logger.error("SQL '\(sql, privacy: .public)' failed: \(String(cString: sqlite3_errmsg(handle)), privacy: .public)")
            return false
        }
        return true
    }

    /// Closes the database connection.
    func close() {
        for stmtRef in [updateStmt, closeStmt, insertStmt] {
            if let stmt = stmtRef { sqlite3_finalize(stmt) }
        }
        updateStmt = nil
        closeStmt = nil
        insertStmt = nil
        if let handle = db {
            sqlite3_close(handle)
            db = nil
        }
    }

    deinit {
        close()
    }
}
