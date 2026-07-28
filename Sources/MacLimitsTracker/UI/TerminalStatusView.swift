import SwiftUI
import MacLimitsTrackerCore

/// Тема Terminal: палитра Tokyo Night, тонкие полосы прогресса.
struct TerminalStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let launchAtLogin: LaunchAtLoginManager

    private let mono = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ProviderOverview(
                sections: PopupContentBuilder.sections(
                    viewModel.states,
                    history: viewModel.historySamples(providerId:),
                    thresholds: viewModel.severityThresholds),
                theme: .terminal,
                surface: .menuBar)
            Rectangle().fill(TerminalPalette.track).frame(height: 1)
            PopupFooter(viewModel: viewModel, launchAtLogin: launchAtLogin)
                .tint(TerminalPalette.cyan)
        }
        .font(mono)
        .foregroundStyle(TerminalPalette.fg)
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
        .background(TerminalPalette.bg)
        .environment(\.colorScheme, .dark) // системные контролы читаемы на тёмном фоне
    }

    private var header: some View {
        HStack {
            Text("limits-tracker").foregroundStyle(TerminalPalette.cyan)
            Spacer()
            Text(PopupContentBuilder.updatedText(states: viewModel.states))
                .foregroundStyle(TerminalPalette.dim)
            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(viewModel.isRefreshing ? TerminalPalette.dim : TerminalPalette.cyan)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
        }
    }
}
