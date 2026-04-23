import AppKit
import Combine
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "AppDelegate")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()
    private let observer = WorkspaceObserver(monitors: [
        ClaudeMonitor(),
        OutlookMonitor()
    ])
    private var cancellables = Set<AnyCancellable>()
    private var permissionTimer: Timer?

    override init() {
        super.init()
        appState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerLoginItemIfNeeded()

        if AccessibilityPermission.isGranted {
            logger.notice("AX permission granted — starting observer")
            startObserver()
        } else {
            logger.notice("AX permission not granted — waiting")
            appState.setPermissionError()
            AccessibilityPermission.requestIfNeeded()
            startPermissionPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        observer.stop()
    }

    // MARK: - Private

    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                if AccessibilityPermission.isGranted {
                    logger.notice("Permission granted mid-flight — starting observer")
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.startObserver()
                }
            }
        }
    }

    private func startObserver() {
        observer.onTitleChange = { [weak self] bundleID, title in
            self?.appState.setActive(bundleID: bundleID, title: title)
        }
        observer.start()
    }

    private func registerLoginItemIfNeeded() {
        do {
            if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
                logger.notice("Registered as login item")
            }
        } catch {
            logger.error("Failed to register login item: \(error)")
        }
    }
}
