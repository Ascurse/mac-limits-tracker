import Foundation

/// Одно окно лимита в снапшоте провайдера. Длительность определяет метку
/// (см. `RateLimitWindowLabel`) независимо от позиции в ответе API.
/// `usedPercent == nil` — слот заявлен, но данных нет («… usage unavailable»).
public struct SnapshotWindow: Equatable, Sendable {
    public let windowDurationMins: Int?
    public let usedPercent: Double?
    public let resetsAt: Date?

    public init(windowDurationMins: Int?, usedPercent: Double?, resetsAt: Date?) {
        self.windowDurationMins = windowDurationMins
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// Произвольная detail-строка снапшота (Auth/Account/Org и т.п.).
public struct SnapshotDetail: Equatable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Унифицированный снапшот использования лимитов одного провайдера.
public struct LimitsSnapshot: Equatable, Sendable {
    public let loggedIn: Bool
    /// Сырой план (без capitalized); приоритет источников (live vs claim) решает провайдер.
    public let plan: String?
    /// nil — usage ещё не загружен («Loading usage…»/«Loading…»).
    public let windows: [SnapshotWindow]?
    public let creditsBalance: String?
    public let rateLimitReachedType: String?
    public let details: [SnapshotDetail]
    public let daysUntilRenewal: Int?
    public let renewalDate: Date?
    public let usageError: String?
    public let providerError: String?
    public let fetchedAt: Date

    public init(
        loggedIn: Bool,
        plan: String?,
        windows: [SnapshotWindow]?,
        creditsBalance: String?,
        rateLimitReachedType: String?,
        details: [SnapshotDetail],
        daysUntilRenewal: Int?,
        renewalDate: Date?,
        usageError: String?,
        providerError: String?,
        fetchedAt: Date
    ) {
        self.loggedIn = loggedIn
        self.plan = plan
        self.windows = windows
        self.creditsBalance = creditsBalance
        self.rateLimitReachedType = rateLimitReachedType
        self.details = details
        self.daysUntilRenewal = daysUntilRenewal
        self.renewalDate = renewalDate
        self.usageError = usageError
        self.providerError = providerError
        self.fetchedAt = fetchedAt
    }
}

extension LimitsSnapshot {
    /// Заголовок для меню-бара: единое правило для всех провайдеров
    /// (было раздельно в `ClaudeStatus.menuTitle`/`CodexStatus.menuTitle`).
    public func menuTitle(shortName: String) -> String {
        if providerError != nil { return "\(shortName): ?" }
        guard loggedIn else { return "\(shortName): —" }
        if let plan, !plan.isEmpty { return "\(shortName): \(plan.capitalized)" }
        return shortName
    }
}
