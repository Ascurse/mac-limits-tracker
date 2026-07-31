import XCTest
@testable import MacLimitsTrackerCore

/// Тесты чистого калькулятора burn rate / time-to-exhaustion (GH #30).
/// Окна идентифицируются по `windowMins`; недостаток данных, нулевой/отрицательный
/// темп или несовпадение окна подавляют результат.
final class BurnRateCalculatorTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(
        windowMins: Int = 300,
        minutesAgo: Double,
        used: Double,
        resetsAt: Date? = nil
    ) -> UsageSample {
        UsageSample(
            providerId: "claude",
            windowMins: windowMins,
            fetchedAt: Self.now.addingTimeInterval(-minutesAgo * 60),
            usedPercent: used,
            resetsAt: resetsAt
        )
    }

    private func calculate(
        samples: [UsageSample],
        windowMins: Int = 300,
        currentUsed: Double,
        currentResetsAt: Date? = nil,
        now: Date? = nil
    ) -> BurnRate? {
        BurnRateCalculator.calculate(
            samples: samples,
            windowMins: windowMins,
            currentUsedPercent: currentUsed,
            currentResetsAt: currentResetsAt,
            now: now ?? Self.now
        )
    }

    // MARK: - нормальный случай

    func test_normalFiveHourWindow_returnsRateAndForecast() {
        let reset = Self.now.addingTimeInterval(5 * 3600)
        let samples = [
            sample(minutesAgo: 120, used: 50, resetsAt: reset),
            sample(minutesAgo: 60, used: 65, resetsAt: reset),
            sample(minutesAgo: 15, used: 78, resetsAt: reset),
        ]
        let rate = calculate(samples: samples, currentUsed: 80, currentResetsAt: reset)
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate?.windowMins, 300)
        // Скорость: 30% за 2 часа -> ~15.4 %/ч.
        let perHour = rate?.usedPercentPerHour ?? 0
        XCTAssertEqual(perHour, 15.4, accuracy: 0.5)
        // Осталось 20% при ~15.4%/ч -> ~1.3 часа, внутри 5-часового окна.
        XCTAssertGreaterThan(rate?.exhaustionDate ?? .distantPast, Self.now)
        XCTAssertLessThan(rate?.exhaustionDate ?? .distantFuture, reset)
    }

    func test_normalWeeklyWindow_returnsRateAndForecast() {
        let reset = Self.now.addingTimeInterval(7 * 24 * 3600)
        // Недельное окно: рост 1% в час, текущий 50%.
        let samples = [
            sample(windowMins: 10080, minutesAgo: 24 * 60, used: 25, resetsAt: reset),
            sample(windowMins: 10080, minutesAgo: 12 * 60, used: 38, resetsAt: reset),
            sample(windowMins: 10080, minutesAgo: 60, used: 49, resetsAt: reset),
        ]
        let rate = calculate(samples: samples, windowMins: 10080, currentUsed: 50, currentResetsAt: reset)
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate?.windowMins, 10080)
        XCTAssertGreaterThan(rate?.usedPercentPerHour ?? 0, 0)
        XCTAssertLessThan(rate?.exhaustionDate ?? .distantFuture, reset)
    }

    // MARK: - подавление при недостатке/некорректных данных

    func test_insufficientSamples_returnsNil() {
        let samples = [
            sample(minutesAgo: 60, used: 10),
            sample(minutesAgo: 5, used: 20),
        ]
        XCTAssertNil(calculate(samples: samples, currentUsed: 22))
    }

    func test_emptyHistory_returnsNil() {
        XCTAssertNil(calculate(samples: [], currentUsed: 50))
    }

    func test_flatHistory_returnsNil() {
        let samples = (0..<5).map { i in
            sample(minutesAgo: Double(i + 1) * 30, used: 30)
        }
        XCTAssertNil(calculate(samples: samples, currentUsed: 30))
    }

    func test_negativeTrend_returnsNil() {
        let samples = [
            sample(minutesAgo: 120, used: 40),
            sample(minutesAgo: 60, used: 30),
            sample(minutesAgo: 15, used: 20),
        ]
        XCTAssertNil(calculate(samples: samples, currentUsed: 18))
    }

    func test_wrongWindowMins_returnsNil() {
        let samples = [
            sample(windowMins: 300, minutesAgo: 120, used: 10),
            sample(windowMins: 300, minutesAgo: 60, used: 16),
            sample(windowMins: 300, minutesAgo: 15, used: 22),
        ]
        XCTAssertNil(calculate(samples: samples, windowMins: 10080, currentUsed: 24))
    }

    func test_forecastBeyondReset_returnsNil() {
        let reset = Self.now.addingTimeInterval(2 * 3600)
        let samples = [
            sample(minutesAgo: 120, used: 10, resetsAt: reset),
            sample(minutesAgo: 60, used: 15, resetsAt: reset),
            sample(minutesAgo: 15, used: 20, resetsAt: reset),
        ]
        // При current 50% и умеренном положительном тренде исчерпание наступит
        // позже ресета окна -> результат должен подавляться.
        XCTAssertNil(calculate(samples: samples, currentUsed: 50, currentResetsAt: reset))
    }

    // MARK: - шумные данные

    func test_jumpyHistoryWithPositiveTrend_returnsRate() {
        let reset = Self.now.addingTimeInterval(5 * 3600)
        let samples = [
            sample(minutesAgo: 180, used: 10, resetsAt: reset),
            sample(minutesAgo: 120, used: 25, resetsAt: reset),
            sample(minutesAgo: 60, used: 15, resetsAt: reset),
            sample(minutesAgo: 30, used: 40, resetsAt: reset),
            sample(minutesAgo: 10, used: 35, resetsAt: reset),
        ]
        // Шумные скачки с положительным трендом; текущий 70% -> осталось 30%.
        let rate = calculate(samples: samples, currentUsed: 70, currentResetsAt: reset)
        XCTAssertNotNil(rate)
        XCTAssertGreaterThan(rate?.usedPercentPerHour ?? 0, 0)
        XCTAssertLessThan(rate?.exhaustionDate ?? .distantFuture, reset)
    }

    // MARK: - граничные случаи

    func test_samplesSpanTooShort_returnsNil() {
        let samples = [
            sample(minutesAgo: 5, used: 10),
            sample(minutesAgo: 3, used: 12),
            sample(minutesAgo: 1, used: 14),
        ]
        XCTAssertNil(calculate(samples: samples, currentUsed: 15))
    }

    func test_currentUsedAt100_returnsNil() {
        let reset = Self.now.addingTimeInterval(5 * 3600)
        let samples = [
            sample(minutesAgo: 60, used: 50, resetsAt: reset),
            sample(minutesAgo: 30, used: 75, resetsAt: reset),
            sample(minutesAgo: 10, used: 90, resetsAt: reset),
        ]
        XCTAssertNil(calculate(samples: samples, currentUsed: 100, currentResetsAt: reset))
    }

    func test_samplesFromPreviousResetIgnored() {
        let reset = Self.now.addingTimeInterval(5 * 3600)
        let previousReset = Self.now.addingTimeInterval(-1 * 3600)
        let samples = [
            sample(minutesAgo: 400, used: 80, resetsAt: previousReset),
            sample(minutesAgo: 300, used: 90, resetsAt: previousReset),
            sample(minutesAgo: 60, used: 10, resetsAt: reset),
            sample(minutesAgo: 30, used: 20, resetsAt: reset),
            sample(minutesAgo: 10, used: 30, resetsAt: reset),
        ]
        let rate = calculate(samples: samples, currentUsed: 35, currentResetsAt: reset)
        XCTAssertNotNil(rate)
        // Предыдущие точки должны быть отброшены, иначе тренд был бы отрицательным/плоским.
        XCTAssertGreaterThan(rate?.usedPercentPerHour ?? 0, 0)
    }
}
