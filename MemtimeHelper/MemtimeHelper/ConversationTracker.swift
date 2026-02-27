import Foundation

final class ConversationTracker {
    var lastTitle: String?

    func hasChanged(from newTitle: String?) -> Bool {
        lastTitle != newTitle
    }

    func record(_ title: String?) {
        lastTitle = title
    }
}
