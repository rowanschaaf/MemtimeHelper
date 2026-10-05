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
}
