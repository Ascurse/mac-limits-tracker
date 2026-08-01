import Foundation

/// Результат расчёта burn rate: скорость расхода лимита в процентах за час и
/// прогнозируемый момент исчерпания остатка.
public struct BurnRate: Equatable, Sendable {
    public let usedPercentPerHour: Double
    public let exhaustionDate: Date
    public let windowMins: Int

    public init(usedPercentPerHour: Double, exhaustionDate: Date, windowMins: Int) {
        self.usedPercentPerHour = usedPercentPerHour
        self.exhaustionDate = exhaustionDate
        self.windowMins = windowMins
    }
}

/// Чистый калькулятор burn rate / time-to-exhaustion над историей `UsageSample`.
/// Окно идентифицируется по `windowMins`; недостаток данных, нулевой/отрицательный
/// темп или несовпадение окна подавляют результат (возвращается `nil`).
public enum BurnRateCalculator {
    /// Минимальное число сэмплов истории для надёжного расчёта тренда.
    private static let minimumSampleCount = 3
    /// Минимальный разброс времени между сэмплами (в минутах), иначе rate
    /// считается шумом.
    private static let minimumSpanMinutes: TimeInterval = 15

    /// Вычисляет burn rate для окна по его `windowMins`.
    /// - Parameters:
    ///   - samples: история сэмплов (может содержать сэмплы разных окон).
    ///   - windowMins: длительность окна в минутах, для которого считаем rate.
    ///   - currentUsedPercent: текущее использование окна (0…100).
    ///   - currentResetsAt: время ресета текущего окна; используется для отсева
    ///     сэмплов предыдущего окна и проверки, что прогноз вписывается в окно.
    ///   - now: опорный момент «сейчас» для прогноза.
    /// - Returns: `BurnRate` или `nil`, если данных недостаточно/темп неположителен/
    ///   прогноз выходит за ресет окна.
    public static func calculate(
        samples: [UsageSample],
        windowMins: Int,
        currentUsedPercent: Double,
        currentResetsAt: Date?,
        now: Date
    ) -> BurnRate? {
        // samples is already sorted by time from HistoryStore
        var relevantSamples: [UsageSample] = []
        for sample in samples {
            if sample.windowMins != windowMins { continue }
            if let currentResetsAt {
                if sample.resetsAt != currentResetsAt { continue }
            }
            if sample.fetchedAt > now { continue }
            relevantSamples.append(sample)
        }

        guard relevantSamples.count >= minimumSampleCount else { return nil }

        // Текущее значение якорит последнюю точку и даёт остаток для прогноза.
        let points: [(time: Date, used: Double)] = relevantSamples.map {
            (time: $0.fetchedAt, used: $0.usedPercent)
        } + [(time: now, used: currentUsedPercent)]

        guard let firstTime = points.first?.time,
              let lastTime = points.last?.time else { return nil }

        let span = lastTime.timeIntervalSince(firstTime)
        guard span >= minimumSpanMinutes * 60 else { return nil }

        let xValues = points.map { $0.time.timeIntervalSince(firstTime) / 3600 }
        let yValues = points.map { $0.used }

        let slope = linearRegressionSlope(x: xValues, y: yValues)
        guard let slope, slope > 0 else { return nil }

        let remaining = max(0, 100 - currentUsedPercent)
        guard remaining > 0 else { return nil }

        let hoursToExhaustion = remaining / slope
        let exhaustionDate = now.addingTimeInterval(hoursToExhaustion * 3600)

        // Прогноз должен вписываться в текущее окно: исчерпание до ресета.
        if let currentResetsAt, exhaustionDate > currentResetsAt {
            return nil
        }

        return BurnRate(
            usedPercentPerHour: slope,
            exhaustionDate: exhaustionDate,
            windowMins: windowMins
        )
    }

    /// Простая линейная регрессия по МНК: y = slope * x + intercept.
    /// Возвращает `nil`, если вырожденная матрица (все x совпадают).
    private static func linearRegressionSlope(x: [Double], y: [Double]) -> Double? {
        precondition(x.count == y.count)
        let n = Double(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let sumXX = x.map { $0 * $0 }.reduce(0, +)

        let denominator = n * sumXX - sumX * sumX
        guard denominator > 0 else { return nil }

        return (n * sumXY - sumX * sumY) / denominator
    }
}
