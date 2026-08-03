import Foundation

/// Строка попапа. Темы рендерят каждый вид по-своему;
/// порядок строк задаёт PopupContentBuilder — единый для всех тем.
public enum PopupRow: Equatable {
    case detail(key: String, value: String)
    case window(WindowContent)
    case sparkline(SparklineContent)
    case burnRate(BurnRateContent)
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

/// Метрика тренда: единый контракт на уровне presentation, чтобы рендереры
/// всех тем не преобразовывали used↔remaining по-разному.
public enum TrendMetric: Equatable, Sendable {
    /// Остаток окна в процентах (0–100), как у строки summary рядом.
    case remainingPercent
}

/// Состояние данных тренда: рендерер должен отличать реальный тренд от
/// недостаточных/пропущенных данных.
public enum TrendDataState: Equatable, Sendable {
    case ok
    /// Недостаточно точек для уверенной линии.
    case sparse(pointCount: Int, minimumNeeded: Int)
    /// Слишком большой разрыв между соседними точками — нельзя рисовать сплошную линию.
    case gap(largestGapSeconds: TimeInterval, thresholdSeconds: TimeInterval)
    case empty
    case loading
    /// Последняя точка слишком старая.
    case stale(lastSampleSecondsAgo: TimeInterval)
}

/// Одна точка тренда: отдельный struct, т.к. кортеж не синтезирует Equatable.
public struct SparklinePoint: Equatable, Sendable {
    public let time: Date
    public let remainingPercent: Double

    public init(time: Date, remainingPercent: Double) {
        self.time = time
        self.remainingPercent = max(0, min(100, remainingPercent))
    }
}

/// Единый presentation-контракт 7-дневного тренда для одного окна лимита.
/// metric — остаток (0–100), rangeStart/rangeEnd — границы окна, points отсортированы
/// хронологически и клемпированы, dataState явно говорит, можно ли рисовать линию.
public struct SparklineContent: Equatable, Sendable {
    public let metric: TrendMetric
    public let windowMins: Int
    public let shortLabel: String
    public let windowLabel: String
    public let rangeStart: Date
    public let rangeEnd: Date
    public let currentPercent: Double
    public let points: [SparklinePoint]
    public let dataState: TrendDataState

    public var fallbackText: String {
        switch dataState {
        case .ok:
            return ""
        case .sparse(let pointCount, let minimumNeeded):
            return "7d — \(pointCount) sample\(pointCount == 1 ? "" : "s"), need \(minimumNeeded)"
        case .gap(let largestGapSeconds, let thresholdSeconds):
            let hours = Int(largestGapSeconds / 3600)
            return "7d — data gap (\(hours)h > \(Int(thresholdSeconds / 3600))h)"
        case .empty:
            return "7d — no history"
        case .loading:
            return "7d — loading"
        case .stale(let lastSampleSecondsAgo):
            let hours = Int(lastSampleSecondsAgo / 3600)
            return "7d — stale (last sample \(hours)h ago)"
        }
    }

    public init(
        metric: TrendMetric = .remainingPercent,
        windowMins: Int,
        shortLabel: String,
        windowLabel: String,
        rangeStart: Date,
        rangeEnd: Date,
        currentPercent: Double,
        points: [SparklinePoint],
        dataState: TrendDataState
    ) {
        self.metric = metric
        self.windowMins = windowMins
        self.shortLabel = shortLabel
        self.windowLabel = windowLabel
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.currentPercent = max(0, min(100, currentPercent))
        self.points = points
        self.dataState = dataState
    }
}

/// Скорость расхода окна лимита: относительно продолжительности самого окна,
/// чтобы не путать «быстро» для 5-часового и недельного окон.
public enum BurnRatePace: Equatable, Sendable {
    case fast
    case moderate
    case slow
}

/// Текстовое представление burn rate и прогноза исчерпания для одного окна.
public struct BurnRateContent: Equatable, Sendable {
    public let windowMins: Int
    public let shortLabel: String
    public let text: String
    public let pace: BurnRatePace

    public init(windowMins: Int, shortLabel: String, text: String, pace: BurnRatePace) {
        self.windowMins = windowMins
        self.shortLabel = shortLabel
        self.text = text
        self.pace = pace
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

        return windows.flatMap { w -> [PopupRow] in
            let labels = RateLimitWindowLabel.labels(forDurationMins: w.windowDurationMins)
            let row = windowRow(short: labels.short, long: labels.long,
                                remaining: w.usedPercent.map { max(0, 100 - $0) },
                                resetsAt: w.resetsAt, now: now,
                                unavailable: "\(labels.long) usage unavailable",
                                thresholds: thresholds)
            guard let usedPercent = w.usedPercent, let durationMins = w.windowDurationMins else { return [row] }

            var rows: [PopupRow] = [row]

            if let burnRate = BurnRateCalculator.calculate(
                samples: history,
                windowMins: durationMins,
                currentUsedPercent: usedPercent,
                currentResetsAt: w.resetsAt,
                now: now
            ) {
                rows.append(.burnRate(LimitsFormatting.burnRateContent(
                    burnRate: burnRate,
                    shortLabel: labels.short,
                    now: now
                )))
            }

            let samples = history.filter {
                $0.windowMins == durationMins && $0.fetchedAt >= rangeStart && $0.fetchedAt <= rangeEnd
            }
            let trend = trendContent(
                samples: samples,
                windowMins: durationMins,
                shortLabel: labels.short,
                windowLabel: labels.long,
                currentUsedPercent: usedPercent,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd
            )

            // UsageTrendView обрабатывает все состояния контракта сам:
            // ok → полный график, sparse/stale → только маркеры с note,
            // gap → разорванная линия с note, empty → пропускаем (не шумим).
            switch trend.dataState {
            case .empty:
                break
            default:
                rows.append(.sparkline(trend))
            }

            return rows
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
        return (0..<maxPoints).compactMap { latestByBucket[$0] }
    }

    /// Минимальное число точек для уверенной линии тренда.
    private static let trendMinPoints = 2
    /// Максимальный разрыв между соседними точками, при котором ещё можно рисовать
    /// сплошную линию. Больше — явный dataState `.gap`.
    private static let trendGapThreshold: TimeInterval = 24 * 3600

    /// Строит единый presentation-контракт 7-дневного тренда из сырых `UsageSample`.
    /// Здесь единственное преобразование usedPercent → remainingPercent (100 - used).
    /// Возвращает SparklineContent с отсортированными, клемпированными точками,
    /// явным dataState и fallbackText для рендереров.
    internal static func trendContent(
        samples: [UsageSample],
        windowMins: Int,
        shortLabel: String,
        windowLabel: String,
        currentUsedPercent: Double,
        rangeStart: Date,
        rangeEnd: Date,
        minPoints: Int = trendMinPoints,
        gapThreshold: TimeInterval = trendGapThreshold,
        maxPoints: Int = 24
    ) -> SparklineContent {
        let currentPercent = max(0, min(100, 100 - currentUsedPercent))

        // Единственное преобразование used → remaining в presentation boundary.
        var points: [SparklinePoint] = samples.map {
            SparklinePoint(time: $0.fetchedAt, remainingPercent: 100 - $0.usedPercent)
        }

        // Контракт: хронологический порядок, независимо от порядка сэмплов на входе.
        points.sort { $0.time < $1.time }

        // Одинаковые timestamp — оставляем последнее значение, чтобы не было
        // наложенных точек на линии.
        points = points.reduce(into: [SparklinePoint]()) { result, point in
            if let last = result.last, last.time == point.time {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }

        // Ограничиваем диапазоном тренда.
        points = points.filter { $0.time >= rangeStart && $0.time <= rangeEnd }

        let dataState: TrendDataState
        if points.isEmpty {
            dataState = .empty
        } else if points.count < minPoints {
            dataState = .sparse(pointCount: points.count, minimumNeeded: minPoints)
        } else {
            var largestGap: TimeInterval = 0
            for i in 1..<points.count {
                let gap = points[i].time.timeIntervalSince(points[i - 1].time)
                largestGap = max(largestGap, gap)
            }
            if largestGap > gapThreshold {
                dataState = .gap(largestGapSeconds: largestGap, thresholdSeconds: gapThreshold)
            } else {
                dataState = .ok
            }
        }

        // Даунсэмплинг только для уверенного тренда, чтобы не портить визуальную
        // плотность при большом числе точек.
        let renderPoints: [SparklinePoint]
        if case .ok = dataState {
            renderPoints = trendPoints(from: points, rangeStart: rangeStart, rangeEnd: rangeEnd, maxPoints: maxPoints)
        } else {
            renderPoints = points
        }

        return SparklineContent(
            metric: .remainingPercent,
            windowMins: windowMins,
            shortLabel: shortLabel,
            windowLabel: windowLabel,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            currentPercent: currentPercent,
            points: renderPoints,
            dataState: dataState
        )
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
