import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Suppress dock icon (belt-and-suspenders alongside LSUIElement)
        NSApp.setActivationPolicy(.accessory)

        // DEV: Print Claude's AX tree to find the conversation title element.
        // Remove this block in Task 8.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            AXTreeExplorer.printClaudeTree()
        }
    }
}
