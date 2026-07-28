import Foundation

extension ClaudeLimitsProvider: LimitsProvider {
    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: "claude",
            displayName: "Claude Code",
            shortName: "Claude",
            menuBarSymbol: "C",
            accentColorHex: 0xFF9E64,
            loginHelp: LoginHelp(
                helpText: "Open Claude Code to refresh the claude.ai login",
                binaryPath: claudeBinary
            )
        )
    }

    public func fetch() async -> LimitsSnapshot {
        await fetchStatus().toSnapshot()
    }
}

extension CodexLimitsProvider: LimitsProvider {
    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: "codex",
            displayName: "Codex",
            shortName: "Codex",
            menuBarSymbol: "X",
            accentColorHex: 0x9ECE6A,
            loginHelp: nil
        )
    }

    public func fetch() async -> LimitsSnapshot {
        await fetchStatus().toSnapshot()
    }
}

extension KimiLimitsProvider: LimitsProvider {
    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: "kimi",
            displayName: "Kimi",
            shortName: "Kimi",
            menuBarSymbol: "K",
            accentColorHex: 0x7AA2F7,
            loginHelp: nil
        )
    }

    public func fetch() async -> LimitsSnapshot {
        await fetchStatus().toSnapshot()
    }
}

/// Приводит статус-структуры конкретных провайдеров к унифицированному `LimitsSnapshot`.
/// Единственное место, где Claude/Codex-специфичные поля разбираются вручную —
/// весь остальной стек (билдер, меню-бар, виджет) работает только со снапшотом.
extension ClaudeStatus {
    func toSnapshot() -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: loggedIn,
            plan: subscriptionType,
            windows: snapshotWindows,
            creditsBalance: nil,
            rateLimitReachedType: nil,
            details: snapshotDetails,
            daysUntilRenewal: nil,
            renewalDate: nil,
            usageError: usageError,
            providerError: providerError,
            fetchedAt: fetchedAt
        )
    }

    private var snapshotWindows: [SnapshotWindow]? {
        guard let usage else { return nil }
        return [
            SnapshotWindow(windowDurationMins: 300,
                           usedPercent: usage.fiveHour?.utilizationPercent,
                           resetsAt: usage.fiveHour?.resetsAt),
            SnapshotWindow(windowDurationMins: 10080,
                           usedPercent: usage.sevenDay?.utilizationPercent,
                           resetsAt: usage.sevenDay?.resetsAt)
        ]
    }

    // Дневная статистика из stats-cache (gh #26): счётчики уже распарсены в
    // `today`, здесь только форматируем detail-строку.
    private var snapshotDetails: [SnapshotDetail] {
        guard let today else { return [] }
        return [
            SnapshotDetail(
                key: "Today",
                value: "\(today.messageCount) msgs · \(today.sessionCount) sessions · \(Self.abbreviated(today.tokens)) tokens"
            )
        ]
    }

    /// Компактная запись числа токенов: 999 / 12.3K / 1.3M, без локали
    /// (детерминированно для тестов), `.0` срезается.
    private static func abbreviated(_ value: Int) -> String {
        func trim(_ scaled: Double, _ suffix: String) -> String {
            let s = String(format: "%.1f", scaled)
            return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + suffix
        }
        if value >= 1_000_000 { return trim(Double(value) / 1_000_000, "M") }
        if value >= 1_000 { return trim(Double(value) / 1_000, "K") }
        return "\(value)"
    }
}

extension CodexStatus {
    func toSnapshot() -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: loggedIn,
            // Приоритет: live planType из app-server над JWT-claimом (может отстать при продлении).
            plan: usage?.snapshot?.planType ?? planType,
            windows: snapshotWindows,
            creditsBalance: snapshotCredits,
            rateLimitReachedType: usage?.snapshot?.rateLimitReachedType,
            details: snapshotDetails,
            daysUntilRenewal: daysUntilRenewal,
            renewalDate: subscriptionActiveUntil,
            usageError: usageError,
            providerError: providerError,
            fetchedAt: fetchedAt
        )
    }

    private var snapshotWindows: [SnapshotWindow]? {
        guard let snap = usage?.snapshot else { return nil }
        let present = [snap.primary, snap.secondary].compactMap { $0 }
        return present
            .sorted { Self.windowSortKey($0) < Self.windowSortKey($1) }
            .map { SnapshotWindow(windowDurationMins: $0.windowDurationMins,
                                  usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) }
    }

    private var snapshotCredits: String? {
        guard let credits = usage?.snapshot?.creditsBalance, !credits.isEmpty else { return nil }
        return credits
    }

    private var snapshotDetails: [SnapshotDetail] {
        var details: [SnapshotDetail] = []
        if let authMode { details.append(SnapshotDetail(key: "Auth", value: authMode)) }
        if let email { details.append(SnapshotDetail(key: "Account", value: email)) }
        if let accountOwner { details.append(SnapshotDetail(key: "Org", value: accountOwner)) }
        return details
    }

    /// Порядок окон: 5h первым, weekly вторым, прочие — по возрастанию длительности,
    /// nil-длительность в конце (см. bd mac-limits-tracker-w4a).
    private static func windowSortKey(_ w: CodexUsageWindow) -> (Int, Int) {
        switch w.windowDurationMins {
        case 300: return (0, 0)
        case 10080: return (1, 0)
        case .some(let mins): return (2, mins)
        case .none: return (3, Int.max)
        }
    }
}

extension KimiStatus {
    /// `limits[]` → окна (по `windowDurationMins`, как у Claude/Codex); верхнеуровневый
    /// `usage` — покупной пул без периода (`subType: TYPE_PURCHASE`), поэтому идёт деталью
    /// "Quota", а не окном с придуманной длительностью (см. docs/journal/decisions.md).
    func toSnapshot() -> LimitsSnapshot {
        let windows = usage?.windows.isEmpty == false ? usage?.windows.map(Self.toSnapshotWindow) : nil
        let details = usage?.quota.flatMap(Self.quotaDetail).map { [$0] } ?? []
        return LimitsSnapshot(
            loggedIn: loggedIn,
            plan: plan,
            windows: windows,
            creditsBalance: nil,
            rateLimitReachedType: nil,
            details: details,
            daysUntilRenewal: nil,
            renewalDate: nil,
            usageError: usageError,
            providerError: providerError,
            fetchedAt: fetchedAt
        )
    }

    private static func toSnapshotWindow(_ window: KimiUsageWindow) -> SnapshotWindow {
        SnapshotWindow(windowDurationMins: window.windowDurationMins,
                       usedPercent: window.usedPercent, resetsAt: window.resetsAt)
    }

    private static func quotaDetail(_ quota: KimiQuotaDetail) -> SnapshotDetail? {
        guard let limit = quota.limit, let used = quota.used else { return nil }
        var value = "\(used) / \(limit) used"
        if let resetsAt = quota.resetsAt {
            value += " · resets \(Self.quotaResetFormatter.string(from: resetsAt))"
        }
        return SnapshotDetail(key: "Quota", value: value)
    }

    private static let quotaResetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
