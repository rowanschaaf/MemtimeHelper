import XCTest
@testable import MemtimeHelper

final class BrowserTabTests: XCTestCase {
    private func result(_ values: [String]) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for (i, v) in values.enumerated() {
            list.insert(NSAppleEventDescriptor(string: v), at: i + 1)
        }
        return list
    }

    func test_normalWindow_givesURLAndTitle() {
        XCTAssertEqual(EdgeTab.parse(result(["normal", "https://dev.azure.com/x", "Board"])),
                       .tab(BrowserTab(url: "https://dev.azure.com/x", title: "Board")))
    }

    func test_inPrivateWindow_isPrivateWindow() {
        XCTAssertEqual(EdgeTab.parse(result(["incognito", "https://example.com", "Secret"])), .privateWindow)
    }

    func test_privateWindowWithEmptyFields_isPrivateWindow() {
        XCTAssertEqual(EdgeTab.parse(result(["incognito", "", ""])), .privateWindow)
    }

    func test_unknownMode_isUnavailable() {
        XCTAssertEqual(EdgeTab.parse(result(["", "https://example.com", "Page"])), .unavailable)
    }

    func test_noWindow_isUnavailable() {
        XCTAssertEqual(EdgeTab.parse(result(["", "", ""])), .unavailable)
    }

    func test_emptyTitle_givesNilTitle() {
        XCTAssertEqual(EdgeTab.parse(result(["normal", "https://example.com", ""])),
                       .tab(BrowserTab(url: "https://example.com", title: nil)))
    }

    func test_scriptReadsModeURLAndTitle_withTimeout() {
        XCTAssertTrue(EdgeTab.source.contains("with timeout of 1 second"))
        XCTAssertTrue(EdgeTab.source.contains("mode of w"))
        XCTAssertTrue(EdgeTab.source.contains(EdgeTab.bundleID))
        XCTAssertTrue(EdgeTab.source.contains("if mode of w is not \"normal\""))
    }

    func test_bundleID_isPinned() {
        XCTAssertEqual(EdgeTab.bundleID, "com.microsoft.edgemac")
        XCTAssertTrue(EdgeTab.source.contains("\"com.microsoft.edgemac\""))
    }

    func test_twoItemList_givesNothing() {
        XCTAssertEqual(EdgeTab.parse(result(["normal", "https://x"])), .unavailable)
    }

    func test_fourItemList_givesNothing() {
        XCTAssertEqual(EdgeTab.parse(result(["normal", "https://x", "T", "extra"])), .unavailable)
    }

    func test_nonListDescriptor_givesNothing() {
        XCTAssertEqual(EdgeTab.parse(NSAppleEventDescriptor(string: "normal")), .unavailable)
    }

    func test_normalWindowWithEmptyURL_givesNothing() {
        XCTAssertEqual(EdgeTab.parse(result(["normal", "", "Title"])), .unavailable)
    }
}
