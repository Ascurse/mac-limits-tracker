import Foundation
import XCTest
@testable import MacLimitsTrackerCore

final class DailyBudgetCalculatorTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
    private func calendar(timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    func test_resetAfterLocalDayEnd_scalesRemainingToUsableTime() throws {
        let now = date("2026-07-31T15:00:00Z")
        let resetAt = date("2026-08-02T00:00:00Z")

        let budget = DailyBudgetCalculator.calculate(
            remainingPercent: 50,
            resetAt: resetAt,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(try XCTUnwrap(budget).budgetPercent, 50 * (9.0 / 33.0), accuracy: 0.000_000_001)
        XCTAssertEqual(budget?.resetAt, resetAt)
    }

    func test_resetBeforeLocalDayEnd_allRemainingIsUsableUntilReset() throws {
        let now = date("2026-07-31T15:00:00Z")
        let resetAt = date("2026-07-31T18:00:00Z")
        let budget = DailyBudgetCalculator.calculate(
            remainingPercent: 25,
            resetAt: resetAt,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(try XCTUnwrap(budget).budgetPercent, 25, accuracy: 0.000_000_001)
    }

    func test_missingOrExpiredReset_returnsNil() {
        let now = date("2026-07-31T15:00:00Z")
        XCTAssertNil(DailyBudgetCalculator.calculate(
            remainingPercent: 50,
            resetAt: nil,
            now: now,
            calendar: utcCalendar
        ))
        XCTAssertNil(DailyBudgetCalculator.calculate(
            remainingPercent: 50,
            resetAt: date("2026-07-31T14:59:59Z"),
            now: now,
            calendar: utcCalendar
        ))
        XCTAssertNil(DailyBudgetCalculator.calculate(
            remainingPercent: 50,
            resetAt: now,
            now: now,
            calendar: utcCalendar
        ))
    }

    func test_zeroRemaining_returnsZeroBudget() throws {
        let now = date("2026-07-31T15:00:00Z")
        let resetAt = date("2026-08-01T00:00:00Z")
        let budget = DailyBudgetCalculator.calculate(
            remainingPercent: 0,
            resetAt: resetAt,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(try XCTUnwrap(budget).budgetPercent, 0, accuracy: 0.000_000_001)
    }

    func test_remainingBelowZero_isClampedToZero() throws {
        let now = date("2026-07-31T15:00:00Z")
        let resetAt = date("2026-08-01T00:00:00Z")

        let budget = DailyBudgetCalculator.calculate(
            remainingPercent: -20,
            resetAt: resetAt,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(try XCTUnwrap(budget).budgetPercent, 0, accuracy: 0.000_000_001)
    }

    func test_remainingAbove100_isClampedTo100() throws {
        let now = date("2026-07-31T15:00:00Z")
        let resetAt = date("2026-07-31T18:00:00Z")

        let budget = DailyBudgetCalculator.calculate(
            remainingPercent: 120,
            resetAt: resetAt,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(try XCTUnwrap(budget).budgetPercent, 100, accuracy: 0.000_000_001)
    }

    func test_nonUTCTimeZone_usesLocalDayBoundary() throws {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let now = date("2026-08-01T06:30:00Z")
        let resetAt = date("2026-08-01T08:00:00Z")

        let budget = DailyBudgetCalculator.calculate(
            remainingPercent: 50,
            resetAt: resetAt,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(try XCTUnwrap(budget).budgetPercent, 50.0 / 3.0, accuracy: 0.000_000_001)
    }

    func test_DSTBoundary_usesCalendarDayRatherThan24Hours() throws {
        let calendar = calendar(timeZone: "America/New_York")
        let now = date("2026-03-08T00:30:00-05:00")
        let resetAt = date("2026-03-09T12:00:00-04:00")

        let budget = DailyBudgetCalculator.calculate(
            remainingPercent: 46,
            resetAt: resetAt,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(try XCTUnwrap(budget).budgetPercent, 30, accuracy: 0.000_000_001)
    }
}
