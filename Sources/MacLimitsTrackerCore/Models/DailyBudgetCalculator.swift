import Foundation

public struct DailyBudget: Equatable, Sendable {
    public let budgetPercent: Double
    public let resetAt: Date

    public init(budgetPercent: Double, resetAt: Date) {
        self.budgetPercent = budgetPercent
        self.resetAt = resetAt
    }
}

public enum DailyBudgetCalculator {
    public static func calculate(
        remainingPercent: Double,
        resetAt: Date?,
        now: Date,
        calendar: Calendar
    ) -> DailyBudget? {
        guard let resetAt, resetAt > now else { return nil }
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfLocalDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }
        let usableUntil = min(endOfLocalDay, resetAt)
        guard usableUntil > now else { return nil }

        let clampedRemaining = min(max(remainingPercent, 0), 100)
        let ratio = usableUntil.timeIntervalSince(now) / resetAt.timeIntervalSince(now)
        return DailyBudget(
            budgetPercent: clampedRemaining * ratio,
            resetAt: resetAt
        )
    }
}
