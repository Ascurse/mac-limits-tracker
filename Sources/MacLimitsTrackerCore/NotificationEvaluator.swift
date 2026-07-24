import Foundation

/// Событие для уведомления (issue #29). Чистое значение — доставку
/// (UNUserNotificationCenter) выполняет NotificationManager в app-таргете.
public struct NotificationEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Окно пересекло порог вниз (normal→warning, warning→critical и т.п.).
        case thresholdCrossed(severity: Severity, remainingPercent: Double)
        /// Окно ресетнулось: resetsAt сменился на новое значение.
        case windowReset
    }

    public let providerId: String
    public let providerName: String
    public let windowLabel: String
    public let kind: Kind

    public init(providerId: String, providerName: String, windowLabel: String, kind: Kind) {
        self.providerId = providerId
        self.providerName = providerName
        self.windowLabel = windowLabel
        self.kind = kind
    }
}

/// Вычисляет события уведомлений по потоку состояний провайдеров (issue #29).
/// Дедупликация: crossing шлётся один раз на ухудшение зоны; восстановление
/// выше порога перевзводит (re-arm) уведомление. Ресет окна — по смене
/// resetsAt; первое наблюдение resetsAt — базовая линия, не событие.
/// Первое наблюдение окна уже за порогом — crossing из normal (запуск приложения).
/// Состояние — в памяти: перезапуск приложения даёт максимум одно уведомление
/// на окно за порогом, что соответствует штатному сценарию issue.
public final class NotificationEvaluator {
    private struct WindowKey: Hashable {
        let providerId: String
        let durationMins: Int
    }

    private var lastSeverity: [WindowKey: Severity] = [:]
    private var lastResetsAt: [WindowKey: Date] = [:]

    public init() {}

    public func evaluate(
        states: [ProviderState],
        thresholds: SeverityThresholds
    ) -> [NotificationEvent] {
        var events: [NotificationEvent] = []
        for state in states {
            guard let windows = state.snapshot?.windows else { continue }
            for window in windows {
                // Слот заявлен, данных нет — не окно для уведомлений.
                guard let used = window.usedPercent else { continue }
                let key = WindowKey(providerId: state.descriptor.id,
                                    durationMins: window.windowDurationMins ?? -1)
                let remaining = max(0, 100 - used)
                let severity = Severity.from(remainingPercent: remaining, thresholds: thresholds)
                let label = RateLimitWindowLabel.labels(forDurationMins: window.windowDurationMins).long

                let previous = lastSeverity[key] ?? .normal
                if severity.rank > previous.rank {
                    events.append(NotificationEvent(
                        providerId: state.descriptor.id,
                        providerName: state.descriptor.displayName,
                        windowLabel: label,
                        kind: .thresholdCrossed(severity: severity, remainingPercent: remaining)
                    ))
                }
                lastSeverity[key] = severity

                if let resetsAt = window.resetsAt {
                    if let previousReset = lastResetsAt[key], previousReset != resetsAt {
                        events.append(NotificationEvent(
                            providerId: state.descriptor.id,
                            providerName: state.descriptor.displayName,
                            windowLabel: label,
                            kind: .windowReset
                        ))
                    }
                    lastResetsAt[key] = resetsAt
                }
            }
        }
        return events
    }
}

extension Severity {
    /// Порядок ухудшения для сравнения зон (normal < warning < critical).
    fileprivate var rank: Int {
        switch self {
        case .normal: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }
}
