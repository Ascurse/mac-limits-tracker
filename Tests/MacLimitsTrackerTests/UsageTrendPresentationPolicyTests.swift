import Foundation
import XCTest
@testable import MacLimitsTrackerCore

/// Политика представления единого UsageTrendView: маппинг контракта gld.1
/// (SparklineContent) в view-state, общий для всех четырёх тем. Здесь фиксируются
/// инварианты: фиксированная шкала 0...100, severity не только цветом, и
/// loading/error/stale никогда не рисуют ложно-уверенный график.
final class UsageTrendPresentationPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func point(hoursAgo: Double, remaining: Double) -> SparklinePoint {
        SparklinePoint(time: now.addingTimeInterval(-hoursAgo * 3600), remainingPercent: remaining)
    }

    private func content(
        dataState: TrendDataState,
        points: [SparklinePoint],
        currentPercent: Double = 78
    ) -> SparklineContent {
        SparklineContent(
            windowMins: 300,
            shortLabel: "5h",
            windowLabel: "5-hour",
            rangeStart: now.addingTimeInterval(-7 * 24 * 3600),
            rangeEnd: now,
            currentPercent: currentPercent,
            points: points,
            dataState: dataState
        )
    }

    private func state(
        dataState: TrendDataState,
        points: [SparklinePoint],
        currentPercent: Double = 78
    ) -> UsageTrendViewState {
        UsageTrendPresentationPolicy.viewState(
            for: content(dataState: dataState, points: points, currentPercent: currentPercent)
        )
    }

    func test_okState_singleSegmentConfidentLineNoNote() {
        let points = [point(hoursAgo: 10, remaining: 80), point(hoursAgo: 5, remaining: 70),
                      point(hoursAgo: 2, remaining: 60)]
        let s = state(dataState: .ok, points: points)
        XCTAssertEqual(s.segments, [points])
        XCTAssertTrue(s.showsLine)
        XCTAssertNil(s.noteText)
    }

    func test_scale_alwaysFixedZeroToHundredWithLabelledGuides() {
        // Даже если все точки прижаты к 100, автомасштаба нет: домен фиксирован.
        let points = [point(hoursAgo: 3, remaining: 100), point(hoursAgo: 1, remaining: 100)]
        let s = state(dataState: .ok, points: points)
        XCTAssertEqual(s.yDomain, 0...100)
        XCTAssertEqual(s.scaleGuides, [0, 50, 100])
        XCTAssertEqual(s.metricLabel, "remaining %")
    }

    func test_xDomain_matchesContractRange() {
        let c = content(dataState: .ok, points: [point(hoursAgo: 3, remaining: 50),
                                                 point(hoursAgo: 1, remaining: 60)])
        let s = UsageTrendPresentationPolicy.viewState(for: c)
        XCTAssertEqual(s.xDomain, c.rangeStart...c.rangeEnd)
    }

    func test_sparseState_markersOnlyWithFallbackNote() {
        let points = [point(hoursAgo: 1, remaining: 60)]
        let c = content(dataState: .sparse(pointCount: 1, minimumNeeded: 2), points: points)
        let s = UsageTrendPresentationPolicy.viewState(for: c)
        XCTAssertFalse(s.showsLine, "sparse не должен рисовать уверенную линию")
        XCTAssertEqual(s.segments, [points], "точки показываем маркерами, не выбрасываем")
        XCTAssertEqual(s.noteText, c.fallbackText)
        XCTAssertFalse(s.noteText?.isEmpty ?? true)
    }

    func test_gapState_segmentsSplitAtGapWithNote() {
        let points = [point(hoursAgo: 50, remaining: 90), point(hoursAgo: 49, remaining: 88),
                      point(hoursAgo: 2, remaining: 60)]
        let gap: TimeInterval = 47 * 3600
        let threshold: TimeInterval = 24 * 3600
        let c = content(dataState: .gap(largestGapSeconds: gap, thresholdSeconds: threshold),
                        points: points)
        let s = UsageTrendPresentationPolicy.viewState(for: c)
        XCTAssertEqual(s.segments.count, 2, "разрыв больше порога должен разбить линию на сегменты")
        XCTAssertEqual(s.segments.first, Array(points.prefix(2)))
        XCTAssertEqual(s.segments.last, Array(points.suffix(1)))
        XCTAssertTrue(s.showsLine, "внутри сегментов линия рисуется — разрыв виден как дисконтинуити")
        XCTAssertEqual(s.noteText, c.fallbackText)
    }

    func test_emptyState_noSegmentsNoteShown() {
        let s = state(dataState: .empty, points: [])
        XCTAssertTrue(s.segments.isEmpty)
        XCTAssertFalse(s.showsLine)
        XCTAssertEqual(s.noteText, "7d — no history")
    }

    func test_loadingState_noConfidentChart() {
        let s = state(dataState: .loading, points: [])
        XCTAssertTrue(s.segments.isEmpty)
        XCTAssertFalse(s.showsLine)
        XCTAssertEqual(s.noteText, "7d — loading")
    }

    func test_staleState_notConfidentChart() {
        let points = [point(hoursAgo: 30, remaining: 90), point(hoursAgo: 29, remaining: 88)]
        let c = content(dataState: .stale(lastSampleSecondsAgo: 30 * 3600), points: points)
        let s = UsageTrendPresentationPolicy.viewState(for: c)
        XCTAssertFalse(s.showsLine, "stale не должен выглядеть как живой уверенный график")
        XCTAssertEqual(s.segments, [points])
        XCTAssertEqual(s.noteText, c.fallbackText)
    }

    func test_severityCue_notColorOnlySignal() {
        let critical = state(dataState: .ok, points: [], currentPercent: 10)
        XCTAssertEqual(critical.severity, .critical)
        XCTAssertEqual(critical.severityCue, "critical")

        let warning = state(dataState: .ok, points: [], currentPercent: 30)
        XCTAssertEqual(warning.severity, .warning)
        XCTAssertEqual(warning.severityCue, "warning")

        let normal = state(dataState: .ok, points: [], currentPercent: 80)
        XCTAssertEqual(normal.severity, .normal)
        XCTAssertEqual(normal.severityCue, "")
    }

    func test_periodLabels_derivedFromRange() {
        let c = content(dataState: .ok, points: [])
        let s = UsageTrendPresentationPolicy.viewState(for: c)
        XCTAssertEqual(s.trendRangeLabel, "7d")
        XCTAssertFalse(s.periodStartLabel.isEmpty)
        XCTAssertFalse(s.periodEndLabel.isEmpty)
        XCTAssertNotEqual(s.periodStartLabel, s.periodEndLabel)
    }

    func test_accessibility_derivesFromSameModel() {
        let points = [point(hoursAgo: 3, remaining: 80), point(hoursAgo: 1, remaining: 78)]
        let ok = state(dataState: .ok, points: points, currentPercent: 78)
        XCTAssertTrue(ok.accessibilityLabel.contains("5h"))
        XCTAssertTrue(ok.accessibilityValue.contains("78%"))

        let empty = state(dataState: .empty, points: [])
        XCTAssertTrue(empty.accessibilityValue.contains("no history"))

        let critical = state(dataState: .ok, points: points, currentPercent: 10)
        XCTAssertTrue(critical.accessibilityValue.contains("critical"))
    }
}
