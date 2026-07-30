import Foundation

/// Публичный вход в Cost-домен: сканирует локальные логи Claude/Codex и
/// строит best-effort оценку стоимости за период. НЕ биллинговый API —
/// оценка может расходиться с реальным счётом поставщика (см. `pricingTableVersion`
/// в `CostEstimate` — таблица тарифов зашита в бинарь и обновляется вручную).
///
/// Строго read-only: файлы логов только читаются, ничего не создаётся и не
/// изменяется. В диагностику (`CostDiagnostics`) никогда не попадают пути,
/// session id, промпты или сырой JSON — только счётчики проблем.
public struct LocalCostEstimateService {
    private let claudeRoot: URL
    private let codexRoot: URL
    private let fileManager: FileManager

    public init(
        claudeRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true),
        codexRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
        self.fileManager = fileManager
    }

    public func estimate(
        period: CostPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CostEstimateResult {
        let claudeFiles = LocalCostLogSource.discoverFiles(source: .claude, root: claudeRoot, fileManager: fileManager)
        let codexFiles = LocalCostLogSource.discoverFiles(source: .codex, root: codexRoot, fileManager: fileManager)

        guard !claudeFiles.isEmpty || !codexFiles.isEmpty else {
            return .unavailable(.noLogsFound, diagnostics: CostDiagnostics())
        }

        let range = period.range(now: now, calendar: calendar)
        var records: [CostUsageRecord] = []
        var diagnostics = CostDiagnostics()

        for file in claudeFiles {
            guard let lines = LocalCostLogSource.readLines(of: file, fileManager: fileManager) else {
                diagnostics.unreadableFiles += 1
                continue
            }
            for line in lines {
                collect(ClaudeCostLogParser.parseLine(line), range: range, into: &records, diagnostics: &diagnostics)
            }
        }

        for file in codexFiles {
            guard let lines = LocalCostLogSource.readLines(of: file, fileManager: fileManager) else {
                diagnostics.unreadableFiles += 1
                continue
            }
            for result in CodexCostLogParser.parseFile(lines: lines) {
                collect(result, range: range, into: &records, diagnostics: &diagnostics)
            }
        }

        return CostEstimator.buildResult(records: records, diagnostics: diagnostics)
    }

    private func collect(
        _ result: CostLineParseResult,
        range: CostPeriodRange,
        into records: inout [CostUsageRecord],
        diagnostics: inout CostDiagnostics
    ) {
        switch result {
        case .record(let record):
            if range.contains(record.timestamp) { records.append(record) }
        case .ignored:
            break
        case .malformed:
            diagnostics.malformedLines += 1
        }
    }
}

/// Чистая (без I/O) логика ценообразования и группировки — отдельно от
/// `LocalCostEstimateService`, чтобы её можно было гонять в тестах без диска.
enum CostEstimator {
    private struct GroupKey: Hashable {
        let source: CostSource
        let tariffId: String
    }

    static func buildResult(records: [CostUsageRecord], diagnostics: CostDiagnostics) -> CostEstimateResult {
        guard !records.isEmpty else {
            // Логи просканированы, записей за период нет. Если сканирование было
            // чистым — это настоящий $0.00, а не «недоступно». Если по пути были
            // проблемы (нечитаемые файлы/битые строки) — честнее не утверждать $0.
            if diagnostics.isClean {
                let estimate = CostEstimate(total: 0, breakdown: [], pricingTableVersion: CostPricingTable.version)
                return .available(estimate, diagnostics: diagnostics)
            }
            return .unavailable(.noPricedRecords, diagnostics: diagnostics)
        }

        var runningDiagnostics = diagnostics
        var amounts: [GroupKey: Decimal] = [:]
        var unknownModelNames: Set<String> = []

        for record in records {
            guard let priced = CostPricingTable.rate(forModel: record.model) else {
                unknownModelNames.insert(record.model)
                continue
            }
            let cost = cost(for: record, rate: priced.rate)
            let key = GroupKey(source: record.source, tariffId: priced.tariffId)
            amounts[key, default: 0] += cost
        }
        runningDiagnostics.unknownModels += unknownModelNames.count

        let breakdown = amounts
            .map { CostBreakdownEntry(source: $0.key.source, model: $0.key.tariffId, amount: $0.value) }
            .sorted { ($0.source.rawValue, $0.model) < ($1.source.rawValue, $1.model) }

        guard !breakdown.isEmpty else {
            // Записи были, но ни одна не попала на известный тариф — никогда не
            // подставляем приблизительную цену вместо честного "недоступно".
            return .unavailable(.noPricedRecords, diagnostics: runningDiagnostics)
        }

        let total = breakdown.reduce(Decimal(0)) { $0 + $1.amount }
        let estimate = CostEstimate(total: total, breakdown: breakdown, pricingTableVersion: CostPricingTable.version)

        return runningDiagnostics.isClean
            ? .available(estimate, diagnostics: runningDiagnostics)
            : .incomplete(estimate, diagnostics: runningDiagnostics)
    }

    private static func cost(for record: CostUsageRecord, rate: CostRate) -> Decimal {
        Decimal(record.inputTokens) * rate.inputPerToken
            + Decimal(record.outputTokens) * rate.outputPerToken
            + Decimal(record.cacheCreationTokens) * rate.cacheCreationPerToken
            + Decimal(record.cacheReadTokens) * rate.cacheReadPerToken
    }
}
