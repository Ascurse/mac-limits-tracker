import XCTest
@testable import MacLimitsTrackerCore

final class CostPeriodRangeTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func test_today_startsAtMidnightAndEndsAtNow() {
        let now = ISO8601DateFormatter().date(from: "2026-07-31T15:30:00Z")!
        let range = CostPeriod.today.range(now: now, calendar: calendar)

        XCTAssertEqual(range.start, ISO8601DateFormatter().date(from: "2026-07-31T00:00:00Z")!)
        XCTAssertEqual(range.end, now)
    }

    func test_last7Days_startsSevenDaysBeforeNow() {
        let now = ISO8601DateFormatter().date(from: "2026-07-31T15:30:00Z")!
        let range = CostPeriod.last7Days.range(now: now, calendar: calendar)

        XCTAssertEqual(range.start, ISO8601DateFormatter().date(from: "2026-07-24T15:30:00Z")!)
        XCTAssertEqual(range.end, now)
    }

    func test_last30Days_startsThirtyDaysBeforeNow() {
        let now = ISO8601DateFormatter().date(from: "2026-07-31T15:30:00Z")!
        let range = CostPeriod.last30Days.range(now: now, calendar: calendar)

        XCTAssertEqual(range.start, ISO8601DateFormatter().date(from: "2026-07-01T15:30:00Z")!)
        XCTAssertEqual(range.end, now)
    }

    func test_contains_isHalfOpenInterval() {
        let start = ISO8601DateFormatter().date(from: "2026-07-24T15:30:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-07-31T15:30:00Z")!
        let range = CostPeriodRange(start: start, end: end)

        XCTAssertTrue(range.contains(start), "start включён")
        XCTAssertFalse(range.contains(end), "end не включён — полуинтервал")
        XCTAssertTrue(range.contains(start.addingTimeInterval(1)))
        XCTAssertFalse(range.contains(start.addingTimeInterval(-1)))
    }
}

final class CostDiagnosticsTests: XCTestCase {
    func test_isClean_trueWhenAllCountersZero() {
        XCTAssertTrue(CostDiagnostics().isClean)
    }

    func test_isClean_falseWhenAnyCounterNonZero() {
        XCTAssertFalse(CostDiagnostics(malformedLines: 1).isClean)
        XCTAssertFalse(CostDiagnostics(unknownModels: 1).isClean)
        XCTAssertFalse(CostDiagnostics(unreadableFiles: 1).isClean)
    }

    func test_plus_sumsCountersFieldByField() {
        let a = CostDiagnostics(malformedLines: 1, unknownModels: 2, unreadableFiles: 3)
        let b = CostDiagnostics(malformedLines: 10, unknownModels: 20, unreadableFiles: 30)

        let sum = a + b

        XCTAssertEqual(sum.malformedLines, 11)
        XCTAssertEqual(sum.unknownModels, 22)
        XCTAssertEqual(sum.unreadableFiles, 33)
    }
}

final class CostTimestampParsingTests: XCTestCase {
    func test_parse_acceptsFractionalSeconds() {
        let date = CostTimestampParsing.parse("2026-07-31T15:30:00.123Z")
        XCTAssertNotNil(date)
    }

    func test_parse_acceptsWholeSeconds() {
        let date = CostTimestampParsing.parse("2026-07-31T15:30:00Z")
        XCTAssertNotNil(date)
    }

    func test_parse_rejectsGarbage() {
        XCTAssertNil(CostTimestampParsing.parse("not-a-date"))
        XCTAssertNil(CostTimestampParsing.parse(""))
    }
}
