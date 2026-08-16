import Foundation

public enum PaceComparisonStatus: Equatable, Sendable {
    case onPace
    case atRisk
    case collectingHistory
    case unavailable
}

public struct PaceComparisonContent: Equatable, Sendable {
    public let windowLabel: String
    public let windowDurationMins: Int?
    public let quotaRemainingPercent: Double?
    public let timeRemainingPercent: Double?
    public let paceDeltaPercent: Double?
    public let resetAt: Date?
    public let forecastAt: Date?
    public let status: PaceComparisonStatus

    public init(
        windowLabel: String,
        windowDurationMins: Int?,
        quotaRemainingPercent: Double?,
        timeRemainingPercent: Double?,
        paceDeltaPercent: Double?,
        resetAt: Date?,
        forecastAt: Date?,
        status: PaceComparisonStatus
    ) {
        self.windowLabel = windowLabel
        self.windowDurationMins = windowDurationMins
        self.quotaRemainingPercent = quotaRemainingPercent
        self.timeRemainingPercent = timeRemainingPercent
        self.paceDeltaPercent = paceDeltaPercent
        self.resetAt = resetAt
        self.forecastAt = forecastAt
        self.status = status
    }

    public func compactText(now: Date = Date()) -> String {
        guard status != .unavailable else { return "Usage unavailable" }

        var parts: [String] = [
            status == .atRisk ? "At risk" : status == .onPace ? "On pace" : "Collecting history"
        ]
        if let quotaRemainingPercent {
            parts.append(String(format: "%.0f%% left", quotaRemainingPercent))
        }

        switch status {
        case .atRisk:
            if let forecastAt {
                parts.append("runs out \(LimitsFormatting.timeToExhaustionText(forecastAt.timeIntervalSince(now)))")
            }
            parts.append("switch or wait")
        case .onPace, .collectingHistory:
            if let resetAt {
                parts.append("reset \(LimitsFormatting.timeToExhaustionText(resetAt.timeIntervalSince(now)))")
            }
        case .unavailable:
            break
        }

        return parts.joined(separator: " · ")
    }
}

public enum PaceComparisonPolicy {
    public static func make(
        window: SnapshotWindow,
        windowLabel: String,
        burnRate: BurnRate?,
        now: Date
    ) -> PaceComparisonContent {
        guard let durationMins = window.windowDurationMins,
              durationMins > 0,
              let usedPercent = window.usedPercent,
              let resetAt = window.resetsAt else {
            return PaceComparisonContent(
                windowLabel: windowLabel,
                windowDurationMins: window.windowDurationMins,
                quotaRemainingPercent: nil,
                timeRemainingPercent: nil,
                paceDeltaPercent: nil,
                resetAt: window.resetsAt,
                forecastAt: burnRate?.exhaustionDate,
                status: .unavailable
            )
        }

        let quotaRemaining = clamp(100 - usedPercent)
        let windowDuration = TimeInterval(durationMins) * 60
        let timeRemaining = clamp(resetAt.timeIntervalSince(now) / windowDuration * 100)
        let status: PaceComparisonStatus
        if let burnRate {
            status = burnRate.exhaustionDate < resetAt ? .atRisk : .onPace
        } else {
            status = .collectingHistory
        }

        return PaceComparisonContent(
            windowLabel: windowLabel,
            windowDurationMins: durationMins,
            quotaRemainingPercent: quotaRemaining,
            timeRemainingPercent: timeRemaining,
            paceDeltaPercent: quotaRemaining - timeRemaining,
            resetAt: resetAt,
            forecastAt: burnRate?.exhaustionDate,
            status: status
        )
    }

    private static func clamp(_ value: Double) -> Double {
        max(0, min(100, value))
    }
}
