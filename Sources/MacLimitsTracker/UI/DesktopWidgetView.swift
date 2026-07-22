import SwiftUI
import MacLimitsTrackerCore

/// Компактная панель на рабочем столе: остатки лимитов всех провайдеров с прогресс-барами.
struct DesktopWidgetView: View {
    @ObservedObject var viewModel: LimitsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach(viewModel.states) { state in
                providerSection(state)
            }
        }
        .padding(14)
        .frame(width: 260)
        // Живой материал в borderless-панели на уровне десктопа схлопывается
        // в чёрный фон после закрытия попапа — заливаем явно.
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("desktopWidget")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.subheadline)
            Text("Limits Tracker")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(latestUpdateText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private var latestUpdateText: String {
        let latest = viewModel.states.map { $0.snapshot?.fetchedAt ?? .distantPast }.max() ?? .distantPast
        if latest == .distantPast { return "—" }
        return Self.timeFormatter.string(from: latest)
    }

    private struct LimitWindow {
        let label: String
        let remainingPercent: Double
        let resetText: String
    }

    /// Только окна с реальными данными — заглушки со `usedPercent == nil` не отображаются
    /// (для них секция целиком покажет «Usage unavailable», как раньше у Claude).
    private func windows(for snapshot: LimitsSnapshot?) -> [LimitWindow] {
        guard let windows = snapshot?.windows else { return [] }
        return windows.compactMap { w in
            guard let used = w.usedPercent else { return nil }
            let label = RateLimitWindowLabel.labels(forDurationMins: w.windowDurationMins).short
            return LimitWindow(
                label: label,
                remainingPercent: LimitsFormatting.remainingPercent(usedPercent: used),
                resetText: LimitsFormatting.resetText(resetsAt: w.resetsAt)
            )
        }
    }

    private func providerSection(_ state: ProviderState) -> some View {
        let color = Color(hex: state.descriptor.accentColorHex)
        let error = state.snapshot?.providerError ?? state.snapshot?.usageError
        let items = windows(for: state.snapshot)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(state.descriptor.shortName)
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if state.snapshot == nil {
                Text("Loading…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if items.isEmpty {
                Text("Usage unavailable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                // id по offset, а не по label: у двух окон может совпасть длительность
                // (например два «5h»), и коллизия по label схлопнет строки.
                ForEach(Array(items.enumerated()), id: \.offset) { _, window in
                    windowRow(window, color: color)
                }
            }
        }
    }

    private func windowRow(_ window: LimitWindow, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.caption2.monospacedDigit())
                Text("· resets \(window.resetText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ProgressView(value: window.remainingPercent, total: 100)
                .tint(color)
                .scaleEffect(x: 1, y: 0.6, anchor: .center)
        }
    }
}
