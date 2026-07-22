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

/// Секция попапа одного провайдера.
public struct ProviderSectionContent: Equatable {
    public let descriptor: ProviderDescriptor
    public let title: String
    public let rows: [PopupRow]
}

/// Сборка секций попапа из состояний провайдеров. Чистые функции — покрыты тестами.
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

    /// Единая сборка секции попапа для любого провайдера — надмножество прежних
    /// `claudeSection`/`codexSection`: у Claude просто нет details/credits/renewal
    /// (мапперы оставляют эти поля snapshot'а пустыми).
    public static func section(_ state: ProviderState, now: Date = Date()) -> ProviderSectionContent {
        var rows: [PopupRow] = []
        guard let snap = state.snapshot else {
            rows.append(.note("Loading…"))
            return ProviderSectionContent(descriptor: state.descriptor,
                                          title: state.descriptor.displayName, rows: rows)
        }
        if let e = snap.providerError {
            rows.append(.error(e))
        } else {
            rows.append(.detail(key: "Plan", value: snap.plan ?? "—"))
            if let windows = snap.windows {
                rows.append(contentsOf: windowRows(windows, now: now))
                if let bal = snap.creditsBalance, !bal.isEmpty {
                    rows.append(.detail(key: "Credits", value: bal))
                }
                if let reached = snap.rateLimitReachedType {
                    rows.append(.error("rate limit reached: \(reached)"))
                }
            } else if let ue = snap.usageError {
                rows.append(.error(ue))
            } else {
                rows.append(.note("Loading usage…"))
            }
            for d in snap.details {
                rows.append(.detail(key: d.key, value: d.value))
            }
            if let days = snap.daysUntilRenewal {
                rows.append(.detail(key: "Renews in", value: "\(days) days"))
            }
            if let until = snap.renewalDate, until > now {
                rows.append(.detail(key: "Renews", value: dateFormatter.string(from: until)))
            }
        }
        return ProviderSectionContent(descriptor: state.descriptor,
                                      title: state.descriptor.displayName, rows: rows)
    }

    /// Окна снапшота в уже заданном мапперами порядке; `usedPercent == nil` — слот
    /// заявлен, данных нет («… usage unavailable», раньше было только у Claude).
    private static func windowRows(_ windows: [SnapshotWindow], now: Date) -> [PopupRow] {
        windows.map { w in
            let labels = RateLimitWindowLabel.labels(forDurationMins: w.windowDurationMins)
            return windowRow(short: labels.short, long: labels.long,
                             remaining: w.usedPercent.map { max(0, 100 - $0) },
                             resetsAt: w.resetsAt, now: now,
                             unavailable: "\(labels.long) usage unavailable")
        }
    }

    public static func updatedText(states: [ProviderState]) -> String {
        let latest = states.map { $0.snapshot?.fetchedAt ?? .distantPast }.max() ?? .distantPast
        if latest == .distantPast { return "—" }
        return "Updated \(timeFormatter.string(from: latest))"
    }

    private static func windowRow(short: String, long: String, remaining: Double?,
                                  resetsAt: Date?, now: Date, unavailable: String = "unavailable") -> PopupRow {
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
