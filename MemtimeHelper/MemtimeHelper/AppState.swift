import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var statusMessage: String = "Waiting for apps…"
    @Published var statusIcon: String = "circle"
    @Published var appStatuses: [String: String] = [:]  // bundleID → display title

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

    func setPermissionError() {
        statusMessage = "Accessibility permission needed"
        statusIcon = "exclamationmark.circle"
    }

    private func refreshStatus() {
        if appStatuses.isEmpty {
            statusMessage = "Monitoring — no active context"
            statusIcon = "circle.dotted"
        } else {
            statusMessage = appStatuses.values.joined(separator: " | ")
            statusIcon = "circle.fill"
        }
    }
}
