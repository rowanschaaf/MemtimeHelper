import SwiftUI

@main
struct MemtimeHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("MemtimeHelper", systemImage: appDelegate.appState.statusIcon) {
            MenuBarView(state: appDelegate.appState)
        }
        .menuBarExtraStyle(.menu)
    }
}
