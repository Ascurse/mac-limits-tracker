import Foundation

/// Форматирование остатков, ресетов и burn rate лимитов — общее для меню-бара и десктоп-виджета.
/// Общая для всех провайдеров: `usedPercent` — использованная доля (0…100),
/// осталось = разница (было раздельно `claudeRemainingPercent`/`codexRemainingPercent`).
public enum LimitsFormatting {
    public static func remainingPercent(usedPercent: Double) -> Double {
        max(0, 100 - usedPercent)
    }

    public static func remainingText(usedPercent: Double) -> String {
        String(format: "%.0f%%", remainingPercent(usedPercent: usedPercent))
    }

    public static func resetText(resetsAt: Date?, relativeTo now: Date = Date()) -> String {
        guard let resetsAt else { return "—" }
        return relativeFormatter.localizedString(for: resetsAt, relativeTo: now)
    }

    /// Форматирует `BurnRate` в текст для строки попапа: скорость расхода и
    /// прогноз исчерпания с понятными единицами и временной зоной пользователя.
    public static func burnRateContent(
        burnRate: BurnRate,
        shortLabel: String,
        now: Date = Date()
    ) -> BurnRateContent {
        let rateText = Self.burnRateValueText(usedPercentPerHour: burnRate.usedPercentPerHour)
        let intervalText = Self.timeToExhaustionText(
            burnRate.exhaustionDate.timeIntervalSince(now)
        )
        let absoluteText = Self.timeFormatter.string(from: burnRate.exhaustionDate)
        let text = "Burn \(shortLabel): +\(rateText)%/h · exhausted \(intervalText) (\(absoluteText))"
        let pace = Self.burnRatePace(burnRate: burnRate, now: now)
        return BurnRateContent(
            windowMins: burnRate.windowMins,
            shortLabel: shortLabel,
            text: text,
            pace: pace
        )
    }

    private static func burnRateValueText(usedPercentPerHour: Double) -> String {
        if usedPercentPerHour >= 10 {
            return String(format: "%.0f", usedPercentPerHour)
        } else if usedPercentPerHour >= 1 {
            return String(format: "%.1f", usedPercentPerHour)
        } else {
            return String(format: "%.2f", usedPercentPerHour)
        }
    }

    private static func timeToExhaustionText(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, interval / 60)
        if totalMinutes < 60 {
            return "in \(Int(totalMinutes))m"
        }
        let totalHours = totalMinutes / 60
        if totalHours < 24 {
            let hours = Int(totalHours)
            let minutes = Int(totalMinutes) % 60
            return minutes > 0 ? "in \(hours)h \(minutes)m" : "in \(hours)h"
        }
        let totalDays = totalHours / 24
        let hours = Int(totalHours) % 24
        return hours > 0 ? "in \(Int(totalDays))d \(hours)h" : "in \(Int(totalDays))d"
    }

    private static func burnRatePace(burnRate: BurnRate, now: Date) -> BurnRatePace {
        let windowDuration = TimeInterval(burnRate.windowMins) * 60
        guard windowDuration > 0 else { return .moderate }
        let timeToExhaustion = burnRate.exhaustionDate.timeIntervalSince(now)
        let ratio = timeToExhaustion / windowDuration
        if ratio < 0.25 { return .fast }
        if ratio < 0.5 { return .moderate }
        return .slow
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

