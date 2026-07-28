import SwiftUI
import MacLimitsTrackerCore

/// Системная тема: текущий нативный вид попапа.
struct SystemStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let desktopWidgetController: DesktopWidgetController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ProviderOverview(
                sections: PopupContentBuilder.sections(
                    viewModel.states,
                    history: viewModel.historySamples(providerId:),
                    thresholds: viewModel.severityThresholds),
                theme: .system,
                surface: .menuBar)
            Divider()
            PopupFooter(viewModel: viewModel, desktopWidgetController: desktopWidgetController)
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.title3)
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
            .accessibilityLabel("Refresh")
        }
    }
}
