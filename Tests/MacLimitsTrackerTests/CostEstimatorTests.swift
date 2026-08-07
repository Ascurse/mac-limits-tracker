import XCTest
@testable import MacLimitsTrackerCore

final class CostEstimatorBuildResultTests: XCTestCase {
    private func record(
        source: CostSource = .claude,
        model: String,
        input: Int = 0,
        output: Int = 0,
        cacheCreation: Int = 0,
        cacheRead: Int = 0,
        at timestamp: Date = Date()
    ) -> CostUsageRecord {
        CostUsageRecord(
            source: source, timestamp: timestamp, model: model,
            inputTokens: input, outputTokens: output,
            cacheCreationTokens: cacheCreation, cacheReadTokens: cacheRead
        )
    }

    func test_noRecords_cleanDiagnostics_isAvailableWithZeroTotal() {
        let result = CostEstimator.buildResult(records: [], diagnostics: CostDiagnostics())

        guard case .available(let estimate, let diagnostics) = result else {
            return XCTFail("expected .available")
        }
        XCTAssertEqual(estimate.total, 0)
        XCTAssertTrue(estimate.breakdown.isEmpty)
        XCTAssertTrue(diagnostics.isClean)
    }

    func test_noRecords_dirtyDiagnostics_isUnavailable() {
        let result = CostEstimator.buildResult(
            records: [],
            diagnostics: CostDiagnostics(malformedLines: 2)
        )

        guard case .unavailable(let reason, let diagnostics) = result else {
            return XCTFail("expected .unavailable")
        }
        XCTAssertEqual(reason, .noPricedRecords)
        XCTAssertEqual(diagnostics.malformedLines, 2)
    }

    func test_allRecordsPriced_cleanDiagnostics_isAvailable() {
        let records = [
            record(model: "claude-sonnet-4-5", input: 100, output: 50, cacheCreation: 10, cacheRead: 5)
        ]

        let result = CostEstimator.buildResult(records: records, diagnostics: CostDiagnostics())

        guard case .available(let estimate, let diagnostics) = result else {
            return XCTFail("expected .available")
        }
        // 100*3.00e-6 + 50*15.00e-6 + 10*3.75e-6 + 5*0.30e-6 = 0.001089 (точная десятичная сумма).
        XCTAssertEqual(estimate.total, Decimal(string: "0.001089"))
        XCTAssertEqual(estimate.breakdown.count, 1)
        XCTAssertEqual(estimate.breakdown[0].model, "claude-sonnet-4-5")
        XCTAssertEqual(estimate.pricingTableVersion, CostPricingTable.version)
        XCTAssertTrue(diagnostics.isClean)
    }

    func test_mixOfKnownAndUnknownModels_isIncompleteAndExcludesUnknownFromTotal() {
        let records = [
            record(model: "claude-sonnet-4-5", input: 1_000_000, output: 0),
            record(model: "some-unreleased-model", input: 1_000_000, output: 1_000_000)
        ]

        let result = CostEstimator.buildResult(records: records, diagnostics: CostDiagnostics())

        guard case .incomplete(let estimate, let diagnostics) = result else {
            return XCTFail("expected .incomplete")
        }
        XCTAssertEqual(estimate.total, Decimal(string: "3.00"), "неизвестная модель не должна попадать в сумму")
        XCTAssertEqual(estimate.breakdown.count, 1)
        XCTAssertEqual(diagnostics.unknownModels, 1)
    }

    func test_allRecordsUnknownModel_isUnavailableNotZero() {
        let records = [record(model: "totally-unknown", input: 5, output: 5)]

        let result = CostEstimator.buildResult(records: records, diagnostics: CostDiagnostics())

        guard case .unavailable(let reason, let diagnostics) = result else {
            return XCTFail("expected .unavailable — never claim $0 when a record exists but is unpriced")
        }
        XCTAssertEqual(reason, .noPricedRecords)
        XCTAssertEqual(diagnostics.unknownModels, 1)
    }

    func test_unknownModels_countsDistinctModelsNotOccurrences() {
        let records = [
            record(model: "unknown-a", input: 1, output: 1),
            record(model: "unknown-a", input: 1, output: 1),
            record(model: "unknown-b", input: 1, output: 1)
        ]

        let result = CostEstimator.buildResult(records: records, diagnostics: CostDiagnostics())

        guard case .unavailable(_, let diagnostics) = result else {
            return XCTFail("expected .unavailable")
        }
        XCTAssertEqual(diagnostics.unknownModels, 2)
    }

    func test_multipleSourcesAndModels_groupsAndSortsBreakdownDeterministically() {
        let records = [
            record(source: .codex, model: "gpt-5-codex", input: 1_000_000, output: 0),
            record(source: .claude, model: "claude-sonnet-4-5", input: 1_000_000, output: 0),
            record(source: .claude, model: "claude-opus-4-1", input: 1_000_000, output: 0)
        ]

        let result = CostEstimator.buildResult(records: records, diagnostics: CostDiagnostics())

        guard case .available(let estimate, _) = result else {
            return XCTFail("expected .available")
        }
        XCTAssertEqual(estimate.breakdown.map { "\($0.source.rawValue):\($0.model)" }, [
            "claude:claude-opus-4-1",
            "claude:claude-sonnet-4-5",
            "codex:gpt-5-codex"
        ])
    }

    func test_sameModelDifferentAliasesInSameSource_groupIntoOneBreakdownEntry() {
        let records = [
            record(model: "claude-sonnet-4-5-20260101", input: 500_000, output: 0),
            record(model: "claude-sonnet-4-5-20260601", input: 500_000, output: 0)
        ]

        let result = CostEstimator.buildResult(records: records, diagnostics: CostDiagnostics())

        guard case .available(let estimate, _) = result else {
            return XCTFail("expected .available")
        }
        XCTAssertEqual(estimate.breakdown.count, 1, "оба алиаса — один тариф, не должны дробить разбивку")
        XCTAssertEqual(estimate.breakdown[0].model, "claude-sonnet-4-5")
    }

    func test_neverUsesDoubleRoundingErrorProneArithmetic_decimalStaysExact() {
        // Классический пример: 0.1 + 0.2 в Double даёт 0.30000000000000004.
        // Decimal с точными строковыми литералами тарифов обязан остаться точным.
        let records = [record(model: "claude-sonnet-4-5", input: 1, output: 0)]
        let result = CostEstimator.buildResult(records: records, diagnostics: CostDiagnostics())

        guard case .available(let estimate, _) = result else {
            return XCTFail("expected .available")
        }
        XCTAssertEqual(estimate.total, Decimal(string: "0.000003"))
    }
}

final class LocalCostLogSourceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    func test_discoverFiles_missingRoot_returnsEmptyNotError() {
        let missing = tempDir.appendingPathComponent("does-not-exist")
        let files = LocalCostLogSource.discoverFiles(source: .claude, root: missing, fileManager: .default)
        XCTAssertTrue(files.isEmpty)
    }

    func test_discoverFiles_ignoresNonJsonlFiles_andSortsDeterministically() throws {
        try "a".write(to: tempDir.appendingPathComponent("b.jsonl"), atomically: true, encoding: .utf8)
        try "a".write(to: tempDir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        try "a".write(to: tempDir.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let files = LocalCostLogSource.discoverFiles(source: .claude, root: tempDir, fileManager: .default)

        XCTAssertEqual(files.map { $0.url.lastPathComponent }, ["a.jsonl", "b.jsonl"])
        XCTAssertTrue(files.allSatisfy { $0.source == .claude })
    }

    func test_readLines_missingFile_returnsNil() {
        let file = CostLogFile(source: .claude, url: tempDir.appendingPathComponent("gone.jsonl"))
        XCTAssertNil(LocalCostLogSource.readLines(of: file, fileManager: .default))
    }

    func test_readLines_splitsNonEmptyLinesOnly() throws {
        let url = tempDir.appendingPathComponent("x.jsonl")
        try "line1\n\nline2\n".write(to: url, atomically: true, encoding: .utf8)

        let lines = LocalCostLogSource.readLines(of: CostLogFile(source: .claude, url: url), fileManager: .default)

        XCTAssertEqual(lines, ["line1", "line2"])
    }
}

final class LocalCostEstimateServiceIntegrationTests: XCTestCase {
    private var tempDir: URL!
    private var claudeRoot: URL!
    private var codexRoot: URL!
    private let now = ISO8601DateFormatter().date(from: "2026-07-31T12:00:00Z")!

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    override func setUp() {
        super.setUp()
        let fm = FileManager.default
        tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        claudeRoot = tempDir.appendingPathComponent("claude")
        codexRoot = tempDir.appendingPathComponent("codex")

        let fixturesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CostLogs")

        try! fm.copyItem(at: fixturesRoot.appendingPathComponent("claude"), to: claudeRoot)
        try! fm.copyItem(at: fixturesRoot.appendingPathComponent("codex"), to: codexRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    private func service() -> LocalCostEstimateService {
        LocalCostEstimateService(claudeRoot: claudeRoot, codexRoot: codexRoot, fileManager: .default)
    }

    func test_noLogsAtAll_isUnavailableNoLogsFound() {
        let emptyService = LocalCostEstimateService(
            claudeRoot: tempDir.appendingPathComponent("nope-claude"),
            codexRoot: tempDir.appendingPathComponent("nope-codex"),
            fileManager: .default
        )

        let result = emptyService.estimate(period: .today, now: now, calendar: calendar)

        guard case .unavailable(let reason, _) = result else {
            return XCTFail("expected .unavailable")
        }
        XCTAssertEqual(reason, .noLogsFound)
    }

    func test_today_onlyClaudeRecordsInRange_isIncompleteDueToMalformedAndUnknownModel() {
        let result = service().estimate(period: .today, now: now, calendar: calendar)

        guard case .incomplete(let estimate, let diagnostics) = result else {
            return XCTFail("expected .incomplete")
        }
        XCTAssertEqual(estimate.total, Decimal(string: "0.001089"))
        XCTAssertEqual(estimate.breakdown.count, 1)
        XCTAssertEqual(estimate.breakdown[0].model, "claude-sonnet-4-5")
        XCTAssertEqual(diagnostics.malformedLines, 1, "битая строка в claude-фикстуре")
        XCTAssertEqual(diagnostics.unknownModels, 1, "claude-future-6 в диапазоне today")
    }

    func test_last7Days_includesClaudeAndCodexAcrossFiles() {
        let result = service().estimate(period: .last7Days, now: now, calendar: calendar)

        guard case .incomplete(let estimate, let diagnostics) = result else {
            return XCTFail("expected .incomplete")
        }
        XCTAssertEqual(estimate.total, Decimal(string: "0.0030165"))
        XCTAssertEqual(estimate.breakdown.map { "\($0.source.rawValue):\($0.model)" }, [
            "claude:claude-opus-4-1",
            "claude:claude-sonnet-4-5",
            "codex:gpt-5-codex"
        ])
        XCTAssertEqual(diagnostics.malformedLines, 1)
        XCTAssertEqual(diagnostics.unknownModels, 2, "claude-future-6 и gpt-6-preview")
    }

    func test_last30Days_excludesRecordOlderThanThirtyDays() {
        let result = service().estimate(period: .last30Days, now: now, calendar: calendar)

        guard case .incomplete(let estimate, _) = result else {
            return XCTFail("expected .incomplete")
        }
        // Совпадает с last7Days: запись 2026-06-01 старше 30 дней и не должна
        // задвоить вклад claude-opus-4-1 — если бы она просочилась, total был бы больше.
        XCTAssertEqual(estimate.total, Decimal(string: "0.0030165"))
    }
}
