import ApplicationServices

enum AccessibilityPermission {
    /// Returns true if Accessibility permission has been granted.
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission by opening System Settings.
    /// Does NOT block — returns immediately. Callers must poll `isGranted` to detect
    /// when the user grants permission.
    static func requestIfNeeded() {
        guard !isGranted else { return }
        // takeUnretainedValue() is correct: kAXTrustedCheckOptionPrompt is a +0 global constant
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
