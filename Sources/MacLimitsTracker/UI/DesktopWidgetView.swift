import SwiftUI
import MacLimitsTrackerCore

/// Компактная панель на рабочем столе: остатки лимитов обоих провайдеров с прогресс-барами.
struct DesktopWidgetView: View {
    @ObservedObject var viewModel: LimitsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            providerSection(
                title: "Claude",
                color: .orange,
                error: viewModel.claude?.providerError ?? viewModel.claude?.usageError,
                isLoaded: viewModel.claude != nil,
                windows: claudeWindows
            )
            providerSection(
                title: "Codex",
                color: .green,
                error: viewModel.codex?.providerError ?? viewModel.codex?.usageError,
                isLoaded: viewModel.codex != nil,
                windows: codexWindows
            )
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
        let claudeFetched = viewModel.claude?.fetchedAt ?? .distantPast
        let codexFetched = viewModel.codex?.fetchedAt ?? .distantPast
        let latest = max(claudeFetched, codexFetched)
        if latest == .distantPast { return "—" }
        return Self.timeFormatter.string(from: latest)
    }

    private struct LimitWindow {
        let label: String
        let remainingPercent: Double
        let resetText: String
    }

    private var claudeWindows: [LimitWindow] {
        guard let usage = viewModel.claude?.usage else { return [] }
        var windows: [LimitWindow] = []
        if let fh = usage.fiveHour {
            windows.append(LimitWindow(
                label: "5h",
                remainingPercent: LimitsFormatting.claudeRemainingPercent(fh),
                resetText: LimitsFormatting.resetText(resetsAt: fh.resetsAt)
            ))
        }
        if let wk = usage.sevenDay {
            windows.append(LimitWindow(
                label: "week",
                remainingPercent: LimitsFormatting.claudeRemainingPercent(wk),
                resetText: LimitsFormatting.resetText(resetsAt: wk.resetsAt)
            ))
        }
        return windows
    }

    private var codexWindows: [LimitWindow] {
        guard let snapshot = viewModel.codex?.usage?.snapshot else { return [] }
        var windows: [LimitWindow] = []
        if let fh = snapshot.primary {
            windows.append(LimitWindow(
                label: "5h",
                remainingPercent: LimitsFormatting.codexRemainingPercent(fh),
                resetText: LimitsFormatting.resetText(resetsAt: fh.resetsAt)
            ))
        }
        if let wk = snapshot.secondary {
            windows.append(LimitWindow(
                label: "week",
                remainingPercent: LimitsFormatting.codexRemainingPercent(wk),
                resetText: LimitsFormatting.resetText(resetsAt: wk.resetsAt)
            ))
        }
        return windows
    }

    private func providerSection(title: String, color: Color, error: String?,
                                 isLoaded: Bool, windows: [LimitWindow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if !isLoaded {
                Text("Loading…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if windows.isEmpty {
                Text("Usage unavailable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(windows, id: \.label) { window in
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
