import SwiftUI
import MacLimitsTrackerCore

/// Тема Terminal: палитра Tokyo Night, тонкие полосы прогресса.
struct TerminalStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let launchAtLogin: LaunchAtLoginManager

    private let mono = Font.system(size: 11, design: .monospaced)

    var body: some View {
        ProviderOverview(
            sections: PopupContentBuilder.sections(
                viewModel.states,
                history: viewModel.historySamples(providerId:),
                thresholds: viewModel.severityThresholds,
                costResult: viewModel.costEstimate,
                surface: .menuBar),
            theme: .terminal,
            surface: .menuBar)
            .font(mono)
            .foregroundStyle(TerminalPalette.fg)
            .padding(16)
            .background(TerminalPalette.bg)
            .environment(\.colorScheme, .dark)
    }
}
