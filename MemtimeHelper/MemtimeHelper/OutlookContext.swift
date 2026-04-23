import Foundation

/// Represents the different contexts detectable in Outlook, each with its own display format.
enum OutlookContext {
    case readingEmail(sender: String, subject: String)
    case composing(to: String?, subject: String?)
    case calendar(eventTitle: String?)

    var formattedTitle: String {
        switch self {
        case .readingEmail(let sender, let subject):
            return "\(sender) — \(subject)"
        case .composing(let to, let subject):
            let recipient = to ?? "New Email"
            let subj = (subject?.isEmpty ?? true) ? "No Subject" : subject!
            return "Composing to \(recipient) — \(subj)"
        case .calendar(let title):
            return "Calendar: \(title ?? "Calendar")"
        }
    }
}
