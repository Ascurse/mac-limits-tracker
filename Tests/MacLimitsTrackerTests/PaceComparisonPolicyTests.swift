import XCTest
@testable import MacLimitsTrackerCore

final class PaceComparisonPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func test_validWindow_calculatesQuotaTimeAndDelta() {
        let window = SnapshotWindow(windowDurationMins: 100, usedPercent: 20,
                                    resetsAt: now.addingTimeInterval(50 * 60))

        let result = PaceComparisonPolicy.make(window: window, windowLabel: "Week", burnRate: nil, now: now)

        XCTAssertEqual(result.quotaRemainingPercent, 80)
        XCTAssertEqual(result.timeRemainingPercent, 50)
        XCTAssertEqual(result.paceDeltaPercent, 30)
        XCTAssertEqual(result.status, .collectingHistory)
    }

    func test_usedPercent_isClampedBeforeCalculatingQuota() {
        let window = SnapshotWindow(windowDurationMins: 100, usedPercent: 140,
                                    resetsAt: now.addingTimeInterval(50 * 60))

        let result = PaceComparisonPolicy.make(window: window, windowLabel: "Week", burnRate: nil, now: now)

        XCTAssertEqual(result.quotaRemainingPercent, 0)
    }

    func test_missingInputs_areUnavailable() {
        let cases = [
            SnapshotWindow(windowDurationMins: nil, usedPercent: 20, resetsAt: now),
            SnapshotWindow(windowDurationMins: 100, usedPercent: nil, resetsAt: now),
            SnapshotWindow(windowDurationMins: 100, usedPercent: 20, resetsAt: nil)
        ]

        for window in cases {
            XCTAssertEqual(
                PaceComparisonPolicy.make(window: window, windowLabel: "Week", burnRate: nil, now: now).status,
                .unavailable
            )
        }
    }

    func test_pastReset_clampsTimeToZero() {
        let window = SnapshotWindow(windowDurationMins: 100, usedPercent: 20,
                                    resetsAt: now.addingTimeInterval(-1))

        let result = PaceComparisonPolicy.make(window: window, windowLabel: "Week", burnRate: nil, now: now)

        XCTAssertEqual(result.timeRemainingPercent, 0)
        XCTAssertEqual(result.status, .collectingHistory)
    }

    func test_forecastBeforeReset_isAtRisk() {
        let reset = now.addingTimeInterval(100 * 60)
        let window = SnapshotWindow(windowDurationMins: 100, usedPercent: 20, resetsAt: reset)
        let burn = BurnRate(usedPercentPerHour: 1, exhaustionDate: reset.addingTimeInterval(-1), windowMins: 100)

        let result = PaceComparisonPolicy.make(window: window, windowLabel: "Week", burnRate: burn, now: now)

        XCTAssertEqual(result.status, .atRisk)
        XCTAssertEqual(result.forecastAt, burn.exhaustionDate)
    }

    func test_forecastAtOrAfterReset_isOnPace() {
        let reset = now.addingTimeInterval(100 * 60)
        let window = SnapshotWindow(windowDurationMins: 100, usedPercent: 20, resetsAt: reset)
        let burn = BurnRate(usedPercentPerHour: 1, exhaustionDate: reset, windowMins: 100)

        let result = PaceComparisonPolicy.make(window: window, windowLabel: "Week", burnRate: burn, now: now)

        XCTAssertEqual(result.status, .onPace)
    }
}
