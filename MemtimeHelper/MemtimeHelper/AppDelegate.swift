import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Suppress dock icon (belt-and-suspenders alongside LSUIElement)
        NSApp.setActivationPolicy(.accessory)
    }
}
