import XCTest
@testable import MemtimeHelper

private struct FakeMonitor: AppMonitor {
    let bundleID: String
    let appDisplayName: String
    let expectsTitleWhenFrontmost = false
    func currentTitle(for pid: pid_t) -> String? { nil }
}

final class ActivitySamplerTests: XCTestCase {
    func test_enricherNames_mapBundleIDToLowerCaseDisplayName() {
        let monitors: [AppMonitor] = [
            FakeMonitor(bundleID: "com.example.chat", appDisplayName: "Chat"),
            FakeMonitor(bundleID: "com.example.mail", appDisplayName: "Mail"),
        ]
        XCTAssertEqual(LiveActivitySampler.enricherNames(for: monitors),
                       ["com.example.chat": "chat", "com.example.mail": "mail"])
    }
}
