import SwiftUI
import MacLimitsTrackerCore

/// Тема Phosphor: монохромный зелёный CRT.
struct PhosphorStatusView: View {
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
            theme: .phosphor,
            surface: .menuBar)
            .font(mono)
            .foregroundStyle(PhosphorPalette.bright)
            .padding(16)
            .background(PhosphorPalette.bg)
            .environment(\.colorScheme, .dark)
    }
}
