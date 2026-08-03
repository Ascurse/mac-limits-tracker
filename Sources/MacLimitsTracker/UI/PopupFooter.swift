import SwiftUI
import MacLimitsTrackerCore

/// Футер попапа: композиция общих секций настроек с поверхностью `.menuBar`
/// и специфичная для попапа кнопка Quit. Состояние — только через ViewModel
/// и инжектированный `LaunchAtLoginManager`; прямых чтений персистентности нет.
struct PopupFooter: View {
    @ObservedObject var viewModel: LimitsViewModel
    let launchAtLogin: LaunchAtLoginManager

    var body: some View {
        VStack(spacing: 8) {
            DisplaySettingsSection(viewModel: viewModel, surface: .menuBar)
            RefreshSettingsSection(viewModel: viewModel, surface: .menuBar)
            ProvidersSettingsSection(viewModel: viewModel, surface: .menuBar)
            SystemSettingsSection(viewModel: viewModel, launchAtLogin: launchAtLogin, surface: .menuBar)

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
