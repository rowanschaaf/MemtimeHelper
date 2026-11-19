import XCTest
@testable import MemtimeHelper

/// A monitor that never reads a title, so a poll never reaches the Memtime writer.
private struct SilentMonitor: AppMonitor {
    let bundleID: String
    var appDisplayName: String { bundleID }
    var expectsTitleWhenFrontmost: Bool { false }
    func currentTitle(for pid: pid_t) -> String? { nil }
}

@MainActor
final class WorkspaceObserverReconcileTests: XCTestCase {
    private let claude = "test.claude"
    private var running: [String: pid_t] = [:]
    private var titleEvents: [(String, String?)] = []

    private func makeObserver() -> WorkspaceObserver {
        let observer = WorkspaceObserver(
            monitors: [SilentMonitor(bundleID: claude)],
            runningPID: { [unowned self] in self.running[$0] }
        )
        observer.onTitleChange = { [unowned self] in self.titleEvents.append(($0, $1)) }
        return observer
    }

    func test_relaunchWithNewPIDAndNoNotification_isAdopted() {
        let observer = makeObserver()
        running[claude] = 100
        observer.reconcileRunningApps()
        XCTAssertEqual(observer.activeApps[claude], 100)

        running[claude] = 200
        observer.reconcileRunningApps()

        XCTAssertEqual(observer.activeApps[claude], 200)
    }

    func test_appGoneWithoutNotification_isRemovedWithTerminationSideEffects() {
        let observer = makeObserver()
        running[claude] = 100
        observer.reconcileRunningApps()
        titleEvents.removeAll()

        running[claude] = nil
        observer.reconcileRunningApps()

        XCTAssertNil(observer.activeApps[claude])
        XCTAssertEqual(titleEvents.count, 1)
        XCTAssertEqual(titleEvents.first?.0, claude)
        XCTAssertNil(titleEvents.first?.1)
    }

    func test_unchangedPID_isNoOp() {
        let observer = makeObserver()
        running[claude] = 100
        observer.reconcileRunningApps()
        titleEvents.removeAll()

        observer.reconcileRunningApps()

        XCTAssertEqual(observer.activeApps[claude], 100)
        XCTAssertTrue(titleEvents.isEmpty)
    }

    func test_appAbsentAndStillAbsent_isNoOp() {
        let observer = makeObserver()
        observer.reconcileRunningApps()
        XCTAssertTrue(observer.activeApps.isEmpty)
        XCTAssertTrue(titleEvents.isEmpty)
    }

    func test_appAppearingWhileNothingWasRunning_isTrackedAndPollingContinues() {
        let observer = makeObserver()
        observer.start()
        defer { observer.stop() }
        XCTAssertTrue(observer.activeApps.isEmpty)
        XCTAssertTrue(observer.isPolling, "the timer must run with no monitored app, or a launch with a missed notification is never seen")

        running[claude] = 300
        observer.reconcileRunningApps()

        XCTAssertEqual(observer.activeApps[claude], 300)
        XCTAssertTrue(observer.isPolling)
    }

    func test_appGone_keepsPolling() {
        let observer = makeObserver()
        running[claude] = 100
        observer.start()
        defer { observer.stop() }

        running[claude] = nil
        observer.reconcileRunningApps()

        XCTAssertTrue(observer.activeApps.isEmpty)
        XCTAssertTrue(observer.isPolling)
    }
}
