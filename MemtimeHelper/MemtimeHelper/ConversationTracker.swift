import Foundation

@MainActor
final class ConversationTracker {
    private var lastTitle: String?

    func hasChanged(from newTitle: String?) -> Bool {
        lastTitle != newTitle
    }

    func record(_ title: String?) {
        lastTitle = title
    }
}
