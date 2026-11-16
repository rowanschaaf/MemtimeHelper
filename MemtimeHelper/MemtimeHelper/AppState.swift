import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var statusMessage: String = "Waiting for apps…"
    @Published var statusIcon: String = "circle"
    @Published var appStatuses: [String: String] = [:]  // bundleID → display title
    /// Apps whose title reads have failed long enough to alert (see `TitleHealth`).
    @Published private(set) var degradedApps: [String: String] = [:]  // bundleID → app name

    /// Native capture health (see `CaptureHealthMonitor`); takes precedence over the app status.
    @Published private(set) var captureStatus: CaptureHealth.Status = .capturing

    func setCaptureStatus(_ status: CaptureHealth.Status) {
        captureStatus = status
        refreshStatus()
    }

    func setActive(bundleID: String, title: String?) {
        if let title {
            appStatuses[bundleID] = title
        } else {
            appStatuses.removeValue(forKey: bundleID)
        }
        refreshStatus()
    }

    func setWaiting() {
        statusMessage = "Waiting for apps…"
        statusIcon = "circle"
        appStatuses.removeAll()
    }

    func setDegraded(bundleID: String, appName: String) {
        degradedApps[bundleID] = appName
        refreshStatus()
    }

    func clearDegraded(bundleID: String) {
        degradedApps.removeValue(forKey: bundleID)
        refreshStatus()
    }

    private var permissionMissing = false

    func setPermissionError() {
        permissionMissing = true
        refreshStatus()
    }

    func clearPermissionError() {
        permissionMissing = false
        refreshStatus()
    }

    private func refreshStatus() {
        switch captureStatus {
        case .stopped(let reason):
            statusMessage = "Native capture stopped: \(reason)"
            statusIcon = "xmark.octagon.fill"
            return
        case .degraded(let reasons):
            statusMessage = reasons.map(\.message).joined(separator: "\n")
            statusIcon = "exclamationmark.triangle.fill"
            return
        case .capturing:
            break
        }
        if permissionMissing {
            statusMessage = "Accessibility permission needed"
            statusIcon = "exclamationmark.circle"
            return
        }
        if !degradedApps.isEmpty {
            let names = degradedApps.values.sorted().joined(separator: ", ")
            statusMessage = "\(names): no title read — layout may have changed. Use Dump Claude AX Tree…"
            statusIcon = "exclamationmark.triangle.fill"
        } else if appStatuses.isEmpty {
            statusMessage = "Monitoring — no active context"
            statusIcon = "circle.dotted"
        } else {
            statusMessage = appStatuses.values.joined(separator: " | ")
            statusIcon = "circle.fill"
        }
    }
}
