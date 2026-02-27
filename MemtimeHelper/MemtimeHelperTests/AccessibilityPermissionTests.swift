import XCTest
@testable import MemtimeHelper

final class AccessibilityPermissionTests: XCTestCase {
    func test_isGranted_isFalseInTestEnvironment() {
        // The test runner process is never granted Accessibility permission.
        // If this fails, a developer has manually granted permission to the test host,
        // which is unusual and worth investigating.
        XCTAssertFalse(AccessibilityPermission.isGranted)
    }
}
