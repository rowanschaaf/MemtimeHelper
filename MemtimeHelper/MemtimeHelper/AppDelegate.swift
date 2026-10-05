import AppKit
import Combine
import ServiceManagement
import UserNotifications
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "AppDelegate")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()
    /// Shared by the Memtime writer and the native capture engine.
    private let monitors: [AppMonitor] = [ClaudeMonitor(), OutlookMonitor()]
    private lazy var observer = WorkspaceObserver(monitors: monitors)
    private var captureEngine: CaptureEngine?
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
        UNUserNotificationCenter.current().delegate = self
        registerLoginItemIfNeeded()
        startCapture()

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
        captureEngine?.stop()
    }

    // MARK: - Private

    private func startCapture() {
        do {
            let store = try CaptureStore(url: CaptureStore.defaultURL)
            try store.replaceEnrichers(LiveActivitySampler.enricherNames(for: monitors))
            let engine = CaptureEngine(sampler: LiveActivitySampler(monitors: monitors), store: store)
            engine.start()
            captureEngine = engine
            logger.notice("Native capture started: \(CaptureStore.defaultURL.path, privacy: .public)")
        } catch {
            logger.error("Native capture failed to start: \(String(describing: error), privacy: .public)")
        }
    }

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
        observer.onHealthEvent = { [weak self] monitor, event in
            switch event {
            case .alert:
                self?.appState.setDegraded(bundleID: monitor.bundleID, appName: monitor.appDisplayName)
                Self.postHealthAlert(appName: monitor.appDisplayName)
            case .recovered:
                self?.appState.clearDegraded(bundleID: monitor.bundleID)
            }
        }
        observer.start()
    }

    /// Posts the title-health notification. The menu bar icon is easy to miss,
    /// so this is the signal that reaches the user. Authorisation is requested
    /// on the first alert, when the prompt has an obvious reason. A fixed
    /// identifier per app makes a repeat alert replace the earlier banner.
    private static func postHealthAlert(appName: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                logger.notice("Notification permission not granted: \(error?.localizedDescription ?? "denied", privacy: .public)")
                return
            }
            let duration = DateComponentsFormatter.localizedString(
                from: DateComponents(second: Int(TitleHealth.configuredThreshold())), unitsStyle: .full) ?? "a while"
            let content = UNMutableNotificationContent()
            content.title = "\(appName) titles are not being tracked"
            content.body = "No \(appName) conversation title read in \(duration) of use. \(appName)'s layout may have changed. "
                + "Open the MemtimeHelper menu (warning triangle in the menu bar) → Dump Claude AX Tree…"
            center.add(UNNotificationRequest(identifier: "title-health-\(appName)", content: content, trigger: nil))
        }
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

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Shows the banner even when MemtimeHelper is the active app (menu open).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
