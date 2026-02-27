import AppKit
import Combine
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "AppDelegate")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()
    private let observer = WorkspaceObserver()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        // Forward AppState's objectWillChange so SwiftUI re-renders the MenuBarExtra icon.
        appState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

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

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(claudeTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        observer.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        observer.stop()
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

    @objc private func claudeTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == claudeBundleID else { return }
        logger.debug("Claude terminated")
        appState.setWaiting()
    }
}
