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

    /// Claude 2.19675.0 (Oct 2026) pane header. The "Session actions" popup is
    /// gone, and the title button has no `title` attribute. The title is in
    /// its `desc`, as "{title}, rename session".
    private func makeV2Header(renameDesc: String) -> (root: FakeAXNode, rename: FakeAXNode, moreOptions: FakeAXNode) {
        let rename = FakeAXNode(role: "AXButton", desc: renameDesc)
        let moreOptions = FakeAXNode(role: "AXPopUpButton", desc: "More options for Fix title extraction")
        let root = FakeAXNode(role: "AXGroup").adding(
            FakeAXNode(role: "AXGroup").adding(
                FakeAXNode(role: "AXCheckBox", desc: "Remote Control"),
                rename,
                moreOptions,
                FakeAXNode(role: "AXPopUpButton", title: "MemtimeHelper")
            ),
            FakeAXNode(role: "AXGroup").adding(
                FakeAXNode(role: "AXCheckBox", desc: "Terminal"),
                FakeAXNode(role: "AXCheckBox", desc: "Changes"),
                FakeAXNode(role: "AXCheckBox", desc: "Browser"),
                FakeAXNode(role: "AXPopUpButton", desc: "View options"),
                FakeAXNode(role: "AXButton", desc: "Close split view")
            )
        )
        return (root, rename, moreOptions)
    }

    func test_isAnchor_acceptsRenameSessionButton_v2Layout() {
        let header = makeV2Header(renameDesc: "Fix title extraction, rename session")
        withExtendedLifetime(header.root) {
            XCTAssertTrue(ClaudeTitle.isAnchor(header.rename))
        }
    }

    func test_extract_v2Layout_titleFromRenameSessionButtonDesc() {
        let header = makeV2Header(renameDesc: "Fix title extraction, rename session")
        withExtendedLifetime(header.root) {
            XCTAssertEqual(ClaudeTitle.extract(fromAnchor: header.rename), "Fix title extraction")
        }
    }

    /// A rename button with an empty title must not produce an empty title.
    /// WorkspaceObserver writes every non-nil result to Memtime.
    func test_extract_v2Layout_returnsNil_whenTitleIsEmpty() {
        let header = makeV2Header(renameDesc: ", rename session")
        withExtendedLifetime(header.root) {
            XCTAssertNil(ClaudeTitle.extract(fromAnchor: header.rename))
        }
    }

    /// Older Claude versions anchor on the "Session actions" popup. Keep
    /// accepting it so an older Claude still works.
    func test_isAnchor_acceptsLegacySessionActionsPopup() {
        XCTAssertTrue(ClaudeTitle.isAnchor(FakeAXNode(role: "AXPopUpButton", desc: "Session actions")))
    }

    /// The sidebar has one "More options for {title}" popup and one status-
    /// prefixed button per session. Neither may anchor a pane, or the monitor
    /// reports a sidebar row instead of the open conversation.
    func test_isAnchor_rejectsSidebarRowsAndPaneMoreOptions() {
        let header = makeV2Header(renameDesc: "Fix title extraction, rename session")
        withExtendedLifetime(header.root) {
            XCTAssertFalse(ClaudeTitle.isAnchor(header.moreOptions))
            XCTAssertFalse(ClaudeTitle.isAnchor(FakeAXNode(role: "AXButton", title: "Idle Fix title extraction")))
            XCTAssertFalse(ClaudeTitle.isAnchor(FakeAXNode(role: "AXButton", desc: "Close split view")))
        }
    }

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
