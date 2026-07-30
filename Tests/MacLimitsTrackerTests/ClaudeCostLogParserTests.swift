import XCTest
@testable import MacLimitsTrackerCore

final class ClaudeCostLogParserTests: XCTestCase {
    func test_parseLine_validAssistantLine_returnsRecord() {
        let line = """
        {"type":"assistant","timestamp":"2026-07-29T14:04:57.042Z","message":{"model":"claude-sonnet-4-5-20260101","usage":{"input_tokens":9,"output_tokens":9250,"cache_creation_input_tokens":11654,"cache_read_input_tokens":21617}}}
        """

        guard case .record(let record) = ClaudeCostLogParser.parseLine(line) else {
            return XCTFail("expected .record")
        }
        XCTAssertEqual(record.source, .claude)
        XCTAssertEqual(record.model, "claude-sonnet-4-5-20260101")
        XCTAssertEqual(record.inputTokens, 9)
        XCTAssertEqual(record.outputTokens, 9250)
        XCTAssertEqual(record.cacheCreationTokens, 11654)
        XCTAssertEqual(record.cacheReadTokens, 21617)
        XCTAssertEqual(record.timestamp, CostTimestampParsing.parse("2026-07-29T14:04:57.042Z"))
    }

    func test_parseLine_missingCacheFields_defaultsToZero() {
        let line = """
        {"type":"assistant","timestamp":"2026-07-29T14:04:57Z","message":{"model":"claude-haiku-4-5","usage":{"input_tokens":1,"output_tokens":2}}}
        """

        guard case .record(let record) = ClaudeCostLogParser.parseLine(line) else {
            return XCTFail("expected .record")
        }
        XCTAssertEqual(record.cacheCreationTokens, 0)
        XCTAssertEqual(record.cacheReadTokens, 0)
    }

    func test_parseLine_nonAssistantType_isIgnoredNotMalformed() {
        let line = """
        {"type":"user","timestamp":"2026-07-29T14:04:57Z","message":{"content":"hi"}}
        """

        XCTAssertEqual(ClaudeCostLogParser.parseLine(line), .ignored)
    }

    func test_parseLine_summaryLine_isIgnored() {
        let line = """
        {"type":"summary","summary":"session recap"}
        """

        XCTAssertEqual(ClaudeCostLogParser.parseLine(line), .ignored)
    }

    func test_parseLine_invalidJson_isMalformed() {
        XCTAssertEqual(ClaudeCostLogParser.parseLine("not json at all"), .malformed)
    }

    func test_parseLine_assistantMissingUsage_isMalformed() {
        let line = """
        {"type":"assistant","timestamp":"2026-07-29T14:04:57Z","message":{"model":"claude-sonnet-4-5"}}
        """

        XCTAssertEqual(ClaudeCostLogParser.parseLine(line), .malformed)
    }

    func test_parseLine_assistantMissingModel_isMalformed() {
        let line = """
        {"type":"assistant","timestamp":"2026-07-29T14:04:57Z","message":{"usage":{"input_tokens":1,"output_tokens":1}}}
        """

        XCTAssertEqual(ClaudeCostLogParser.parseLine(line), .malformed)
    }

    func test_parseLine_negativeTokenCount_isMalformed() {
        let line = """
        {"type":"assistant","timestamp":"2026-07-29T14:04:57Z","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":-1,"output_tokens":1}}}
        """

        XCTAssertEqual(ClaudeCostLogParser.parseLine(line), .malformed)
    }

    func test_parseLine_invalidTimestamp_isMalformed() {
        let line = """
        {"type":"assistant","timestamp":"not-a-date","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}
        """

        XCTAssertEqual(ClaudeCostLogParser.parseLine(line), .malformed)
    }
}
