import AppKit
import ApplicationServices
import os

let claudeBundleID = "com.anthropic.claudefordesktop"

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "WorkspaceObserver")

/// Monitors for Claude.app becoming frontmost and drives the 1-second polling loop.
@MainActor
final class WorkspaceObserver {
    private let monitor = AccessibilityMonitor()
    private let updater = WindowTitleUpdater()
    private let tracker = ConversationTracker()
    private var timer: Timer?

    var onTitleChange: ((String?) -> Void)?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidDeactivate(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )

        // If Claude is already frontmost when we start, begin polling immediately
        if let claude = runningClaude() {
            startPolling(pid: claude.processIdentifier)
        }
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopPolling()
    }

    // MARK: - Private

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == claudeBundleID else { return }
        logger.debug("Claude activated — starting polling")
        startPolling(pid: app.processIdentifier)
    }

    @objc private func appDidDeactivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == claudeBundleID else { return }
        logger.debug("Claude deactivated — stopping polling")
        stopPolling()
    }

    private func startPolling(pid: pid_t) {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.poll(pid: pid) }
        }
        poll(pid: pid) // fire immediately
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func poll(pid: pid_t) {
        let title = monitor.currentConversationTitle(for: pid)
        guard tracker.hasChanged(from: title) else { return }
        tracker.record(title)
        logger.debug("Conversation changed: \(title ?? "nil")")
        updater.update(pid: pid, conversationTitle: title)
        onTitleChange?(title)
    }

    private func runningClaude() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID).first
    }
}
