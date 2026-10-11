import XCTest
import ServiceManagement
@testable import MemtimeHelper

final class LoginItemTests: XCTestCase {
    func test_registers_whenNeverRegistered() {
        XCTAssertTrue(LoginItem.shouldRegister(.notRegistered))
    }

    /// Removing the item in System Settings leaves the status `.notFound`.
    /// The app must add itself back, or it silently stops starting at login.
    func test_registers_whenRemovedInSystemSettings() {
        XCTAssertTrue(LoginItem.shouldRegister(.notFound))
    }

    func test_leavesAnEnabledItemAlone() {
        XCTAssertFalse(LoginItem.shouldRegister(.enabled))
    }

    /// The user turned the item off in System Settings; registering again
    /// would override that choice.
    func test_leavesAnItemAwaitingApprovalAlone() {
        XCTAssertFalse(LoginItem.shouldRegister(.requiresApproval))
    }
}
