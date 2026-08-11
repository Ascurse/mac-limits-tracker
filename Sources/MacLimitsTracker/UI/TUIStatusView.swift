import SwiftUI
import MacLimitsTrackerCore

/// Тема TUI: панели с рамками и датчиками в духе htop.
struct TUIStatusView: View {
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
            theme: .tui,
            surface: .menuBar)
            .font(mono)
            .foregroundStyle(TuiPalette.fg)
            .padding(16)
            .background(TuiPalette.bg)
            .environment(\.colorScheme, .dark)
    }
}
