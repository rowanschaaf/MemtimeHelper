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
                       BrowserTab(url: "https://dev.azure.com/x", title: "Board"))
    }

    func test_inPrivateWindow_givesNothing() {
        XCTAssertNil(EdgeTab.parse(result(["incognito", "https://example.com", "Secret"])))
    }

    func test_unknownMode_givesNothing() {
        XCTAssertNil(EdgeTab.parse(result(["", "https://example.com", "Page"])))
    }

    func test_noWindow_givesNothing() {
        XCTAssertNil(EdgeTab.parse(result(["", "", ""])))
    }

    func test_emptyTitle_givesNilTitle() {
        XCTAssertEqual(EdgeTab.parse(result(["normal", "https://example.com", ""])),
                       BrowserTab(url: "https://example.com", title: nil))
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
        XCTAssertNil(EdgeTab.parse(result(["normal", "https://x"])))
    }

    func test_fourItemList_givesNothing() {
        XCTAssertNil(EdgeTab.parse(result(["normal", "https://x", "T", "extra"])))
    }

    func test_nonListDescriptor_givesNothing() {
        XCTAssertNil(EdgeTab.parse(NSAppleEventDescriptor(string: "normal")))
    }

    func test_normalWindowWithEmptyURL_givesNothing() {
        XCTAssertNil(EdgeTab.parse(result(["normal", "", "Title"])))
    }
}
