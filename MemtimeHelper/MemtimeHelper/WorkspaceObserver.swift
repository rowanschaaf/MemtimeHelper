import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "WorkspaceObserver")

/// Monitors multiple apps via AX and updates Memtime's database with enriched titles.
@MainActor
final class WorkspaceObserver {
    private let monitors: [AppMonitor]
    private let updater = WindowTitleUpdater()
    private var trackers: [String: ConversationTracker] = [:]
    /// Running PID per monitored bundleID. Kept in step by the launch and
    /// terminate notifications and, as the authority, by `reconcileRunningApps()`.
    private(set) var activeApps: [String: pid_t] = [:]
    /// Last title we successfully wrote to Memtime, per bundleID. Drives the
    /// row-split decision: when this differs from a fresh non-nil read, we
    /// close the open row and insert a new one so time is segmented per
    /// conversation rather than rolled into one Claude block.
    private var lastWrittenTitles: [String: String] = [:]
    /// Silent-breakage detection, for monitors that opt in via
    /// `expectsTitleWhenFrontmost`.
    private var health: [String: TitleHealth] = [:]
    private var timer: Timer?
    /// Looks up the running PID for a bundleID. Injected so tests need no live apps.
    private let runningPID: (String) -> pid_t?

    var isPolling: Bool { timer != nil }

    /// Called when any monitored app's title changes. Parameters: (bundleID, title).
    var onTitleChange: ((String, String?) -> Void)?

    /// Called when a monitor's title health alerts or recovers.
    var onHealthEvent: ((AppMonitor, TitleHealth.Event) -> Void)?

    init(
        monitors: [AppMonitor],
        runningPID: @escaping (String) -> pid_t? = { bundleID in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { !$0.isTerminated })?.processIdentifier
        }
    ) {
        self.monitors = monitors
        self.runningPID = runningPID
        let threshold = TitleHealth.configuredThreshold()
        for m in monitors {
            trackers[m.bundleID] = ConversationTracker()
            if m.expectsTitleWhenFrontmost {
                health[m.bundleID] = TitleHealth(threshold: threshold)
            }
        }
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        // Adopt apps that are already running, then poll for the lifetime of
        // the observer. The timer never stops: each poll reconciles against the
        // running apps, so it also catches an app that launches while no
        // notification arrives.
        reconcileRunningApps()
        startPolling()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopPolling()
        updater.close()
    }

    // MARK: - Private

    @objc private func appDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              monitors.contains(where: { $0.bundleID == bundleID }) else { return }

        let displayName = monitors.first(where: { $0.bundleID == bundleID })?.appDisplayName ?? bundleID
        logger.notice("\(displayName, privacy: .public) launched (PID \(app.processIdentifier))")
        activeApps[bundleID] = app.processIdentifier
    }

    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              activeApps[bundleID] != nil else { return }
        // A relaunch can deliver the old instance's terminate after the new
        // instance is running. Keep tracking the new one.
        if let current = runningPID(bundleID), current != app.processIdentifier {
            activeApps[bundleID] = current
            return
        }
        removeApp(bundleID, reason: "terminated")
    }

    /// Aligns `activeApps` with the apps that are actually running. Covers a
    /// relaunch (for example an auto-update) or an exit whose notification
    /// never arrived. A new or changed PID is adopted; a missing app gets the
    /// same side effects as a terminate notification.
    func reconcileRunningApps() {
        for monitor in monitors {
            let id = monitor.bundleID
            let known = activeApps[id]
            switch (known, runningPID(id)) {
            case let (nil, pid?):
                activeApps[id] = pid
                logger.notice("\(monitor.appDisplayName, privacy: .public) found running (PID \(pid))")
            case let (old?, pid?) where old != pid:
                activeApps[id] = pid
                logger.notice("\(monitor.appDisplayName, privacy: .public) relaunched (PID \(old) → \(pid))")
            case (_?, nil):
                removeApp(id, reason: "not running (no terminate notification)")
            default:
                break
            }
        }
    }

    private func removeApp(_ bundleID: String, reason: String) {
        guard activeApps.removeValue(forKey: bundleID) != nil else { return }
        let displayName = monitors.first(where: { $0.bundleID == bundleID })?.appDisplayName ?? bundleID
        logger.notice("\(displayName, privacy: .public) \(reason, privacy: .public)")
        trackers[bundleID]?.record(nil)
        lastWrittenTitles.removeValue(forKey: bundleID)
        onTitleChange?(bundleID, nil)
    }

    private func startPolling() {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.poll() }
        }
        poll()
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private var pollCount = 0

    private func poll() {
        pollCount += 1
        reconcileRunningApps()

        for monitor in monitors {
            guard let pid = activeApps[monitor.bundleID] else { continue }

            let title = monitor.currentTitle(for: pid)

            if pollCount <= 3 || pollCount % 30 == 0 {
                logger.notice("poll #\(self.pollCount) \(monitor.appDisplayName, privacy: .public): \(title ?? "nil", privacy: .public)")
            }

            recordHealth(for: monitor, title: title)

            // Only write when we have a real title. A nil read (typically a
            // backgrounded window with a stub AX tree) must not clobber the
            // last-good title — Memtime would just show the bare app name.
            // A nil read also must not trigger a row-split: a transient AX
            // hiccup between two reads of the same conversation would create
            // an empty segment.
            if let title {
                let previous = lastWrittenTitles[monitor.bundleID]
                if let previous, previous != title {
                    // Real switch between two known titles → split segment.
                    updater.splitSegment(bundleID: monitor.bundleID, newTitle: title)
                    logger.notice("\(monitor.appDisplayName, privacy: .public) segment split: \(previous, privacy: .public) → \(title, privacy: .public)")
                } else {
                    // First write for this app, or same title as before → just
                    // refresh in case Memtime overwrote it between polls.
                    updater.update(bundleID: monitor.bundleID, title: title)
                }
                lastWrittenTitles[monitor.bundleID] = title
            }

            guard let tracker = trackers[monitor.bundleID], tracker.hasChanged(from: title) else { continue }
            tracker.record(title)
            logger.notice("\(monitor.appDisplayName, privacy: .public) title changed to: \(title ?? "nil", privacy: .public)")
            onTitleChange?(monitor.bundleID, title)
        }
    }

    private func recordHealth(for monitor: AppMonitor, title: String?) {
        guard health[monitor.bundleID] != nil else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == monitor.bundleID
        guard let event = health[monitor.bundleID]?.record(title: title, frontmost: frontmost, at: Date()) else { return }

        switch event {
        case .alert:
            let seconds = Int(health[monitor.bundleID]?.threshold ?? 0)
            logger.error("\(monitor.appDisplayName, privacy: .public) title health: no title read in \(seconds) s of frontmost use — AX layout may have changed")
        case .recovered:
            logger.notice("\(monitor.appDisplayName, privacy: .public) title health: recovered")
        }
        onHealthEvent?(monitor, event)
    }
}
