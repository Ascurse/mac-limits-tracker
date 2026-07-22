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
        let windows: [SnapshotWindow]?
        if let usage {
            windows = [
                SnapshotWindow(windowDurationMins: 300,
                               usedPercent: usage.fiveHour?.utilizationPercent,
                               resetsAt: usage.fiveHour?.resetsAt),
                SnapshotWindow(windowDurationMins: 10080,
                               usedPercent: usage.sevenDay?.utilizationPercent,
                               resetsAt: usage.sevenDay?.resetsAt)
            ]
        } else {
            windows = nil
        }
        return LimitsSnapshot(
            loggedIn: loggedIn,
            plan: subscriptionType,
            windows: windows,
            creditsBalance: nil,
            rateLimitReachedType: nil,
            details: [],
            daysUntilRenewal: nil,
            renewalDate: nil,
            usageError: usageError,
            providerError: providerError,
            fetchedAt: fetchedAt
        )
    }
}

extension CodexStatus {
    func toSnapshot() -> LimitsSnapshot {
        // Приоритет: live planType из app-server над JWT-claimом (может отстать при продлении).
        let plan = usage?.snapshot?.planType ?? planType

        var windows: [SnapshotWindow]?
        var credits: String?
        var reached: String?
        if let snap = usage?.snapshot {
            let present = [snap.primary, snap.secondary].compactMap { $0 }
            windows = present
                .sorted { Self.windowSortKey($0) < Self.windowSortKey($1) }
                .map { SnapshotWindow(windowDurationMins: $0.windowDurationMins,
                                      usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) }
            credits = (snap.creditsBalance?.isEmpty == false) ? snap.creditsBalance : nil
            reached = snap.rateLimitReachedType
        }

        var details: [SnapshotDetail] = []
        if let authMode { details.append(SnapshotDetail(key: "Auth", value: authMode)) }
        if let email { details.append(SnapshotDetail(key: "Account", value: email)) }
        if let accountOwner { details.append(SnapshotDetail(key: "Org", value: accountOwner)) }

        return LimitsSnapshot(
            loggedIn: loggedIn,
            plan: plan,
            windows: windows,
            creditsBalance: credits,
            rateLimitReachedType: reached,
            details: details,
            daysUntilRenewal: daysUntilRenewal,
            renewalDate: subscriptionActiveUntil,
            usageError: usageError,
            providerError: providerError,
            fetchedAt: fetchedAt
        )
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
    /// Kimi — "тонкий" провайдер: локального источника usage/лимитов нет, поэтому
    /// windows/credits/renewal всегда пусты; usageError объясняет это пользователю
    /// (не "Loading…" — данные не появятся, см. bd mac-limits-tracker-6gk.3).
    func toSnapshot() -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: loggedIn,
            plan: plan,
            windows: nil,
            creditsBalance: nil,
            rateLimitReachedType: nil,
            details: [],
            daysUntilRenewal: nil,
            renewalDate: nil,
            usageError: usageError,
            providerError: providerError,
            fetchedAt: fetchedAt
        )
    }
}
