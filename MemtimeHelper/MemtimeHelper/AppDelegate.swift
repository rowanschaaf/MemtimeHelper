import AppKit
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "AppDelegate")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private let observer = WorkspaceObserver()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        registerLoginItemIfNeeded()

        guard AccessibilityPermission.isGranted else {
            appState.setPermissionError()
            AccessibilityPermission.requestIfNeeded()
            return
        }

        observer.onTitleChange = { [weak self] title in
            self?.appState.setActive(conversationTitle: title)
        }

        // Listen for Claude launching/quitting to update waiting state
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(claudeLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(claudeTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        observer.start()
    }

    // MARK: - Private

    private func registerLoginItemIfNeeded() {
        do {
            if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
                logger.info("Registered as login item")
            }
        } catch {
            logger.error("Failed to register login item: \(error)")
        }
    }

    @objc private func claudeLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.anthropic.claudefordesktop" else { return }
        logger.debug("Claude launched")
    }

    @objc private func claudeTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.anthropic.claudefordesktop" else { return }
        logger.debug("Claude terminated")
        appState.setWaiting()
    }
}
