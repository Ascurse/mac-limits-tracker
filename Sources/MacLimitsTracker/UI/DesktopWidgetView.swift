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
        let latest = viewModel.states.map {
            SnapshotResolver.resolve($0).snapshot?.fetchedAt ?? .distantPast
        }.max() ?? .distantPast
        if latest == .distantPast { return "—" }
        return Self.timeFormatter.string(from: latest)
    }

    private struct LimitWindow {
        let label: String
        let remainingPercent: Double
        let resetText: String
        let severity: Severity
    }

    /// Только окна с реальными данными — заглушки со `usedPercent == nil` не отображаются
    /// (для них секция целиком покажет «Usage unavailable», как раньше у Claude).
    private func windows(
        for snapshot: LimitsSnapshot?,
        thresholds: SeverityThresholds
    ) -> [LimitWindow] {
        guard let windows = snapshot?.windows else { return [] }
        return windows.compactMap { w in
            guard let used = w.usedPercent else { return nil }
            let label = RateLimitWindowLabel.labels(forDurationMins: w.windowDurationMins).short
            let remainingPercent = LimitsFormatting.remainingPercent(usedPercent: used)
            return LimitWindow(
                label: label,
                remainingPercent: remainingPercent,
                resetText: LimitsFormatting.resetText(resetsAt: w.resetsAt),
                severity: Severity.from(
                    remainingPercent: remainingPercent,
                    thresholds: thresholds
                )
            )
        }
    }

    private func recoveryContent(for state: ProviderState) -> ProviderRecoveryContent? {
        guard let raw = state.snapshot?.providerError ?? state.snapshot?.usageError else { return nil }
        return ProviderErrorRecoveryMapper.recover(rawError: raw, providerName: state.descriptor.displayName)
    }

    private func providerSection(_ state: ProviderState) -> some View {
        let color = Color(hex: state.descriptor.accentColorHex)
        let resolved = SnapshotResolver.resolve(state)
        let recovery = recoveryContent(for: state)
        let items = windows(for: resolved.snapshot, thresholds: viewModel.severityThresholds)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(state.descriptor.shortName)
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            // Stale-проверка раньше error: у stale-состояния ошибка тоже есть,
            // но бары рисуем из last-good.
            if resolved.isStale {
                ForEach(Array(items.enumerated()), id: \.offset) { _, window in
                    windowRow(window, color: color)
                }
                .opacity(StaleAppearance.opacity)
                if let recovery {
                    Label(recovery.primaryText, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .help(recovery.diagnostic)
                        .opacity(StaleAppearance.opacity)
                }
            } else if let recovery {
                Label(recovery.primaryText, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .help(recovery.diagnostic)
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
                .tint(barColor(window.severity, accent: color))
                .scaleEffect(x: 1, y: 0.6, anchor: .center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.label) limit, \(Int(window.remainingPercent.rounded()))% remaining, resets \(window.resetText)")
    }

    private func barColor(_ severity: Severity, accent: Color) -> Color {
        switch severity {
        case .normal: return accent
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
