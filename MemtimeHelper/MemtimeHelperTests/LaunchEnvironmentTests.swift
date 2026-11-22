import XCTest
@testable import MemtimeHelper

final class LaunchEnvironmentTests: XCTestCase {
    func test_isTestHost_whenXCTestConfigurationFilePathIsSet() {
        let environment = ["XCTestConfigurationFilePath": "/tmp/MemtimeHelperTests.xctestconfiguration"]
        XCTAssertTrue(LaunchEnvironment.isTestHost(environment))
    }

    func test_isNotTestHost_withoutXCTestConfigurationFilePath() {
        XCTAssertFalse(LaunchEnvironment.isTestHost(["HOME": "/Users/someone"]))
    }

    /// Checks that Xcode still sets the key. If it stops, every test run
    /// starts the live observer against Memtime's database again.
    func test_isTestHost_inThisTestRun() {
        XCTAssertTrue(LaunchEnvironment.isTestHost())
    }
}
