import XCTest
@testable import MacLimitsTrackerCore

final class CodexCostLogParserTests: XCTestCase {
    func test_parseFile_turnContextThenTokenCount_returnsOneRecordWithModelFromTurnContext() {
        let lines = [
            #"{"timestamp":"2026-03-20T08:57:13.340Z","type":"turn_context","payload":{"model":"gpt-5-codex"}}"#,
            #"{"timestamp":"2026-03-20T08:57:21.220Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":999999,"cached_input_tokens":999999,"output_tokens":999999},"last_token_usage":{"input_tokens":17618,"cached_input_tokens":3456,"output_tokens":253}}}}"#
        ]

        let results = CodexCostLogParser.parseFile(lines: lines)

        XCTAssertEqual(results.count, 2, "turn_context — ignored, token_count — record")
        XCTAssertEqual(results[0], .ignored)
        guard case .record(let record) = results[1] else {
            return XCTFail("expected .record")
        }
        XCTAssertEqual(record.source, .codex)
        XCTAssertEqual(record.model, "gpt-5-codex")
        XCTAssertEqual(record.cacheReadTokens, 3456)
        XCTAssertEqual(record.inputTokens, 17618 - 3456, "input_tokens уже включает cached — вычитаем, чтобы не задвоить")
        XCTAssertEqual(record.outputTokens, 253)
        XCTAssertEqual(record.cacheCreationTokens, 0, "у Codex/OpenAI нет понятия cache-creation тарифа")
    }

    func test_parseFile_neverReadsCumulativeTotalTokenUsage() {
        // last_token_usage меньше total_token_usage — если бы парсер по ошибке читал
        // total, эта проверка бы это поймала.
        let lines = [
            #"{"timestamp":"2026-03-20T08:57:13.340Z","type":"turn_context","payload":{"model":"gpt-5-codex"}}"#,
            #"{"timestamp":"2026-03-20T08:57:21.220Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500000,"cached_input_tokens":0,"output_tokens":500000},"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5}}}}"#
        ]

        let results = CodexCostLogParser.parseFile(lines: lines)

        guard case .record(let record) = results[1] else {
            return XCTFail("expected .record")
        }
        XCTAssertEqual(record.inputTokens, 10)
        XCTAssertEqual(record.outputTokens, 5)
    }

    func test_parseFile_tokenCountWithNullInfo_isIgnored() {
        let lines = [
            #"{"timestamp":"2026-03-20T08:57:13.340Z","type":"turn_context","payload":{"model":"gpt-5-codex"}}"#,
            #"{"timestamp":"2026-03-20T08:57:15.612Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#
        ]

        let results = CodexCostLogParser.parseFile(lines: lines)

        XCTAssertEqual(results, [.ignored, .ignored])
    }

    func test_parseFile_tokenCountBeforeAnyTurnContext_isMalformed() {
        let lines = [
            #"{"timestamp":"2026-03-20T08:57:21.220Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1},"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1}}}}"#
        ]

        XCTAssertEqual(CodexCostLogParser.parseFile(lines: lines), [.malformed],
                        "без известной модели цену этой записи посчитать нельзя")
    }

    func test_parseFile_otherEventTypes_areIgnored() {
        let lines = [
            #"{"timestamp":"2026-03-20T08:56:57.028Z","type":"session_meta","payload":{"id":"abc"}}"#,
            #"{"timestamp":"2026-03-20T08:57:13.335Z","type":"response_item","payload":{"type":"message","role":"developer"}}"#,
            #"{"timestamp":"2026-03-20T08:57:13.335Z","type":"event_msg","payload":{"type":"task_started"}}"#
        ]

        XCTAssertEqual(CodexCostLogParser.parseFile(lines: lines), [.ignored, .ignored, .ignored])
    }

    func test_parseFile_invalidJsonLine_isMalformed() {
        XCTAssertEqual(CodexCostLogParser.parseFile(lines: ["not json"]), [.malformed])
    }

    func test_parseFile_laterTurnContextUpdatesModelForSubsequentRecords() {
        let lines = [
            #"{"timestamp":"2026-03-20T08:57:13.340Z","type":"turn_context","payload":{"model":"gpt-5-codex"}}"#,
            #"{"timestamp":"2026-03-20T08:57:21.220Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1},"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5}}}}"#,
            #"{"timestamp":"2026-03-20T09:10:00.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-03-20T09:10:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1},"last_token_usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":8}}}}"#
        ]

        let results = CodexCostLogParser.parseFile(lines: lines)

        guard case .record(let first) = results[1], case .record(let second) = results[3] else {
            return XCTFail("expected two records")
        }
        XCTAssertEqual(first.model, "gpt-5-codex")
        XCTAssertEqual(second.model, "gpt-5.4")
    }
}
