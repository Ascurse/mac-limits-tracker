import XCTest
@testable import MacLimitsTrackerCore

final class RefreshIntervalTests: XCTestCase {
    func test_rawValuesStable_forPersistence() {
        // rawValue is persisted in UserDefaults ("autoRefreshInterval") - should not change.
        XCTAssertEqual(RefreshInterval.seconds30.rawValue, "seconds30")
        XCTAssertEqual(RefreshInterval.minute1.rawValue, "minute1")
        XCTAssertEqual(RefreshInterval.minute5.rawValue, "minute5")
        XCTAssertEqual(RefreshInterval.minute15.rawValue, "minute15")
    }

    func test_allCasesOrder() {
        XCTAssertEqual(RefreshInterval.allCases, [.seconds30, .minute1, .minute5, .minute15])
    }

    func test_titles() {
        XCTAssertEqual(RefreshInterval.seconds30.title, "30 sec")
        XCTAssertEqual(RefreshInterval.minute1.title, "1 min")
        XCTAssertEqual(RefreshInterval.minute5.title, "5 min")
        XCTAssertEqual(RefreshInterval.minute15.title, "15 min")
    }

    func test_timeIntervals() {
        XCTAssertEqual(RefreshInterval.seconds30.timeInterval, 30)
        XCTAssertEqual(RefreshInterval.minute1.timeInterval, 60)
        XCTAssertEqual(RefreshInterval.minute5.timeInterval, 300)
        XCTAssertEqual(RefreshInterval.minute15.timeInterval, 900)
    }

    func test_defaultValue() {
        XCTAssertEqual(RefreshInterval.default, .minute5)
    }

    func test_idEqualsRawValue() {
        XCTAssertEqual(RefreshInterval.seconds30.id, RefreshInterval.seconds30.rawValue)
        XCTAssertEqual(RefreshInterval.minute1.id, RefreshInterval.minute1.rawValue)
        XCTAssertEqual(RefreshInterval.minute5.id, RefreshInterval.minute5.rawValue)
        XCTAssertEqual(RefreshInterval.minute15.id, RefreshInterval.minute15.rawValue)
    }
}
