import XCTest
@testable import MacLimitsTrackerCore

final class AsciiBarTests: XCTestCase {
    func test_empty_full_half() {
        XCTAssertEqual(AsciiBar.render(remainingPercent: 0), String(repeating: "░", count: 14))
        XCTAssertEqual(AsciiBar.render(remainingPercent: 100), String(repeating: "█", count: 14))
        XCTAssertEqual(AsciiBar.render(remainingPercent: 50),
                       String(repeating: "█", count: 7) + String(repeating: "░", count: 7))
    }

    func test_clampsOutOfRange() {
        XCTAssertEqual(AsciiBar.render(remainingPercent: -5), String(repeating: "░", count: 14))
        XCTAssertEqual(AsciiBar.render(remainingPercent: 140), String(repeating: "█", count: 14))
    }

    func test_customWidth() {
        XCTAssertEqual(AsciiBar.render(remainingPercent: 50, width: 4), "██░░")
    }
}

final class TuiGaugeTests: XCTestCase {
    func test_boundaries() {
        XCTAssertEqual(TuiGauge.filledCount(remainingPercent: 0), 0)
        XCTAssertEqual(TuiGauge.filledCount(remainingPercent: 100), 14)
        XCTAssertEqual(TuiGauge.filledCount(remainingPercent: 50), 7)
    }

    func test_clampsOutOfRange() {
        XCTAssertEqual(TuiGauge.filledCount(remainingPercent: -1), 0)
        XCTAssertEqual(TuiGauge.filledCount(remainingPercent: 101), 14)
    }

    func test_customWidth() {
        XCTAssertEqual(TuiGauge.filledCount(remainingPercent: 25, width: 8), 2)
    }
}

final class AsciiSparklineTests: XCTestCase {
    func test_render_empty_returnsEmptyString() {
        XCTAssertEqual(AsciiSparkline.render(usedPercents: []), "")
    }

    func test_render_singleValue_returnsSingleBlock() {
        XCTAssertEqual(AsciiSparkline.render(usedPercents: [0]), "▁")
        XCTAssertEqual(AsciiSparkline.render(usedPercents: [100]), "█")
        XCTAssertEqual(AsciiSparkline.render(usedPercents: [50]), "▄")
    }

    func test_render_zeroAndHundred_mapToLowestAndHighestBlock() {
        XCTAssertEqual(AsciiSparkline.render(usedPercents: [0, 100]), "▁█")
    }

    func test_render_valuesClamp_outOfRange() {
        XCTAssertEqual(AsciiSparkline.render(usedPercents: [-20, 150]), "▁█")
    }

    func test_render_moreValuesThanWidth_bucketsToWidth() {
        let result = AsciiSparkline.render(usedPercents: [0, 100, 0, 100], width: 2)
        XCTAssertEqual(result, "██")
        XCTAssertEqual(result.count, 2)
    }
}

final class AsciiSparklineTrendTests: XCTestCase {
    private func trend(_ usedPercents: [Double]) -> SparklineContent {
        let now = Date()
        let points = usedPercents.enumerated().map { i, value in
            SparklinePoint(time: now.addingTimeInterval(TimeInterval(i * 3600)), usedPercent: value)
        }
        return SparklineContent(windowMins: 300, shortLabel: "5h",
                                rangeStart: now.addingTimeInterval(-7 * 24 * 3600),
                                rangeEnd: now, points: points)
    }

    func test_renderTrend_emptyPoints_returnsEmptyString() {
        XCTAssertEqual(AsciiSparkline.render(trend([])), "")
    }

    func test_renderTrend_fewerPointsThanWidth_rendersOneBlockPerPoint() {
        XCTAssertEqual(AsciiSparkline.render(trend([0, 50, 100]), width: 24), "▁▄█")
    }

    func test_renderTrend_morePointsThanWidth_bucketsDownToWidth() {
        // 48 точек истории → ровно 24 глифа; каждый бакет из двух точек даёт максимум 90.
        let values = (0..<48).map { $0 % 2 == 0 ? 10.0 : 90.0 }
        let result = AsciiSparkline.render(trend(values), width: 24)
        XCTAssertEqual(result.count, 24)
        XCTAssertEqual(result, String(repeating: "▇", count: 24))
    }

    func test_renderTrend_bucketKeepsPeakNotAverage() {
        XCTAssertEqual(AsciiSparkline.render(trend([10, 90, 20, 80]), width: 2), "▇▆")
    }

    func test_renderTrend_explicitWidth_respected() {
        let result = AsciiSparkline.render(trend([0, 100, 0, 100, 0]), width: 5)
        XCTAssertEqual(result, "▁█▁█▁")
        XCTAssertEqual(result.count, 5)
    }
}
