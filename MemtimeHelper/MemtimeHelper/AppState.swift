import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var statusMessage: String = "Waiting for apps…"
    @Published var statusIcon: String = "circle"
    @Published var appStatuses: [String: String] = [:]  // bundleID → display title
    /// Apps whose title reads have failed long enough to alert (see `TitleHealth`).
    @Published private(set) var degradedApps: [String: String] = [:]  // bundleID → app name

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

    func setPermissionError() {
        statusMessage = "Accessibility permission needed"
        statusIcon = "exclamationmark.circle"
    }

    private func refreshStatus() {
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
