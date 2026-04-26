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
    private var activeApps: [String: pid_t] = [:]
    /// Last title we successfully wrote to Memtime, per bundleID. Drives the
    /// row-split decision: when this differs from a fresh non-nil read, we
    /// close the open row and insert a new one so time is segmented per
    /// conversation rather than rolled into one Claude block.
    private var lastWrittenTitles: [String: String] = [:]
    private var timer: Timer?

    /// Called when any monitored app's title changes. Parameters: (bundleID, title).
    var onTitleChange: ((String, String?) -> Void)?

    init(monitors: [AppMonitor]) {
        self.monitors = monitors
        for m in monitors {
            trackers[m.bundleID] = ConversationTracker()
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

        // Check which monitored apps are already running
        for monitor in monitors {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: monitor.bundleID).first {
                activeApps[monitor.bundleID] = app.processIdentifier
                logger.notice("\(monitor.appDisplayName, privacy: .public) already running (PID \(app.processIdentifier))")
            }
        }

        if !activeApps.isEmpty {
            startPolling()
        } else {
            logger.notice("No monitored apps running — waiting")
        }
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

        if timer == nil { startPolling() }
    }

    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              activeApps.removeValue(forKey: bundleID) != nil else { return }

        let displayName = monitors.first(where: { $0.bundleID == bundleID })?.appDisplayName ?? bundleID
        logger.notice("\(displayName, privacy: .public) terminated")
        trackers[bundleID]?.record(nil)
        lastWrittenTitles.removeValue(forKey: bundleID)
        onTitleChange?(bundleID, nil)

        if activeApps.isEmpty { stopPolling() }
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

        for monitor in monitors {
            guard let pid = activeApps[monitor.bundleID] else { continue }

            let title = monitor.currentTitle(for: pid)

            if pollCount <= 3 || pollCount % 30 == 0 {
                logger.notice("poll #\(self.pollCount) \(monitor.appDisplayName, privacy: .public): \(title ?? "nil", privacy: .public)")
            }

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
}
