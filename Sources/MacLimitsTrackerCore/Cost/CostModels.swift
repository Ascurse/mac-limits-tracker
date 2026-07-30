import Foundation

/// Источник записи об использовании — какой CLI породил лог.
public enum CostSource: String, Equatable {
    case claude
    case codex
}

/// Период агрегации, за который считается оценка стоимости.
public enum CostPeriod: Equatable {
    case today
    case last7Days
    case last30Days

    /// Возвращает полуинтервал `[start, end)` для периода относительно `now`.
    /// `end` всегда равен `now` — записей из будущего не бывает.
    func range(now: Date, calendar: Calendar) -> CostPeriodRange {
        let start: Date
        switch self {
        case .today:
            start = calendar.startOfDay(for: now)
        case .last7Days:
            start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30Days:
            start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        }
        return CostPeriodRange(start: start, end: now)
    }
}

/// Полуинтервал времени `[start, end)` — вся логика «входит ли запись в период»
/// живёт здесь, а не размазана по вызывающему коду.
public struct CostPeriodRange: Equatable {
    public let start: Date
    public let end: Date

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// Одна ценообразуемая запись использования: токены одного вызова модели,
/// извлечённые из локального лога. Внутренний тип — наружу уходит только
/// агрегат `CostEstimateResult`.
struct CostUsageRecord: Equatable {
    let source: CostSource
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
}

/// Счётчики проблем при сканировании — единственный канал сообщения об ошибках.
/// Никогда не содержит путей, session id, промптов или сырого JSON.
public struct CostDiagnostics: Equatable {
    public var malformedLines: Int
    public var unknownModels: Int
    public var unreadableFiles: Int

    public init(malformedLines: Int = 0, unknownModels: Int = 0, unreadableFiles: Int = 0) {
        self.malformedLines = malformedLines
        self.unknownModels = unknownModels
        self.unreadableFiles = unreadableFiles
    }

    /// `true`, если сканирование прошло без единой проблемы — используется,
    /// чтобы отличить «данных действительно нет» от «данные не удалось прочитать».
    public var isClean: Bool {
        malformedLines == 0 && unknownModels == 0 && unreadableFiles == 0
    }

    public static func + (lhs: CostDiagnostics, rhs: CostDiagnostics) -> CostDiagnostics {
        CostDiagnostics(
            malformedLines: lhs.malformedLines + rhs.malformedLines,
            unknownModels: lhs.unknownModels + rhs.unknownModels,
            unreadableFiles: lhs.unreadableFiles + rhs.unreadableFiles
        )
    }
}

/// Одна строка разбивки оценки по источнику и модели.
public struct CostBreakdownEntry: Equatable {
    public let source: CostSource
    public let model: String
    public let amount: Decimal
}

/// Оценённая стоимость за период — сумма и разбивка по моделям.
public struct CostEstimate: Equatable {
    public let total: Decimal
    public let breakdown: [CostBreakdownEntry]
    public let pricingTableVersion: String
}

/// Почему оценка недоступна вовсе (не путать с `incomplete`, где оценка есть,
/// но часть данных не удалось учесть).
public enum CostUnavailableReason: Equatable {
    /// Логи Claude/Codex за период не найдены.
    case noLogsFound
    /// Записи найдены, но ни для одной не нашлось известного тарифа.
    case noPricedRecords
}

/// Итог оценки стоимости за период — best-effort, не биллинговый API-эквивалент.
public enum CostEstimateResult: Equatable {
    /// Все записи учтены и оценены — диагностика чистая.
    case available(CostEstimate, diagnostics: CostDiagnostics)
    /// Часть записей не удалось прочитать/оценить — сумма занижена, диагностика это отражает.
    case incomplete(CostEstimate, diagnostics: CostDiagnostics)
    /// Оценить стоимость не удалось вовсе.
    case unavailable(CostUnavailableReason, diagnostics: CostDiagnostics)
}

/// Общий парсер таймстампов для обоих лог-форматов (Claude и Codex) —
/// повторяет схему `ClaudeUsageParser.iso8601WithFractionalSeconds`.
enum CostTimestampParsing {
    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let wholeSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ string: String) -> Date? {
        withFractionalSeconds.date(from: string) ?? wholeSeconds.date(from: string)
    }
}

/// Результат разбора одной строки лога. Раздельные `.ignored`/`.malformed`
/// нужны, чтобы не считать «не относящиеся к использованию» строки (реплики
/// пользователя, служебные события) ошибками при подсчёте `malformedLines`.
enum CostLineParseResult: Equatable {
    case record(CostUsageRecord)
    case ignored
    case malformed
}

/// Общая валидация счётчика токенов для обоих парсеров: только неотрицательные
/// целые — отрицательное или нечисловое значение делает всю строку malformed.
func costNonNegativeInt(_ value: Any?) -> Int? {
    guard let number = value as? Int, number >= 0 else { return nil }
    return number
}
