import SwiftUI

@main
struct MemtimeHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No WindowGroup — menu bar only
        MenuBarExtra("MemtimeHelper", systemImage: "circle.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
