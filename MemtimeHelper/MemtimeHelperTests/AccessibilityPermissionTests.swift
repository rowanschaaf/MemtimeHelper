import XCTest
@testable import MemtimeHelper

final class AccessibilityPermissionTests: XCTestCase {
    func test_isGranted_returnsBool() {
        // This test documents the interface; actual trust value depends on system state.
        // We just verify the function returns a Bool without crashing.
        let status = AccessibilityPermission.isGranted
        XCTAssertNotNil(status)
        // status is either true or false — both are valid
        _ = status as Bool
    }
}
