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

    private var latestUpdateText: String {
        let claudeFetched = viewModel.claude?.fetchedAt ?? .distantPast
        let codexFetched = viewModel.codex?.fetchedAt ?? .distantPast
        let latest = claudeFetched > codexFetched ? claudeFetched : codexFetched
        if latest == .distantPast { return "—" }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return "Updated \(f.string(from: latest))"
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Claude Code", color: .orange)
            if let c = viewModel.claude {
                if let e = c.providerError {
                    errorRow(e)
                } else {
                    detailRow("Subscription", value(c.subscriptionType))
                    detailRow("Auth", value(c.authMethod))
                    detailRow("Account", value(c.email))
                    if let today = c.today {
                        detailRow("Today", "\(today.messageCount) msgs")
                        detailRow("Tokens today", compact(today.tokens))
                    } else if let latest = c.latestDay {
                        detailRow("Last activity \(latest.date)",
                                  "\(latest.messageCount) msgs")
                        detailRow("Tokens that day", compact(latest.tokens))
                    }
                    if let total = c.totalMessages, let sess = c.totalSessions {
                        detailRow("Total", "\(total) msgs · \(sess) sessions")
                    }
                    detailRow("Last refresh", value(c.lastComputedDate))
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
                    detailRow("Plan", value(x.planType))
                    detailRow("Auth", value(x.authMode))
                    detailRow("Account", value(x.email))
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

    private func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func dateOnly(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }
}