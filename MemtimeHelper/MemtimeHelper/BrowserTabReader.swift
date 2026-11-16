import AppKit
import CoreServices
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "BrowserTabReader")

protocol BrowserTabReading {
    func activeTab(bundleID: String) -> BrowserTab?
}

/// The AppleScript error number travels as the `Result` failure value.
extension Int: @retroactive Error {}

enum AutomationPermission: Equatable {
    case granted, denied, unavailable
}

/// Reads the active Edge tab through AppleScript, on the caller's (main) thread.
/// It never sends an Apple Event until the Automation grant is known: an event
/// sent while the consent prompt is open would block the main thread.
final class BrowserTabReader: BrowserTabReading {
    private enum State { case unknown, requesting, granted, denied }

    private static let notPermitted = -1743

    private let requestPermission: (String, @escaping (AutomationPermission) -> Void) -> Void
    private let execute: () -> Result<NSAppleEventDescriptor, Int>
    private var state = State.unknown

    init(requestPermission: @escaping (String, @escaping (AutomationPermission) -> Void) -> Void,
         execute: @escaping () -> Result<NSAppleEventDescriptor, Int>) {
        self.requestPermission = requestPermission
        self.execute = execute
    }

    func activeTab(bundleID: String) -> BrowserTab? {
        guard bundleID == EdgeTab.bundleID else { return nil }
        switch state {
        case .denied, .requesting:
            return nil
        case .unknown:
            state = .requesting
            requestPermission(bundleID) { [weak self] permission in
                self?.apply(permission)
            }
            return nil
        case .granted:
            switch execute() {
            case .success(let result):
                return EdgeTab.parse(result)
            case .failure(let code):
                if code == Self.notPermitted {
                    state = .denied
                    logger.error("Automation for Edge was revoked; Edge URLs are no longer captured")
                }
                return nil
            }
        }
    }

    private func apply(_ permission: AutomationPermission) {
        switch permission {
        case .granted: state = .granted
        case .denied:
            state = .denied
            logger.error("Automation for Edge is denied; Edge segments are captured without URLs")
        case .unavailable: state = .unknown
        }
    }

    /// The real reader: asks for the grant on a background queue, and runs one
    /// compiled script on the calling thread.
    static func live() -> BrowserTabReader {
        let script = NSAppleScript(source: EdgeTab.source)
        return BrowserTabReader(
            requestPermission: { bundleID, answer in
                DispatchQueue.global(qos: .utility).async {
                    let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
                    // '****' (0x2A2A2A2A) asks about any event class and ID.
                    let status = AEDeterminePermissionToAutomateTarget(
                        target.aeDesc, AEEventClass(0x2A2A_2A2A), AEEventID(0x2A2A_2A2A), true)
                    let permission: AutomationPermission
                    switch status {
                    case noErr: permission = .granted
                    case OSStatus(notPermitted): permission = .denied
                    default: permission = .unavailable
                    }
                    DispatchQueue.main.async { answer(permission) }
                }
            },
            execute: {
                guard let script else { return .failure(-2700) }
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                if let error {
                    return .failure(error[NSAppleScript.errorNumber] as? Int ?? -2700)
                }
                return .success(result)
            })
    }
}
