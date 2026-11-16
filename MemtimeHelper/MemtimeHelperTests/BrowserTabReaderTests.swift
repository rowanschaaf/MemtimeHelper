import XCTest
@testable import MemtimeHelper

@MainActor
final class BrowserTabReaderTests: XCTestCase {
    private let edge = "com.microsoft.edgemac"
    private var requests = 0
    private var executions = 0
    private var pendingAnswer: ((AutomationPermission) -> Void)?
    private var nextResult: Result<NSAppleEventDescriptor, AppleScriptError> = .failure(AppleScriptError(number: -1712))

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
        XCTAssertEqual(reader.activeTab(bundleID: "com.apple.Safari"), .unavailable)
        XCTAssertEqual(reader.activeTab(bundleID: "com.example.app"), .unavailable)
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(executions, 0)
    }

    func test_firstEdgeCall_requestsPermission_andSendsNoEvent() {
        let reader = makeReader()
        XCTAssertEqual(reader.activeTab(bundleID: edge), .unavailable)
        XCTAssertEqual(reader.activeTab(bundleID: edge), .unavailable)   // still requesting
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(executions, 0)
    }

    func test_granted_runsTheScript_andParsesTheTab() {
        let reader = makeReader()
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.granted)
        nextResult = .success(tab("normal", "https://dev.azure.com/x", "Board"))
        XCTAssertEqual(reader.activeTab(bundleID: edge), .tab(BrowserTab(url: "https://dev.azure.com/x", title: "Board")))
        XCTAssertEqual(executions, 1)
    }

    func test_inPrivateWindow_isPrivateWindow() {
        let reader = makeReader()
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.granted)
        nextResult = .success(tab("incognito", "https://example.com", "Secret"))
        XCTAssertEqual(reader.activeTab(bundleID: edge), .privateWindow)
    }

    func test_deniedPermission_stopsForGood() {
        let reader = makeReader()
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.denied)
        XCTAssertEqual(reader.activeTab(bundleID: edge), .unavailable)
        XCTAssertEqual(reader.activeTab(bundleID: edge), .unavailable)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(executions, 0)
    }

    func test_onDenied_firesForAPermissionDenial() {
        let reader = makeReader()
        var denials = 0
        reader.onDenied = { denials += 1 }
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.denied)
        XCTAssertEqual(denials, 1)
    }

    func test_onDenied_firesForAScriptDenial() {
        let reader = makeReader()
        var denials = 0
        reader.onDenied = { denials += 1 }
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.granted)
        nextResult = .failure(AppleScriptError(number: -1743))
        _ = reader.activeTab(bundleID: edge)
        XCTAssertEqual(denials, 1)
    }

    func test_scriptDenial_stopsForGood() {
        let reader = makeReader()
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.granted)
        nextResult = .failure(AppleScriptError(number: -1743))
        XCTAssertEqual(reader.activeTab(bundleID: edge), .unavailable)
        XCTAssertEqual(reader.activeTab(bundleID: edge), .unavailable)
        XCTAssertEqual(executions, 1)
    }

    func test_otherScriptError_retriesNextCall() {
        let reader = makeReader()
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.granted)
        nextResult = .failure(AppleScriptError(number: -1708))
        XCTAssertEqual(reader.activeTab(bundleID: edge), .unavailable)
        nextResult = .success(tab("normal", "https://example.com", "Page"))
        XCTAssertEqual(reader.activeTab(bundleID: edge),
                       .tab(BrowserTab(url: "https://example.com", title: "Page")))
        XCTAssertEqual(executions, 2)
    }

    func test_timeout_backsOffForTenCalls_thenExecutesAgain() {
        let reader = makeReader()
        _ = reader.activeTab(bundleID: edge)
        pendingAnswer?(.granted)
        nextResult = .failure(AppleScriptError(number: -1712))
        XCTAssertEqual(reader.activeTab(bundleID: edge), .unavailable)
        XCTAssertEqual(executions, 1)
        nextResult = .success(tab("normal", "https://example.com", "Page"))
        for _ in 0..<10 {
            XCTAssertEqual(reader.activeTab(bundleID: edge), .unavailable)
        }
        XCTAssertEqual(executions, 1)
        XCTAssertEqual(reader.activeTab(bundleID: edge),
                       .tab(BrowserTab(url: "https://example.com", title: "Page")))
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
