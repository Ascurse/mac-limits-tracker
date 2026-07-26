import Foundation

/// Строка попапа. Темы рендерят каждый вид по-своему;
/// порядок строк задаёт PopupContentBuilder — единый для всех тем.
public enum PopupRow: Equatable {
    case detail(key: String, value: String)
    case window(WindowContent)
    case sparkline(SparklineContent)
    case error(String)
    case note(String)
}

/// Одна точка спарклайна: отдельный struct, т.к. кортеж не синтезирует Equatable.
public struct SparklinePoint: Equatable, Sendable {
    public let time: Date
    public let usedPercent: Double

    public init(time: Date, usedPercent: Double) {
        self.time = time
        self.usedPercent = usedPercent
    }
}

/// Спарклайн использования за 24ч для одного окна лимита.
public struct SparklineContent: Equatable, Sendable {
    public let windowMins: Int
    public let shortLabel: String
    public let points: [SparklinePoint]

    public init(windowMins: Int, shortLabel: String, points: [SparklinePoint]) {
        self.windowMins = windowMins
        self.shortLabel = shortLabel
        self.points = points
    }
}

/// Серьёзность остатка лимита: пороги по ОСТАТКУ (не по использованному).
public enum Severity: Equatable, Sendable {
    case normal
    case warning
    case critical

    public static func from(
        remainingPercent: Double,
        thresholds: SeverityThresholds = .standard
    ) -> Severity {
        if remainingPercent <= thresholds.criticalRemaining { return .critical }
        if remainingPercent <= thresholds.warningRemaining { return .warning }
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
    public let isStale: Bool
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
    public static func section(
        _ state: ProviderState,
        now: Date = Date(),
        history: [UsageSample] = [],
        thresholds: SeverityThresholds = .standard
    ) -> ProviderSectionContent {
        let resolved = SnapshotResolver.resolve(state)
        var rows = rows(for: resolved.snapshot, now: now, history: history, thresholds: thresholds)
        if resolved.isStale, let snapshot = resolved.snapshot, let error = resolved.error {
            rows.append(.note("updated \(relativeFormatter.localizedString(for: snapshot.fetchedAt, relativeTo: now))"))
            rows.append(.error(error))
        }
        return ProviderSectionContent(descriptor: state.descriptor,
                                      title: state.descriptor.displayName,
                                      rows: rows,
                                      isStale: resolved.isStale)
    }

    private static func rows(
        for snapshot: LimitsSnapshot?,
        now: Date,
        history: [UsageSample],
        thresholds: SeverityThresholds
    ) -> [PopupRow] {
        guard let snap = snapshot else { return [.note("Loading…")] }
        if let e = snap.providerError { return [.error(e)] }

        var rows: [PopupRow] = [.detail(key: "Plan", value: snap.plan ?? "—")]
        rows.append(contentsOf: usageRows(snap, now: now, history: history, thresholds: thresholds))
        rows.append(contentsOf: snap.details.map { .detail(key: $0.key, value: $0.value) })
        rows.append(contentsOf: renewalRows(snap, now: now))
        return rows
    }

    /// Окна + кредиты + ошибка rate-limit; либо usageError, либо «Loading usage…»,
    /// если usage ещё не загружен.
    private static func usageRows(
        _ snap: LimitsSnapshot,
        now: Date,
        history: [UsageSample],
        thresholds: SeverityThresholds
    ) -> [PopupRow] {
        guard let windows = snap.windows else {
            if let ue = snap.usageError { return [.error(ue)] }
            return [.note("Loading usage…")]
        }
        var rows = windowRows(windows, now: now, history: history, thresholds: thresholds)
        if let bal = snap.creditsBalance, !bal.isEmpty {
            rows.append(.detail(key: "Credits", value: bal))
        }
        if let reached = snap.rateLimitReachedType {
            rows.append(.error("rate limit reached: \(reached)"))
        }
        return rows
    }

    /// Окна снапшота в уже заданном мапперами порядке; `usedPercent == nil` — слот
    /// заявлен, данных нет («… usage unavailable», раньше было только у Claude).
    /// После каждого окна с данными — спарклайн его использования за последние 24ч,
    /// если в истории есть сэмплы; идентичность окна — windowMins, никогда не индекс.
    private static func windowRows(
        _ windows: [SnapshotWindow],
        now: Date,
        history: [UsageSample],
        thresholds: SeverityThresholds
    ) -> [PopupRow] {
        let cutoff = now.addingTimeInterval(-24 * 3600)
        return windows.flatMap { w -> [PopupRow] in
            let labels = RateLimitWindowLabel.labels(forDurationMins: w.windowDurationMins)
            let row = windowRow(short: labels.short, long: labels.long,
                                remaining: w.usedPercent.map { max(0, 100 - $0) },
                                resetsAt: w.resetsAt, now: now,
                                unavailable: "\(labels.long) usage unavailable",
                                thresholds: thresholds)
            guard w.usedPercent != nil, let durationMins = w.windowDurationMins else { return [row] }
            let points = history
                .filter { $0.windowMins == durationMins && $0.fetchedAt >= cutoff }
                .sorted { $0.fetchedAt < $1.fetchedAt }
                .map { SparklinePoint(time: $0.fetchedAt, usedPercent: $0.usedPercent) }
            guard !points.isEmpty else { return [row] }
            let sparkline = SparklineContent(windowMins: durationMins,
                                             shortLabel: labels.short, points: points)
            return [row, .sparkline(sparkline)]
        }
    }

    private static func renewalRows(_ snap: LimitsSnapshot, now: Date) -> [PopupRow] {
        var rows: [PopupRow] = []
        if let days = snap.daysUntilRenewal {
            rows.append(.detail(key: "Renews in", value: "\(days) days"))
        }
        if let until = snap.renewalDate, until > now {
            rows.append(.detail(key: "Renews", value: dateFormatter.string(from: until)))
        }
        return rows
    }

    public static func updatedText(states: [ProviderState]) -> String {
        let latest = states.map { SnapshotResolver.resolve($0).snapshot?.fetchedAt ?? .distantPast }.max() ?? .distantPast
        if latest == .distantPast { return "—" }
        return "Updated \(timeFormatter.string(from: latest))"
    }

    private static func windowRow(short: String, long: String, remaining: Double?,
                                  resetsAt: Date?, now: Date, unavailable: String = "unavailable",
                                  thresholds: SeverityThresholds = .standard) -> PopupRow {
        guard let p = remaining else { return .note(unavailable) }
        return .window(WindowContent(
            shortLabel: short,
            longLabel: long,
            remainingPercent: p,
            remainingText: String(format: "%.0f%%", p),
            resetText: resetsAt.map { relativeFormatter.localizedString(for: $0, relativeTo: now) },
            severity: .from(remainingPercent: p, thresholds: thresholds)
        ))
    }
}
