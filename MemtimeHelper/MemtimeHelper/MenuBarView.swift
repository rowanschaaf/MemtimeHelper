import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(state.statusMessage, systemImage: state.statusIcon)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Divider()

            Button("Dump Claude AX Tree…") {
                if let path = AXTreeDumper.dump(bundleID: "com.anthropic.claudefordesktop") {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                } else {
                    NSSound.beep()
                }
            }

            Button("Quit MemtimeHelper") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(4)
    }
}
