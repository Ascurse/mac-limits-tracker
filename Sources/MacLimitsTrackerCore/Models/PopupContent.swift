import Foundation

/// Строка попапа. Темы рендерят каждый вид по-своему;
/// порядок строк задаёт PopupContentBuilder — единый для всех тем.
public enum PopupRow: Equatable {
    case detail(key: String, value: String)
    case window(WindowContent)
    case sparkline(SparklineContent)
    case cost(CostRowContent)
    case error(String)
    case note(String)
}

/// Состояние строки оценки стоимости — зеркало `CostEstimateResult`, но без
/// Core-типов: UI-слой работает только с готовыми строками.
public enum CostRowState: Equatable, Sendable {
    case available
    case incomplete
    case unavailable
}

/// Строка оценки стоимости, готовая к показу. Несёт обязательную маркировку:
/// это оценка (label), источник — локальные логи (sourceText), версия таблицы
/// тарифов (pricingVersion, nil когда оценки нет вовсе) и состояние.
///
/// ВАЖНО (ревью 725.1): в `.incomplete` `CostEstimate.total` — сумма только
/// ИЗВЕСТНЫХ оценённых записей, т.е. нижняя граница. valueText тогда имеет
/// вид «≥ $X», а indicatorText явно говорит о неполноте — никогда не
/// показываем неполную сумму как окончательный итог.
public struct CostRowContent: Equatable, Sendable {
    public let state: CostRowState
    public let label: String           // "Cost estimate"
    public let valueText: String       // "$12.34" / "≥ $12.34" / "unavailable"
    public let sourceText: String      // "local logs"
    public let pricingVersion: String? // версия тарифной таблицы
    public let indicatorText: String?  // неполнота/причина недоступности

    public init(state: CostRowState, label: String, valueText: String,
                sourceText: String, pricingVersion: String?, indicatorText: String?) {
        self.state = state
        self.label = label
        self.valueText = valueText
        self.sourceText = sourceText
        self.pricingVersion = pricingVersion
        self.indicatorText = indicatorText
    }

    /// Сноска под значением: источник, версия тарифов и (если есть) индикатор
    /// неполноты/причина недоступности — темы только стилизуют её.
    public var footnoteText: String {
        var parts = [sourceText]
        if let pricingVersion { parts.append("pricing \(pricingVersion)") }
        if let indicatorText { parts.append(indicatorText) }
        return parts.joined(separator: " · ")
    }
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

/// Тренд использования за трейлинг 7 дней для одного окна лимита. rangeStart/rangeEnd —
/// границы периода, чтобы рендереры показывали подписи диапазона независимо от хранилища.
public struct SparklineContent: Equatable, Sendable {
    public let windowMins: Int
    public let shortLabel: String
    public let rangeStart: Date
    public let rangeEnd: Date
    public let points: [SparklinePoint]

    public init(windowMins: Int, shortLabel: String, rangeStart: Date, rangeEnd: Date, points: [SparklinePoint]) {
        self.windowMins = windowMins
        self.shortLabel = shortLabel
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
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

    public static func worst(
        in states: [ProviderState],
        thresholds: SeverityThresholds = .standard
    ) -> Severity {
        var worst: Severity = .normal
        for state in states {
            let resolved = SnapshotResolver.resolve(state)
            guard let snapshot = resolved.snapshot,
                  (resolved.isStale || SnapshotResolver.isGood(snapshot)),
                  let windows = snapshot.windows else { continue }
            for window in windows {
                guard let usedPercent = window.usedPercent else { continue }
                let severity = from(
                    remainingPercent: max(0, 100 - usedPercent),
                    thresholds: thresholds
                )
                if isMoreSevere(severity, than: worst) {
                    worst = severity
                    if worst == .critical { return .critical }
                }
            }
        }
        return worst
    }

    private static func isMoreSevere(_ lhs: Severity, than rhs: Severity) -> Bool {
        switch (lhs, rhs) {
        case (.critical, .normal), (.critical, .warning), (.warning, .normal):
            return true
        default:
            return false
        }
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

    /// Пакетная сборка секций для всех состояний — единое правило
    /// «state + history(providerId) + thresholds → ProviderSectionContent»,
    /// которое раньше дублировалось во всех 4 темах попапа.
    /// `costResult` (агрегат по всем провайдерам, обновляется независимо от
    /// квот) добавляет отдельную секцию оценки стоимости в конец.
    public static func sections(
        _ states: [ProviderState],
        now: Date = Date(),
        history: (String) -> [UsageSample] = { _ in [] },
        thresholds: SeverityThresholds = .standard,
        costResult: CostEstimateResult? = nil
    ) -> [ProviderSectionContent] {
        var result = states.map { section($0, now: now, history: history($0.descriptor.id), thresholds: thresholds) }
        if let costResult { result.append(costSection(costResult)) }
        return result
    }

    // MARK: - Оценка стоимости

    /// Дескриптор секции оценки стоимости: агрегат по локальным логам всех
    /// CLI, а не провайдер реестра — поэтому секция синтетическая.
    public static let costDescriptor = ProviderDescriptor(
        id: "cost", displayName: "Cost estimate", shortName: "Cost",
        menuBarSymbol: "$", accentColorHex: 0x8E8E93, loginHelp: nil)

    /// Форматтер денежной суммы оценки: всегда USD, два знака — Decimal
    /// округляется до центов на отображении, расчёт остаётся точным.
    /// Локаль en_US (не POSIX): POSIX форматирует валюту с пробелом («$ 1.23»).
    private static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    /// Секция оценки стоимости из агрегированного результата Core-сервиса.
    public static func costSection(_ result: CostEstimateResult) -> ProviderSectionContent {
        ProviderSectionContent(descriptor: costDescriptor,
                               title: costDescriptor.displayName,
                               rows: [costRow(result)],
                               isStale: false)
    }

    /// Маппинг ТОЛЬКО агрегата `CostEstimateResult` (bd 725.2). В `.incomplete`
    /// total — нижняя граница (сумма известных оценённых записей), поэтому
    /// показываем «≥ $X» с явным индикатором неполноты, а не итог.
    public static func costRow(_ result: CostEstimateResult) -> PopupRow {
        switch result {
        case .available(let estimate, _):
            return .cost(CostRowContent(
                state: .available,
                label: "Cost estimate",
                valueText: moneyText(estimate.total),
                sourceText: "local logs",
                pricingVersion: estimate.pricingTableVersion,
                indicatorText: nil))
        case .incomplete(let estimate, _):
            return .cost(CostRowContent(
                state: .incomplete,
                label: "Cost estimate",
                valueText: "≥ \(moneyText(estimate.total))",
                sourceText: "local logs",
                pricingVersion: estimate.pricingTableVersion,
                indicatorText: "lower bound — some usage unpriced"))
        case .unavailable(let reason, _):
            let reasonText: String
            switch reason {
            case .noLogsFound: reasonText = "no local logs found"
            case .noPricedRecords: reasonText = "no priced records in logs"
            }
            return .cost(CostRowContent(
                state: .unavailable,
                label: "Cost estimate",
                valueText: "unavailable",
                sourceText: "local logs",
                pricingVersion: nil,
                indicatorText: reasonText))
        }
    }

    private static func moneyText(_ amount: Decimal) -> String {
        moneyFormatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
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

    /// Диапазон тренда использования — трейлинг 7 дней.
    private static let trendRangeDays: Double = 7

    /// Окна снапшота в уже заданном мапперами порядке; `usedPercent == nil` — слот
    /// заявлен, данных нет («… usage unavailable», раньше было только у Claude).
    /// После каждого окна с данными — тренд его использования за последние 7 дней,
    /// если в истории есть ≥2 сэмплов (1 точка тренда не рисует); идентичность
    /// окна — windowMins, никогда не индекс.
    private static func windowRows(
        _ windows: [SnapshotWindow],
        now: Date,
        history: [UsageSample],
        thresholds: SeverityThresholds
    ) -> [PopupRow] {
        let rangeStart = now.addingTimeInterval(-Self.trendRangeDays * 24 * 3600)
        let rangeEnd = now

        var groupedHistory: [Int: [SparklinePoint]] = [:]
        for sample in history where sample.fetchedAt >= rangeStart && sample.fetchedAt <= rangeEnd {
            let point = SparklinePoint(time: sample.fetchedAt, usedPercent: sample.usedPercent)
            groupedHistory[sample.windowMins, default: []].append(point)
        }

        return windows.flatMap { w -> [PopupRow] in
            let labels = RateLimitWindowLabel.labels(forDurationMins: w.windowDurationMins)
            let row = windowRow(short: labels.short, long: labels.long,
                                remaining: w.usedPercent.map { max(0, 100 - $0) },
                                resetsAt: w.resetsAt, now: now,
                                unavailable: "\(labels.long) usage unavailable",
                                thresholds: thresholds)
            guard w.usedPercent != nil, let durationMins = w.windowDurationMins else { return [row] }

            let rawPoints = groupedHistory[durationMins] ?? []
            let points = trendPoints(from: rawPoints, rangeStart: rangeStart, rangeEnd: rangeEnd)

            guard points.count >= 2 else { return [row] }
            let sparkline = SparklineContent(windowMins: durationMins, shortLabel: labels.short,
                                             rangeStart: rangeStart, rangeEnd: rangeEnd, points: points)
            return [row, .sparkline(sparkline)]
        }
    }

    /// Даунсэмплинг сэмплов до максимум `maxPoints` точек: диапазон делится на равные
    /// бакеты, из каждого бакета берётся ПОСЛЕДНИЙ (не максимум) сэмпл — тренд должен
    /// показывать актуальное состояние на момент бакета, а не пиковое значение.
    private static func trendPoints(
        from samples: [SparklinePoint],
        rangeStart: Date,
        rangeEnd: Date,
        maxPoints: Int = 24
    ) -> [SparklinePoint] {
        // samples is already sorted by time from HistoryStore
        guard samples.count > maxPoints else { return samples }

        let totalInterval = rangeEnd.timeIntervalSince(rangeStart)
        guard totalInterval > 0 else { return Array(samples.suffix(maxPoints)) }

        let bucketDuration = totalInterval / Double(maxPoints)
        var latestByBucket: [Int: SparklinePoint] = [:]
        for point in samples {
            let offset = point.time.timeIntervalSince(rangeStart)
            let bucketIndex = min(maxPoints - 1, max(0, Int(offset / bucketDuration)))
            latestByBucket[bucketIndex] = point
        }
        return latestByBucket.keys.sorted().compactMap { latestByBucket[$0] }
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
