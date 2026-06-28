import XCTest
@testable import MemtimeHelper

/// In-memory `AXNode` for exercising the title walk without a live app.
/// `parent` is weak (to avoid retain cycles with the strong `children`), so a
/// test MUST keep a strong reference to the tree root for the duration of the
/// assertion — `withExtendedLifetime(root)` below does that.
private final class FakeAXNode: AXNode {
    var role: String?
    var title: String?
    var desc: String?
    private(set) var children: [AXNode] = []
    private weak var parentNode: FakeAXNode?
    var parent: AXNode? { parentNode }

    init(role: String? = nil, title: String? = nil, desc: String? = nil) {
        self.role = role
        self.title = title
        self.desc = desc
    }

    @discardableResult
    func adding(_ kids: FakeAXNode...) -> FakeAXNode {
        for kid in kids {
            kid.parentNode = self
            children.append(kid)
        }
        return self
    }
}

final class ClaudeTitleTests: XCTestCase {

    /// Claude 1.14271.0 (Jun 2026): the header splits into two sibling groups —
    /// the title button is no longer a sibling of the "Session actions" popup.
    /// This is the layout that broke real title tracking on 2026-06-18.
    func test_extract_newLayout_titleInSiblingGroup() {
        let sessionActions = FakeAXNode(role: "AXPopUpButton", desc: "Session actions")
        let root = FakeAXNode(role: "AXGroup").adding(
            FakeAXNode(role: "AXGroup").adding(
                FakeAXNode(role: "AXButton", title: "Claude entry attribution loss"),
                FakeAXNode(role: "AXCheckBox", desc: "Remote Control"),
                FakeAXNode(role: "AXPopUpButton", title: "MemtimeHelper")
            ),
            FakeAXNode(role: "AXGroup").adding(
                FakeAXNode(role: "AXCheckBox", desc: "Terminal"),
                FakeAXNode(role: "AXCheckBox", desc: "Diff"),
                FakeAXNode(role: "AXCheckBox", desc: "Preview"),
                sessionActions
            )
        )

        withExtendedLifetime(root) {
            XCTAssertEqual(ClaudeTitle.extract(fromAnchor: sessionActions), "Claude entry attribution loss")
        }
    }

    /// ≤ Apr 2026: title was a direct sibling of the popup. The walk must stay
    /// backward-compatible so an older Claude keeps working.
    func test_extract_oldLayout_titleIsDirectSibling() {
        let sessionActions = FakeAXNode(role: "AXPopUpButton", desc: "Session actions")
        let root = FakeAXNode(role: "AXGroup").adding(
            FakeAXNode(role: "AXPopUpButton", title: "pattern-marketing-automation"),
            FakeAXNode(role: "AXButton", title: "Continue CRM migration to Attio platform"),
            sessionActions
        )

        withExtendedLifetime(root) {
            XCTAssertEqual(ClaudeTitle.extract(fromAnchor: sessionActions),
                           "Continue CRM migration to Attio platform")
        }
    }

    /// A pane with no titled button near the anchor (e.g. launcher home) must
    /// return nil — never a stray button or a false positive.
    func test_extract_returnsNil_whenNoTitledButtonInHeader() {
        let sessionActions = FakeAXNode(role: "AXPopUpButton", desc: "Session actions")
        let root = FakeAXNode(role: "AXGroup").adding(
            FakeAXNode(role: "AXCheckBox", desc: "Terminal"),
            sessionActions
        )

        withExtendedLifetime(root) {
            XCTAssertNil(ClaudeTitle.extract(fromAnchor: sessionActions))
        }
    }

    /// The depth bounds must keep the walk inside the header: a button buried
    /// far below the anchor's ancestry (chat content) must not be picked up.
    func test_extract_doesNotReachDeepButtonsOutsideHeader() {
        var deepChain = FakeAXNode(role: "AXGroup").adding(
            FakeAXNode(role: "AXButton", title: "Copy message")
        )
        for _ in 0..<8 {
            deepChain = FakeAXNode(role: "AXGroup").adding(deepChain)
        }
        let sessionActions = FakeAXNode(role: "AXPopUpButton", desc: "Session actions")
        let root = FakeAXNode(role: "AXGroup").adding(
            FakeAXNode(role: "AXGroup").adding(sessionActions),
            deepChain
        )

        withExtendedLifetime(root) {
            XCTAssertNil(ClaudeTitle.extract(fromAnchor: sessionActions))
        }
    }
}
