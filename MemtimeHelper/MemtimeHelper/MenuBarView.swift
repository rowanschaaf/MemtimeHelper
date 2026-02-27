import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Button("Quit MemtimeHelper") {
            NSApplication.shared.terminate(nil)
        }
    }
}
