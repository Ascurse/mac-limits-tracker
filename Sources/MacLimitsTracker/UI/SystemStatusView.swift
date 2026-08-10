import SwiftUI
import MacLimitsTrackerCore

/// Системная тема: текущий нативный вид попапа.
struct SystemStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let launchAtLogin: LaunchAtLoginManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ProviderOverview(
                sections: PopupContentBuilder.sections(
                    viewModel.states,
                    history: viewModel.historySamples(providerId:),
                    thresholds: viewModel.severityThresholds,
                    costResult: viewModel.costEstimate,
                    showTrends: viewModel.showUsageTrends,
                    showDailyBudget: viewModel.showDailyBudget),
                theme: .system,
                surface: .menuBar)
            Divider()
            PopupFooter(viewModel: viewModel, launchAtLogin: launchAtLogin)
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Limits Tracker")
                    .font(.headline)
                Text(PopupContentBuilder.updatedText(states: viewModel.states))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: viewModel.isRefreshing
                      ? "arrow.triangle.2.circlepath.circle"
                      : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshing)
            .help(viewModel.isRefreshing ? "Refreshing…" : "Refresh (⌘R)")
            .accessibilityLabel("Refresh")
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
