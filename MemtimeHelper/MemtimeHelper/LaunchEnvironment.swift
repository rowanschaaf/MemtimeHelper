import Foundation

enum LaunchEnvironment {
    /// True when the app runs as the host for an XCTest run. Xcode sets
    /// `XCTestConfigurationFilePath` in the test host's environment.
    static func isTestHost(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
