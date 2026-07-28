import SwiftUI
import MacLimitsTrackerCore

/// Тема TUI: панели с рамками и датчиками в духе htop.
struct TUIStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let desktopWidgetController: DesktopWidgetController

    private let mono = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ProviderOverview(
                sections: PopupContentBuilder.sections(
                    viewModel.states,
                    history: viewModel.historySamples(providerId:),
                    thresholds: viewModel.severityThresholds),
                theme: .tui,
                surface: .menuBar)
            PopupFooter(viewModel: viewModel, desktopWidgetController: desktopWidgetController)
                .tint(TuiPalette.normal)
        }
        .font(mono)
        .foregroundStyle(TuiPalette.fg)
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
        .background(TuiPalette.bg)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Text(PopupContentBuilder.updatedText(states: viewModel.states))
                .foregroundStyle(TuiPalette.dim)
            Spacer()
            Button {
                viewModel.refresh()
            } label: {
                keyBadge("F5 refresh")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
        }
    }

    private func keyBadge(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(TuiPalette.border)
            .foregroundStyle(TuiPalette.fg)
    }
}
