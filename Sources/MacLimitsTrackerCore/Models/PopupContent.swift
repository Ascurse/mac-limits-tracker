import Foundation

/// Строка попапа. Темы рендерят каждый вид по-своему;
/// порядок строк задаёт PopupContentBuilder — единый для всех тем.
public enum PopupRow: Equatable {
    case detail(key: String, value: String)
    case window(WindowContent)
    case error(String)
    case note(String)
}

/// Серьёзность остатка лимита: пороги по ОСТАТКУ (не по использованному).
public enum Severity: Equatable {
    case normal
    case warning
    case critical

    public static func from(remainingPercent: Double) -> Severity {
        if remainingPercent <= 15 { return .critical }
        if remainingPercent <= 40 { return .warning }
        return .normal
    }
}

/// Одно окно лимита, готовое к показу.
public struct WindowContent: Equatable {
    public let shortLabel: String       // "5h" / "wk" — компактные темы
    public let longLabel: String        // "5h" / "Weekly" — системная тема
    public let remainingPercent: Double // 0…100, остаток
    public let remainingText: String    // "72%"
    public let resetText: String?       // "in 2 hours" / nil
    public let severity: Severity
}

public enum PopupProvider: Equatable {
    case claude
    case codex
}

/// Секция попапа одного провайдера.
public struct ProviderSectionContent: Equatable {
    public let provider: PopupProvider
    public let title: String
    public let rows: [PopupRow]
}

/// Сборка секций попапа из статусов провайдеров. Чистые функции — покрыты тестами.
public enum PopupContentBuilder {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

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

    public static func claudeSection(_ status: ClaudeStatus?, now: Date = Date()) -> ProviderSectionContent {
        var rows: [PopupRow] = []
        if let c = status {
            if let e = c.providerError {
                rows.append(.error(e))
            } else {
                rows.append(.detail(key: "Plan", value: c.subscriptionType ?? "—"))
                if let u = c.usage {
                    rows.append(windowRow(short: "5h", long: "5h",
                                          remaining: u.fiveHour.map { max(0, 100 - $0.utilizationPercent) },
                                          resetsAt: u.fiveHour?.resetsAt, now: now,
                                          unavailable: "5h usage unavailable"))
                    rows.append(windowRow(short: "wk", long: "Weekly",
                                          remaining: u.sevenDay.map { max(0, 100 - $0.utilizationPercent) },
                                          resetsAt: u.sevenDay?.resetsAt, now: now,
                                          unavailable: "Weekly usage unavailable"))
                } else if let ue = c.usageError {
                    rows.append(.error(ue))
                } else {
                    rows.append(.note("Loading usage…"))
                }
            }
        } else {
            rows.append(.note("Loading…"))
        }
        return ProviderSectionContent(provider: .claude, title: "Claude Code", rows: rows)
    }

    public static func codexSection(_ status: CodexStatus?, now: Date = Date()) -> ProviderSectionContent {
        var rows: [PopupRow] = []
        if let x = status {
            if let e = x.providerError {
                rows.append(.error(e))
            } else {
                // Приоритет: live planType из app-server над JWT-claimом.
                let plan = x.usage?.snapshot?.planType ?? x.planType
                rows.append(.detail(key: "Plan", value: plan ?? "—"))
                if let snap = x.usage?.snapshot {
                    rows.append(windowRow(short: "5h", long: "5h",
                                          remaining: snap.primary.map { max(0, 100 - $0.usedPercent) },
                                          resetsAt: snap.primary?.resetsAt, now: now,
                                          unavailable: "5h usage unavailable"))
                    rows.append(windowRow(short: "wk", long: "Weekly",
                                          remaining: snap.secondary.map { max(0, 100 - $0.usedPercent) },
                                          resetsAt: snap.secondary?.resetsAt, now: now,
                                          unavailable: "Weekly usage unavailable"))
                    if let bal = snap.creditsBalance, !bal.isEmpty {
                        rows.append(.detail(key: "Credits", value: bal))
                    }
                    if let reached = snap.rateLimitReachedType {
                        rows.append(.error("rate limit reached: \(reached)"))
                    }
                } else if let ue = x.usageError {
                    rows.append(.error(ue))
                } else {
                    rows.append(.note("Loading usage…"))
                }
                if let auth = x.authMode { rows.append(.detail(key: "Auth", value: auth)) }
                if let email = x.email { rows.append(.detail(key: "Account", value: email)) }
                if let owner = x.accountOwner { rows.append(.detail(key: "Org", value: owner)) }
                if let days = x.daysUntilRenewal {
                    rows.append(.detail(key: "Renews in", value: "\(days) days"))
                }
                if let until = x.subscriptionActiveUntil {
                    rows.append(.detail(key: "Renews", value: dateFormatter.string(from: until)))
                }
            }
        } else {
            rows.append(.note("Loading…"))
        }
        return ProviderSectionContent(provider: .codex, title: "Codex", rows: rows)
    }

    public static func updatedText(claude: ClaudeStatus?, codex: CodexStatus?) -> String {
        let claudeFetched = claude?.fetchedAt ?? .distantPast
        let codexFetched = codex?.fetchedAt ?? .distantPast
        let latest = max(claudeFetched, codexFetched)
        if latest == .distantPast { return "—" }
        return "Updated \(timeFormatter.string(from: latest))"
    }

    private static func windowRow(short: String, long: String, remaining: Double?,
                                  resetsAt: Date?, now: Date, unavailable: String) -> PopupRow {
        guard let p = remaining else { return .note(unavailable) }
        return .window(WindowContent(
            shortLabel: short,
            longLabel: long,
            remainingPercent: p,
            remainingText: String(format: "%.0f%%", p),
            resetText: resetsAt.map { relativeFormatter.localizedString(for: $0, relativeTo: now) },
            severity: .from(remainingPercent: p)
        ))
    }
}
