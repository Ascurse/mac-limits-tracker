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

    func test_burnRateContentFormatsRateAndForecast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let burn = BurnRate(
            usedPercentPerHour: 50,
            exhaustionDate: now.addingTimeInterval(1 * 3600),
            windowMins: 300
        )
        let content = LimitsFormatting.burnRateContent(burnRate: burn, shortLabel: "5h", now: now)
        XCTAssertEqual(content.windowMins, 300)
        XCTAssertEqual(content.shortLabel, "5h")
        XCTAssertTrue(content.text.hasPrefix("Burn 5h: +50%/h"))
        XCTAssertTrue(content.text.contains("exhausted in 1h"))
        XCTAssertEqual(content.pace, .fast)
    }

    func test_burnRateContentFormatsSmallRateAndLongForecast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let burn = BurnRate(
            usedPercentPerHour: 0.42,
            exhaustionDate: now.addingTimeInterval(5 * 24 * 3600 + 3 * 3600),
            windowMins: 10080
        )
        let content = LimitsFormatting.burnRateContent(burnRate: burn, shortLabel: "wk", now: now)
        XCTAssertTrue(content.text.hasPrefix("Burn wk: +0.42%/h"))
        XCTAssertTrue(content.text.contains("exhausted in 5d 3h"))
        XCTAssertEqual(content.pace, .slow)
    }
}
