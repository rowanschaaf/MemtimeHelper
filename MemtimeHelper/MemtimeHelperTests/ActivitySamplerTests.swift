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

    private let edge = "com.microsoft.edgemac"

    private func sample(_ bundle: String, title: String?) -> ActivitySample {
        ActivitySample(time: 1, bundleID: bundle, windowTitle: title)
    }

    func test_privacy_edgeTab_setsURLAndTabTitle() {
        var s = sample(edge, title: "Board - Edge")
        LiveActivitySampler.applyBrowserPrivacy(&s, tab: .tab(BrowserTab(url: "https://x", title: "Board")))
        XCTAssertEqual(s.url, "https://x")
        XCTAssertEqual(s.tabTitle, "Board")
        XCTAssertEqual(s.windowTitle, "Board - Edge")
        XCTAssertFalse(s.isPrivateWindow)
    }

    func test_privacy_edgePrivate_clearsEverything() {
        var s = sample(edge, title: "Secret - InPrivate")
        s.url = "https://leak"
        s.tabTitle = "leak"
        LiveActivitySampler.applyBrowserPrivacy(&s, tab: .privateWindow)
        XCTAssertTrue(s.isPrivateWindow)
        XCTAssertNil(s.windowTitle)
        XCTAssertNil(s.url)
        XCTAssertNil(s.tabTitle)
    }

    func test_privacy_normalTabWithLaggingInPrivateTitle_clearsTitleKeepsURL() {
        var s = sample(edge, title: "Secret - Microsoft Edge (InPrivate)")
        LiveActivitySampler.applyBrowserPrivacy(&s, tab: .tab(BrowserTab(url: "https://x", title: "Board")))
        XCTAssertNil(s.windowTitle)
        XCTAssertEqual(s.url, "https://x")
        XCTAssertEqual(s.tabTitle, "Board")
        XCTAssertFalse(s.isPrivateWindow)
    }

    func test_privacy_edgeUnavailableWithInPrivateTitle_isPrivate() {
        var s = sample(edge, title: "Secret - Microsoft Edge (InPrivate)")
        LiveActivitySampler.applyBrowserPrivacy(&s, tab: .unavailable)
        XCTAssertTrue(s.isPrivateWindow)
        XCTAssertNil(s.windowTitle)
    }

    func test_privacy_edgeUnavailableNormalTitle_untouched() {
        var s = sample(edge, title: "Board - Edge")
        LiveActivitySampler.applyBrowserPrivacy(&s, tab: .unavailable)
        XCTAssertEqual(s.windowTitle, "Board - Edge")
        XCTAssertFalse(s.isPrivateWindow)
    }

    func test_privacy_safari_clearsAllTitles() {
        var s = sample("com.apple.Safari", title: "Some page")
        s.url = "https://x"
        s.tabTitle = "Some page"
        LiveActivitySampler.applyBrowserPrivacy(&s, tab: .unavailable)
        XCTAssertNil(s.windowTitle)
        XCTAssertNil(s.url)
        XCTAssertNil(s.tabTitle)
    }

    func test_privacy_otherApp_normalTitle_untouched() {
        var s = sample("com.example.app", title: "Doc notes")
        LiveActivitySampler.applyBrowserPrivacy(&s, tab: .unavailable)
        XCTAssertEqual(s.windowTitle, "Doc notes")
        XCTAssertFalse(s.isPrivateWindow)
    }

    func test_privacy_chromeIncognito_isPrivateAndCleared() {
        var s = sample("com.google.Chrome", title: "Secret - Google Chrome (Incognito)")
        s.url = "https://leak"
        s.tabTitle = "leak"
        LiveActivitySampler.applyBrowserPrivacy(&s, tab: .unavailable)
        XCTAssertTrue(s.isPrivateWindow)
        XCTAssertNil(s.windowTitle)
        XCTAssertNil(s.url)
        XCTAssertNil(s.tabTitle)
    }

    func test_privacy_unknownAppWithInPrivateTitle_isPrivate() {
        var s = sample("com.example.app", title: "Doc (InPrivate) notes")
        LiveActivitySampler.applyBrowserPrivacy(&s, tab: .unavailable)
        XCTAssertTrue(s.isPrivateWindow)
        XCTAssertNil(s.windowTitle)
    }
}
