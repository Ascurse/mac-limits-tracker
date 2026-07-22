import SwiftUI
import MacLimitsTrackerCore

/// Системная тема: текущий нативный вид попапа.
struct SystemStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            section(PopupContentBuilder.claudeSection(viewModel.claude))
            Divider()
            section(PopupContentBuilder.codexSection(viewModel.codex))
            Divider()
            PopupFooter(viewModel: viewModel)
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
                Text(PopupContentBuilder.updatedText(claude: viewModel.claude, codex: viewModel.codex))
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
            sectionLabel(s.title, color: s.provider == .claude ? .orange : .green)
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

    private func sectionLabel(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
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
