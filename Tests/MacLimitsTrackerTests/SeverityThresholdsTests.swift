import XCTest
@testable import MacLimitsTrackerCore

final class SeverityThresholdsTests: XCTestCase {

    func test_init_withValidValues_preservesValues() {
        let t = SeverityThresholds(warningRemaining: 40, criticalRemaining: 15)
        XCTAssertEqual(t.warningRemaining, 40)
        XCTAssertEqual(t.criticalRemaining, 15)
    }

    func test_init_whenCriticalEqualsWarningMinusOne_preservesValues() {
        let t = SeverityThresholds(warningRemaining: 40, criticalRemaining: 39)
        XCTAssertEqual(t.warningRemaining, 40)
        XCTAssertEqual(t.criticalRemaining, 39)
    }

    func test_init_whenCriticalEqualsWarning_clampsCritical() {
        let t = SeverityThresholds(warningRemaining: 40, criticalRemaining: 40)
        XCTAssertEqual(t.warningRemaining, 40)
        XCTAssertEqual(t.criticalRemaining, 39)
    }

    func test_init_whenCriticalExceedsWarning_clampsCritical() {
        let t = SeverityThresholds(warningRemaining: 40, criticalRemaining: 50)
        XCTAssertEqual(t.warningRemaining, 40)
        XCTAssertEqual(t.criticalRemaining, 39)
    }

    func test_init_defaults() {
        let t = SeverityThresholds()
        XCTAssertEqual(t.warningRemaining, 40)
        XCTAssertEqual(t.criticalRemaining, 15)
    }

    /// Инвариант: critical строго ниже warning, иначе зона warning недостижима.
    func test_init_clampsCriticalBelowWarning() {
        let t = SeverityThresholds(warningRemaining: 20, criticalRemaining: 25)
        XCTAssertEqual(t.warningRemaining, 20)
        XCTAssertLessThan(t.criticalRemaining, t.warningRemaining)
    }

    func test_standard_matchesHardcodedDefaults() {
        XCTAssertEqual(SeverityThresholds.standard.warningRemaining, 40)
        XCTAssertEqual(SeverityThresholds.standard.criticalRemaining, 15)
    }
}
