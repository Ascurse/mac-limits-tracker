import SwiftUI
import MacLimitsTrackerCore

/// Системная тема: текущий нативный вид попапа.
struct SystemStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let launchAtLogin: LaunchAtLoginManager

    var body: some View {
        ProviderOverview(
            sections: PopupContentBuilder.sections(
                viewModel.states,
                history: viewModel.historySamples(providerId:),
                thresholds: viewModel.severityThresholds,
                costResult: viewModel.costEstimate,
                surface: .menuBar),
            theme: .system,
            surface: .menuBar)
            .padding(16)
    }
}
