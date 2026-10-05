import XCTest
@testable import MemtimeHelper

final class CaptureSchemaTests: XCTestCase {
    /// TimesheetHelper builds its fixtures from a copy of docs/capture-store-v1.sql.
    /// If the applied schema drifts from that file, the two codebases disagree silently.
    func test_v1_matchesCanonicalFile() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MemtimeHelperTests
            .deletingLastPathComponent()   // MemtimeHelper (Xcode root)
            .deletingLastPathComponent()   // repository root
        let file = repoRoot.appendingPathComponent("docs/capture-store-v1.sql")
        let canonical = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(CaptureSchema.v1.trimmingCharacters(in: .whitespacesAndNewlines),
                       canonical.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func test_migrations_startWithV1() {
        XCTAssertEqual(CaptureSchema.migrations.first, CaptureSchema.v1)
    }
}
