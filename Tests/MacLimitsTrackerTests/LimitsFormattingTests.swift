import XCTest
@testable import MacLimitsTrackerCore

final class LimitsFormattingTests: XCTestCase {
    func test_remainingPercentInvertsUsedPercent() {
        XCTAssertEqual(LimitsFormatting.remainingPercent(usedPercent: 22), 78, accuracy: 0.001)
        XCTAssertEqual(LimitsFormatting.remainingPercent(usedPercent: 0), 100, accuracy: 0.001)
        XCTAssertEqual(LimitsFormatting.remainingPercent(usedPercent: 100), 0, accuracy: 0.001)
    }

    func test_remainingPercentFloorsAtZero() {
        XCTAssertEqual(LimitsFormatting.remainingPercent(usedPercent: 150), 0, accuracy: 0.001)
        XCTAssertEqual(LimitsFormatting.remainingPercent(usedPercent: 120), 0, accuracy: 0.001)
    }

    func test_remainingTextFormatsWholePercents() {
        XCTAssertEqual(LimitsFormatting.remainingText(usedPercent: 22.4), "78%")
        XCTAssertEqual(LimitsFormatting.remainingText(usedPercent: 1), "99%")
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
