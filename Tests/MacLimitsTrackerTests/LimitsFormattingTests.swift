import XCTest
@testable import MacLimitsTrackerCore

final class LimitsFormattingTests: XCTestCase {
    private func claudeWindow(_ utilization: Double, resetsAt: Date? = nil) -> ClaudeUsageWindow {
        ClaudeUsageWindow(utilizationPercent: utilization, resetsAt: resetsAt,
                          limitDollars: nil, usedDollars: nil, remainingDollars: nil)
    }

    private func codexWindow(_ used: Double, resetsAt: Date? = nil) -> CodexUsageWindow {
        CodexUsageWindow(usedPercent: used, windowDurationMins: 300, resetsAt: resetsAt)
    }

    func test_claudeRemainingPercentInvertsUtilization() {
        XCTAssertEqual(LimitsFormatting.claudeRemainingPercent(claudeWindow(22)), 78, accuracy: 0.001)
        XCTAssertEqual(LimitsFormatting.claudeRemainingPercent(claudeWindow(0)), 100, accuracy: 0.001)
        XCTAssertEqual(LimitsFormatting.claudeRemainingPercent(claudeWindow(100)), 0, accuracy: 0.001)
    }

    func test_claudeRemainingPercentFloorsAtZero() {
        XCTAssertEqual(LimitsFormatting.claudeRemainingPercent(claudeWindow(150)), 0, accuracy: 0.001)
    }

    func test_codexRemainingPercentInvertsUsedPercent() {
        XCTAssertEqual(LimitsFormatting.codexRemainingPercent(codexWindow(1)), 99, accuracy: 0.001)
        XCTAssertEqual(LimitsFormatting.codexRemainingPercent(codexWindow(100)), 0, accuracy: 0.001)
        XCTAssertEqual(LimitsFormatting.codexRemainingPercent(codexWindow(120)), 0, accuracy: 0.001)
    }

    func test_remainingTextFormatsWholePercents() {
        XCTAssertEqual(LimitsFormatting.claudeRemainingText(claudeWindow(22.4)), "78%")
        XCTAssertEqual(LimitsFormatting.codexRemainingText(codexWindow(1)), "99%")
    }

    func test_resetTextReturnsDashForNil() {
        XCTAssertEqual(LimitsFormatting.resetText(resetsAt: nil), "—")
    }

    func test_resetTextProducesNonEmptyRelativeString() {
        let now = Date(timeIntervalSince1970: 1_783_800_000)
        let future = now.addingTimeInterval(2 * 3600)
        let text = LimitsFormatting.resetText(resetsAt: future, relativeTo: now)
        XCTAssertFalse(text.isEmpty)
        XCTAssertNotEqual(text, "—")
    }
}
