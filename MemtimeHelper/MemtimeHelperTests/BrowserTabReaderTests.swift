import XCTest
@testable import MemtimeHelper

final class BrowserTabReaderTests: XCTestCase {
    private let edge = "com.microsoft.edgemac"
    private var requests = 0
    private var executions = 0
    private var pendingAnswer: ((AutomationPermission) -> Void)?
    private var nextResult: Result<NSAppleEventDescriptor, Int> = .failure(-1712)

    private func tab(_ mode: String, _ url: String, _ title: String) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for (i, v) in [mode, url, title].enumerated() {
            list.insert(NSAppleEventDescriptor(string: v), at: i + 1)
        }
        return list
    }

    private func makeReader() -> BrowserTabReader {
        BrowserTabReader(
            requestPermission: { [unowned self] _, answer in
                requests += 1
                pendingAnswer = answer
            },
            execute: { [unowned self] in
                executions += 1
                return nextResult
            })
    }

    func test_otherApps_neverRequestOrExecute() {
        let reader = makeReader()
        XCTAssertNil(reader.activeTab(bundleID: "com.apple.Safari"))
        XCTAssertNil(reader.activeTab(bundleID: "com.example.app"))
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(executions, 0)
    }

    func test_firstEdgeCall_requestsPermission_andSendsNoEvent() {
        let reader = makeReader()
        XCTAssertNil(reader.activeTab(bundleID: edge))
        XCTAssertNil(reader.activeTab(bundleID: edge))   // still requesting
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(executions, 0)
    }

    func test_granted_runsTheScript_andParsesTheTab() {
        let reader = makeReader()
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.granted)
        nextResult = .success(tab("normal", "https://dev.azure.com/x", "Board"))
        XCTAssertEqual(reader.activeTab(bundleID: edge), BrowserTab(url: "https://dev.azure.com/x", title: "Board"))
        XCTAssertEqual(executions, 1)
    }

    func test_inPrivateWindow_givesNothing() {
        let reader = makeReader()
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.granted)
        nextResult = .success(tab("incognito", "https://example.com", "Secret"))
        XCTAssertNil(reader.activeTab(bundleID: edge))
    }

    func test_deniedPermission_stopsForGood() {
        let reader = makeReader()
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.denied)
        XCTAssertNil(reader.activeTab(bundleID: edge))
        XCTAssertNil(reader.activeTab(bundleID: edge))
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(executions, 0)
    }

    func test_scriptDenial_stopsForGood() {
        let reader = makeReader()
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.granted)
        nextResult = .failure(-1743)
        XCTAssertNil(reader.activeTab(bundleID: edge))
        XCTAssertNil(reader.activeTab(bundleID: edge))
        XCTAssertEqual(executions, 1)
    }

    func test_otherScriptError_retriesNextCall() {
        let reader = makeReader()
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.granted)
        nextResult = .failure(-1712)
        XCTAssertNil(reader.activeTab(bundleID: edge))
        nextResult = .success(tab("normal", "https://example.com", "Page"))
        XCTAssertEqual(reader.activeTab(bundleID: edge)?.url, "https://example.com")
        XCTAssertEqual(executions, 2)
    }

    func test_unavailable_asksAgainNextCall() {
        let reader = makeReader()
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.unavailable)
        _ = reader.activeTab(bundleID: edge)
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(executions, 0)
    }
}
