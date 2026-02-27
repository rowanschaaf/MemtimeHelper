import ApplicationServices

enum AccessibilityPermission {
    /// Returns true if Accessibility permission has been granted.
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission.
    /// Opens System Settings dialog. Does NOT block.
    static func requestIfNeeded() {
        guard !isGranted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
