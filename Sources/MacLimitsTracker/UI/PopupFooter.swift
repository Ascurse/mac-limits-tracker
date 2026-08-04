import SwiftUI
import MacLimitsTrackerCore

/// Футер попапа: композиция общих секций настроек с поверхностью `.menuBar`
/// и специфичная для попапа кнопка Quit. Состояние — только через ViewModel
/// и инжектированный `LaunchAtLoginManager`; прямых чтений персистентности нет.
struct PopupFooter: View {
    @ObservedObject var viewModel: LimitsViewModel
    let launchAtLogin: LaunchAtLoginManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 8) {
            Button {
                openSettings()
            } label: {
                Label("Open Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .help("Open Settings (⌘,)")
            .accessibilityLabel("Open Settings")
            .keyboardShortcut(",", modifiers: .command)

            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .help("Quit (⌘Q)")
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
