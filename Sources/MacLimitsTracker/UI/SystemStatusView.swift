import SwiftUI
import MacLimitsTrackerCore

/// Системная тема: текущий нативный вид попапа.
struct SystemStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let desktopWidgetController: DesktopWidgetController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ForEach(viewModel.states) { state in
                Divider()
                section(PopupContentBuilder.section(state))
            }
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

    private func section(_ s: ProviderSectionContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(s.title, color: Color(hex: s.descriptor.accentColorHex),
                         loginHelp: s.descriptor.loginHelp)
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: PopupRow) -> some View {
        switch row {
        case .detail(let key, let value):
            detailRow(key, value)
        case .window(let w):
            detailRow("\(w.longLabel) remaining", w.remainingText)
            detailRow("\(w.longLabel) resets", w.resetText ?? "—")
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        case .note(let text):
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func sectionLabel(_ title: String, color: Color, loginHelp: LoginHelp?) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if let loginHelp {
                Button {
                    openProviderCLI(loginHelp)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help(loginHelp.helpText)
                .accessibilityLabel("Open Claude Code")
            }
        }
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
