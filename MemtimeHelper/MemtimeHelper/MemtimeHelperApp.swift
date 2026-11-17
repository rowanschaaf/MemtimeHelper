import SwiftUI

@main
struct MemtimeHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: appDelegate.appState)
        } label: {
            StatusIcon(state: appDelegate.appState)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// The menu bar icon. It observes `AppState` itself: an icon name passed to
/// `MenuBarExtra(_:systemImage:)` from `App.body` is read once and never updates.
private struct StatusIcon: View {
    @ObservedObject var state: AppState

    var body: some View {
        Image(systemName: state.statusIcon)
    }
}
