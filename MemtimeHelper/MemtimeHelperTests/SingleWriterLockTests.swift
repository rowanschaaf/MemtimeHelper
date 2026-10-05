import XCTest
@testable import MemtimeHelper

final class SingleWriterLockTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lock-\(UUID().uuidString).lock")
    }

    func test_acquiresOnFreshFile() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNotNil(SingleWriterLock(url: url))
    }

    func test_secondAcquireFailsWhileFirstIsAlive() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = SingleWriterLock(url: url)
        XCTAssertNotNil(first)
        XCTAssertNil(SingleWriterLock(url: url))
        withExtendedLifetime(first) {}
    }

    func test_acquiresAgainAfterRelease() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var first = SingleWriterLock(url: url)
        XCTAssertNotNil(first)
        first = nil
        XCTAssertNotNil(SingleWriterLock(url: url))
    }
}
