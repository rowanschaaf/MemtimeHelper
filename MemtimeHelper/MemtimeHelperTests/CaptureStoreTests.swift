import XCTest
import SQLite3
@testable import MemtimeHelper

final class CaptureStoreTests: XCTestCase {
    private var dir: URL!
    private var url: URL { dir.appendingPathComponent("capture.db") }

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func test_open_createsStoreAtVersion1() throws {
        let store = try CaptureStore(url: url)
        defer { store.close() }
        XCTAssertEqual(try store.schemaVersion(), 1)
    }

    func test_open_twice_keepsVersionAndData() throws {
        let first = try CaptureStore(url: url)
        try first.replaceEnrichers(["com.example.app": "example"])
        first.close()

        let second = try CaptureStore(url: url)
        defer { second.close() }
        XCTAssertEqual(try second.schemaVersion(), 1)
        XCTAssertEqual(try second.enrichers(), ["com.example.app": "example"])
    }

    func test_open_setsDirectoryAndFilePermissions() throws {
        let store = try CaptureStore(url: url)
        store.close()
        let dirMode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(dirMode, 0o700)
        XCTAssertEqual(fileMode, 0o600)
    }

    func test_open_usesWALJournal() throws {
        let store = try CaptureStore(url: url)
        defer { store.close() }
        XCTAssertEqual(try store.journalMode(), "wal")
    }

    func test_replaceEnrichers_rewritesTheTable() throws {
        let store = try CaptureStore(url: url)
        defer { store.close() }
        try store.replaceEnrichers(["com.a": "a", "com.b": "b"])
        try store.replaceEnrichers(["com.c": "c"])
        XCTAssertEqual(try store.enrichers(), ["com.c": "c"])
    }

    private func segment(_ start: Int64, _ end: Int64, title: String = "Doc") -> CapturedSegment {
        CapturedSegment(start: start, end: end, type: .app, program: "com.example.app",
                        title: title, path: nil, rawTitle: title, enricher: nil)
    }

    func test_insert_writesClosedSegment() throws {
        let store = try CaptureStore(url: url)
        defer { store.close() }
        try store.insert(segment(100, 160))
        XCTAssertEqual(try store.segments(), [segment(100, 160)])
    }

    func test_insert_clearsTheCheckpoint() throws {
        let store = try CaptureStore(url: url)
        defer { store.close() }
        try store.checkpoint(segment(100, 130))
        try store.insert(segment(100, 160))
        XCTAssertNil(try store.openCheckpoint())
    }

    func test_checkpoint_keepsOneRow() throws {
        let store = try CaptureStore(url: url)
        defer { store.close() }
        try store.checkpoint(segment(100, 130))
        try store.checkpoint(segment(100, 160))
        XCTAssertEqual(try store.openCheckpoint(), segment(100, 160))
    }

    func test_checkpointNil_deletesTheRow() throws {
        let store = try CaptureStore(url: url)
        defer { store.close() }
        try store.checkpoint(segment(100, 130))
        try store.checkpoint(nil)
        XCTAssertNil(try store.openCheckpoint())
    }

    func test_recoverCheckpoint_closesTheLeftoverAtItsCheckpointTime() throws {
        let first = try CaptureStore(url: url)
        try first.checkpoint(segment(100, 130))
        first.close()   // simulates a crash: the segment never closed

        let second = try CaptureStore(url: url)
        defer { second.close() }
        XCTAssertEqual(try second.recoverCheckpoint(), segment(100, 130))
        XCTAssertEqual(try second.segments(), [segment(100, 130)])
        XCTAssertNil(try second.openCheckpoint())
    }

    func test_recoverCheckpoint_withNoRow_returnsNil() throws {
        let store = try CaptureStore(url: url)
        defer { store.close() }
        XCTAssertNil(try store.recoverCheckpoint())
    }

    func test_recoverCheckpoint_dropsZeroLengthLeftover() throws {
        let store = try CaptureStore(url: url)
        defer { store.close() }
        try store.checkpoint(segment(100, 100))
        _ = try store.recoverCheckpoint()
        XCTAssertEqual(try store.segments(), [])
        XCTAssertNil(try store.openCheckpoint())
    }
}
