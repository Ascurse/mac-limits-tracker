import XCTest
@testable import MacLimitsTrackerCore

final class CodexModelsTests: XCTestCase {
    func test_labelsForDurationMins_returnsUnknownForNil() {
        let labels = RateLimitWindowLabel.labels(forDurationMins: nil)
        XCTAssertEqual(labels.short, "?")
        XCTAssertEqual(labels.long, "Unknown")
    }

    func test_labelsForDurationMins_returns5hFor300() {
        let labels = RateLimitWindowLabel.labels(forDurationMins: 300)
        XCTAssertEqual(labels.short, "5h")
        XCTAssertEqual(labels.long, "5h")
    }

    func test_labelsForDurationMins_returnsWeeklyFor10080() {
        let labels = RateLimitWindowLabel.labels(forDurationMins: 10080)
        XCTAssertEqual(labels.short, "wk")
        XCTAssertEqual(labels.long, "Weekly")
    }

    func test_labelsForDurationMins_formatsMinutesLessThanHour() {
        let labels = RateLimitWindowLabel.labels(forDurationMins: 45)
        XCTAssertEqual(labels.short, "45m")
        XCTAssertEqual(labels.long, "45m")
    }

    func test_labelsForDurationMins_formatsExactHours() {
        let labels = RateLimitWindowLabel.labels(forDurationMins: 120)
        XCTAssertEqual(labels.short, "2h")
        XCTAssertEqual(labels.long, "2h")
    }

    func test_labelsForDurationMins_formatsMixedHoursAndMinutes() {
        let labels = RateLimitWindowLabel.labels(forDurationMins: 90)
        XCTAssertEqual(labels.short, "1h30m")
        XCTAssertEqual(labels.long, "1h30m")
    }
}
