import SwiftUI
import MacLimitsTrackerCore

/// Содержимое попапа статус-бара: две секции (Claude / Codex), футер с обновлением.
public struct StatusBarView: View {
    @ObservedObject var viewModel: LimitsViewModel

    public init(viewModel: LimitsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            claudeSection
            Divider()
            codexSection
            Divider()
            footer
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
        .accessibilityIdentifier("statusBarPopup")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Limits Tracker")
                    .font(.headline)
                Text(latestUpdateText)
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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private var latestUpdateText: String {
        let claudeFetched = viewModel.claude?.fetchedAt ?? .distantPast
        let codexFetched = viewModel.codex?.fetchedAt ?? .distantPast
        let latest = claudeFetched > codexFetched ? claudeFetched : codexFetched
        if latest == .distantPast { return "—" }
        return "Updated \(Self.timeFormatter.string(from: latest))"
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Claude Code", color: .orange)
            if let c = viewModel.claude {
                if let e = c.providerError {
                    errorRow(e)
                } else {
                    detailRow("Plan", value(c.subscriptionType))
                    if let u = c.usage {
                        if let fh = u.fiveHour {
                            detailRow("5h remaining", remainingText(fh))
                            detailRow("5h resets", resetText(fh))
                        } else {
                            placeholder("5h usage unavailable")
                        }
                        if let wk = u.sevenDay {
                            detailRow("Weekly remaining", remainingText(wk))
                            detailRow("Weekly resets", resetText(wk))
                        } else {
                            placeholder("Weekly usage unavailable")
                        }
                    } else if let ue = c.usageError {
                        errorRow(ue)
                    } else {
                        placeholder("Loading usage…")
                    }
                }
            } else {
                placeholder("Loading…")
            }
        }
    }

    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Codex", color: .green)
            if let x = viewModel.codex {
                if let e = x.providerError {
                    errorRow(e)
                } else {
                    let plan = x.usage?.snapshot?.planType ?? x.planType
                    detailRow("Plan", value(plan))
                    if let snap = x.usage?.snapshot {
                        if let fh = snap.primary {
                            detailRow("5h remaining", codexRemaining(fh))
                            detailRow("5h resets", codexReset(fh))
                        } else {
                            placeholder("5h usage unavailable")
                        }
                        if let wk = snap.secondary {
                            detailRow("Weekly remaining", codexRemaining(wk))
                            detailRow("Weekly resets", codexReset(wk))
                        } else {
                            placeholder("Weekly usage unavailable")
                        }
                        if let bal = snap.creditsBalance, !bal.isEmpty {
                            detailRow("Credits", bal)
                        }
                        if let reached = snap.rateLimitReachedType {
                            errorRow("rate limit reached: \(reached)")
                        }
                    } else if let ue = x.usageError {
                        errorRow(ue)
                    } else {
                        placeholder("Loading usage…")
                    }
                    if let auth = x.authMode {
                        detailRow("Auth", auth)
                    }
                    if let email = x.email {
                        detailRow("Account", email)
                    }
                    if let owner = x.accountOwner {
                        detailRow("Org", owner)
                    }
                    if let days = x.daysUntilRenewal {
                        detailRow("Renews in", "\(days) days")
                    }
                    if let until = x.subscriptionActiveUntil {
                        detailRow("Renews", dateOnly(until))
                    }
                }
            } else {
                placeholder("Loading…")
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Auto-refresh (5 min)", isOn: Binding(
                get: { viewModel.autoRefresh },
                set: { viewModel.setAutoRefresh($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - Helpers

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

    private func errorRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.red)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func value(_ s: String?) -> String { s ?? "—" }

    private func remainingText(_ w: ClaudeUsageWindow) -> String {
        // utilization — использованная доля (0…100); осталось — разница.
        let remaining = max(0, 100 - w.utilizationPercent)
        return String(format: "%.0f%%", remaining)
    }

    private func resetText(_ w: ClaudeUsageWindow) -> String {
        guard let r = w.resetsAt else { return "—" }
        return Self.relativeFormatter.localizedString(for: r, relativeTo: Date())
    }

    // usedPercent — ИСПОЛЬЗОВАНО; остаётся = 100 − это (зеркало ClaudeUsageWindow).
    private func codexRemaining(_ w: CodexUsageWindow) -> String {
        String(format: "%.0f%%", max(0, 100 - w.usedPercent))
    }

    private func codexReset(_ w: CodexUsageWindow) -> String {
        guard let r = w.resetsAt else { return "—" }
        return Self.relativeFormatter.localizedString(for: r, relativeTo: Date())
    }

    private func dateOnly(_ d: Date) -> String {
        Self.dateFormatter.string(from: d)
    }
}