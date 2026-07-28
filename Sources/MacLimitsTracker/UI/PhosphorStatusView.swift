import SwiftUI
import MacLimitsTrackerCore

/// Тема Phosphor: монохромный зелёный CRT.
struct PhosphorStatusView: View {
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
                theme: .phosphor,
                surface: .menuBar)
            promptLine
            PopupFooter(viewModel: viewModel, desktopWidgetController: desktopWidgetController)
                .tint(PhosphorPalette.mid)
        }
        .font(mono)
        .foregroundStyle(PhosphorPalette.bright)
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
        .background(PhosphorPalette.bg)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Text("~/limits — \(PopupContentBuilder.updatedText(states: viewModel.states).lowercased())")
                .foregroundStyle(PhosphorPalette.mid)
            Spacer()
            Button {
                viewModel.refresh()
            } label: {
                Text("[r]").foregroundStyle(viewModel.isRefreshing ? PhosphorPalette.dim : PhosphorPalette.bright)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
        }
    }

    // Мигающий курсор — единственная анимация темы. phaseAnimator, а не
    // repeatForever в onAppear: looping-анимация привязана к жизненному циклу
    // вью и корректно перезапускается после переоткрытия окна MenuBarExtra —
    // repeatForever в onAppear при этом рассинхронизировался и курсор замирал.
    private var promptLine: some View {
        HStack(spacing: 2) {
            Text("$").foregroundStyle(PhosphorPalette.mid)
            Text("▮")
                .foregroundStyle(PhosphorPalette.bright)
                .phaseAnimator([false, true]) { content, phase in
                    content.opacity(phase ? 1 : 0)
                } animation: { _ in
                    .easeInOut(duration: 0.6)
                }
        }
    }
}
