import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var statusMessage: String = "Waiting for Claude…"
    @Published var statusIcon: String = "circle"

    func setActive(conversationTitle: String?) {
        if let title = conversationTitle {
            statusMessage = title
            statusIcon = "circle.fill"
        } else {
            statusMessage = "Claude active — no conversation"
            statusIcon = "circle.dotted"
        }
    }

    func setWaiting() {
        statusMessage = "Waiting for Claude…"
        statusIcon = "circle"
    }

    func setPermissionError() {
        statusMessage = "Accessibility permission needed"
        statusIcon = "exclamationmark.circle"
    }
}
