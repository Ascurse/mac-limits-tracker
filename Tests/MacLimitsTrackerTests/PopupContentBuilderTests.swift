import XCTest
@testable import MacLimitsTrackerCore

final class SeverityTests: XCTestCase {
    func test_thresholdsByRemaining() {
        XCTAssertEqual(Severity.from(remainingPercent: 100), .normal)
        XCTAssertEqual(Severity.from(remainingPercent: 41), .normal)
        XCTAssertEqual(Severity.from(remainingPercent: 40), .warning)   // граница входит в warning
        XCTAssertEqual(Severity.from(remainingPercent: 16), .warning)
        XCTAssertEqual(Severity.from(remainingPercent: 15), .critical)  // граница входит в critical
        XCTAssertEqual(Severity.from(remainingPercent: 0), .critical)
    }

    /// Кастомные пороги (issue #25): то же значение остатка может давать
    /// другую серьёзность, чем при стандартных 40/15.
    func test_customThresholds_shiftSeverityBands() {
        let lax = SeverityThresholds(warningRemaining: 20, criticalRemaining: 5)
        XCTAssertEqual(Severity.from(remainingPercent: 25, thresholds: lax), .normal)
        XCTAssertEqual(Severity.from(remainingPercent: 25), .warning)
        XCTAssertEqual(Severity.from(remainingPercent: 10, thresholds: lax), .warning)
        XCTAssertEqual(Severity.from(remainingPercent: 10), .critical)

        let strict = SeverityThresholds(warningRemaining: 60, criticalRemaining: 30)
        XCTAssertEqual(Severity.from(remainingPercent: 50, thresholds: strict), .warning)
        XCTAssertEqual(Severity.from(remainingPercent: 25, thresholds: strict), .critical)
    }
}

final class SeverityWorstTests: XCTestCase {
    private func state(
        descriptor: ProviderDescriptor = claudeDescriptor,
        windows: [SnapshotWindow]?,
        lastGoodWindows: [SnapshotWindow]? = nil,
        providerError: String? = nil
    ) -> ProviderState {
        let snapshot = LimitsSnapshot(
            loggedIn: true, plan: nil, windows: windows,
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: providerError, fetchedAt: Date(timeIntervalSince1970: 1)
        )
        let lastGood = lastGoodWindows.map {
            LimitsSnapshot(
                loggedIn: true, plan: nil, windows: $0,
                creditsBalance: nil, rateLimitReachedType: nil, details: [],
                daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
                providerError: nil, fetchedAt: Date(timeIntervalSince1970: 0)
            )
        }
        return ProviderState(descriptor: descriptor, snapshot: snapshot, lastGoodSnapshot: lastGood)
    }

    func test_worstUsesConfiguredThresholdsAcrossResolvedStates() {
        let thresholds = SeverityThresholds(warningRemaining: 60, criticalRemaining: 20)
        let normal = state(windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: 30, resetsAt: nil)])
        let warning = state(descriptor: codexDescriptor,
                            windows: [SnapshotWindow(windowDurationMins: 10080, usedPercent: 50, resetsAt: nil)])
        let critical = state(windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: 90, resetsAt: nil)])

        XCTAssertEqual(Severity.worst(in: [normal], thresholds: thresholds), .normal)
        XCTAssertEqual(Severity.worst(in: [warning], thresholds: thresholds), .warning)
        XCTAssertEqual(Severity.worst(in: [normal, warning, critical], thresholds: thresholds), .critical)
    }

    func test_worstUsesLastGoodWindowsForStaleState() {
        let stale = state(
            windows: nil,
            lastGoodWindows: [SnapshotWindow(windowDurationMins: 300, usedPercent: 90, resetsAt: nil)],
            providerError: "offline"
        )

        XCTAssertEqual(Severity.worst(in: [stale]), .critical)
    }

    func test_worstIgnoresProviderErrorWithoutLastGood() {
        let failed = state(
            windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: 99, resetsAt: nil)],
            providerError: "offline"
        )

        XCTAssertEqual(Severity.worst(in: [failed]), .normal)
    }

    func test_worstReturnsNormalWhenNoWindowHasData() {
        let empty = state(windows: [])
        let unavailable = state(windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: nil, resetsAt: nil)])

        XCTAssertEqual(Severity.worst(in: [empty, unavailable]), .normal)
    }
}

private let claudeDescriptor = ProviderDescriptor(
    id: "claude", displayName: "Claude Code", shortName: "Claude",
    menuBarSymbol: "C", accentColorHex: 0xFF9E64, loginHelp: nil
)

private let codexDescriptor = ProviderDescriptor(
    id: "codex", displayName: "Codex", shortName: "Codex",
    menuBarSymbol: "X", accentColorHex: 0x9ECE6A, loginHelp: nil
)

/// Проброс кастомных порогов через PopupContentBuilder.section (issue #25).
final class PopupContentBuilderThresholdsTests: XCTestCase {
    private func state(remaining: Double) -> ProviderState {
        let snap = LimitsSnapshot(
            loggedIn: true, plan: nil,
            windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: 100 - remaining, resetsAt: nil)],
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: nil, fetchedAt: Date()
        )
        return ProviderState(descriptor: claudeDescriptor, snapshot: snap)
    }

    private func windowSeverity(_ s: ProviderSectionContent) -> Severity? {
        for row in s.rows { if case .window(let w) = row { return w.severity } }
        return nil
    }

    func test_customThresholds_changeWindowSeverity() {
        let lax = SeverityThresholds(warningRemaining: 20, criticalRemaining: 5)
        let s = PopupContentBuilder.section(state(remaining: 25), thresholds: lax)
        XCTAssertEqual(windowSeverity(s), .normal)
    }

    /// Вызов без thresholds — поведение как раньше (стандартные 40/15).
    func test_defaultArgument_keepsStandardSeverity() {
        let s = PopupContentBuilder.section(state(remaining: 25))
        XCTAssertEqual(windowSeverity(s), .warning)
    }
}

final class PopupContentBuilderClaudeTests: XCTestCase {
    private func makeStatus(
        providerError: String? = nil,
        usage: ClaudeUsage? = nil,
        usageError: String? = nil,
        subscriptionType: String? = "max"
    ) -> ClaudeStatus {
        ClaudeStatus(
            loggedIn: true, authMethod: "claude.ai", apiProvider: nil, email: "a@b.co",
            subscriptionType: subscriptionType, orgName: nil,
            today: nil, latestDay: nil, lastComputedDate: nil,
            totalSessions: nil, totalMessages: nil,
            usage: usage, usageError: usageError,
            fetchedAt: Date(timeIntervalSince1970: 1_000_000), providerError: providerError
        )
    }

    private func window(_ utilization: Double, resetsAt: Date? = nil) -> ClaudeUsageWindow {
        ClaudeUsageWindow(utilizationPercent: utilization, resetsAt: resetsAt,
                          limitDollars: nil, usedDollars: nil, remainingDollars: nil)
    }

    private func section(_ status: ClaudeStatus?, now: Date = Date()) -> ProviderSectionContent {
        let state = ProviderState(descriptor: claudeDescriptor, snapshot: status?.toSnapshot())
        return PopupContentBuilder.section(state, now: now)
    }

    func test_nilStatus_isLoadingNote() {
        let s = section(nil)
        XCTAssertEqual(s.descriptor.id, "claude")
        XCTAssertEqual(s.title, "Claude Code")
        XCTAssertEqual(s.rows, [.note("Loading…")])
    }

    func test_providerError_isSingleErrorRow() {
        let s = section(makeStatus(providerError: "boom"))
        XCTAssertEqual(s.rows, [recovery("Claude Code error — retry", action: .retry, diagnostic: "boom")])
    }

    func test_planRow_showsRawSubscriptionType() {
        let s = section(makeStatus(usage: ClaudeUsage(fiveHour: nil, sevenDay: nil)))
        // Тариф без капитализации — как в текущем попапе.
        XCTAssertEqual(s.rows.first, .detail(key: "Plan", value: "max"))
    }

    func test_planRow_dashWhenNil() {
        let s = section(makeStatus(usage: ClaudeUsage(fiveHour: nil, sevenDay: nil), subscriptionType: nil))
        XCTAssertEqual(s.rows.first, .detail(key: "Plan", value: "—"))
    }

    func test_windows_remainingIsInverseOfUtilization() {
        let usage = ClaudeUsage(fiveHour: window(28), sevenDay: window(69))
        let s = section(makeStatus(usage: usage))
        let windows = s.rows.compactMap { row -> WindowContent? in
            guard case .window(let content) = row else { return nil }
            return content
        }
        guard windows.count == 2 else {
            return XCTFail("ожидались окна, rows: \(s.rows)")
        }
        let fh = windows[0]
        let wk = windows[1]
        XCTAssertEqual(fh.shortLabel, "5h")
        XCTAssertEqual(fh.longLabel, "5h")
        XCTAssertEqual(fh.remainingPercent, 72)
        XCTAssertEqual(fh.remainingText, "72%")
        XCTAssertEqual(fh.severity, .normal)
        XCTAssertEqual(wk.shortLabel, "wk")
        XCTAssertEqual(wk.longLabel, "Weekly")
        XCTAssertEqual(wk.remainingPercent, 31)
        XCTAssertEqual(wk.severity, .warning)
    }

    func test_windows_remainingClampedToZero() {
        let usage = ClaudeUsage(fiveHour: window(140), sevenDay: nil)
        let s = section(makeStatus(usage: usage))
        guard case .window(let fh) = s.rows[1] else { return XCTFail("\(s.rows)") }
        XCTAssertEqual(fh.remainingPercent, 0)
        XCTAssertEqual(fh.remainingText, "0%")
        XCTAssertEqual(fh.severity, .critical)
    }

    func test_missingWindow_becomesUnavailableNote() {
        let usage = ClaudeUsage(fiveHour: nil, sevenDay: window(10))
        let s = section(makeStatus(usage: usage))
        XCTAssertEqual(s.rows[1], .note("5h usage unavailable"))
        guard case .window = s.rows[2] else { return XCTFail("\(s.rows)") }
    }

    func test_resetText_presentOnlyWithResetsAt() {
        let usage = ClaudeUsage(fiveHour: window(50, resetsAt: Date().addingTimeInterval(7200)),
                                sevenDay: window(50))
        let s = section(makeStatus(usage: usage))
        let windows = s.rows.compactMap { row -> WindowContent? in
            guard case .window(let content) = row else { return nil }
            return content
        }
        guard windows.count == 2 else {
            return XCTFail("\(s.rows)")
        }
        let fh = windows[0]
        let wk = windows[1]
        // Точный текст зависит от локали — проверяем только наличие.
        XCTAssertNotNil(fh.resetText)
        XCTAssertNil(wk.resetText)
    }

    func test_usageError_shownWhenNoUsage() {
        let s = section(makeStatus(usageError: "token expired"))
        XCTAssertEqual(s.rows, [.detail(key: "Plan", value: "max"),
                                recovery("Claude Code error — retry", action: .retry, diagnostic: "token expired")])
    }

    func test_noUsageNoError_loadingUsageNote() {
        let s = section(makeStatus())
        XCTAssertEqual(s.rows, [.detail(key: "Plan", value: "max"), .note("Loading usage…")])
    }
}

final class PopupContentBuilderCodexTests: XCTestCase {
    private func makeStatus(
        providerError: String? = nil,
        usage: CodexUsage? = nil,
        usageError: String? = nil,
        planType: String? = "plus",
        authMode: String? = "chatgpt",
        email: String? = "x@y.z",
        accountOwner: String? = "Acme",
        daysUntilRenewal: Int? = 12,
        subscriptionActiveUntil: Date? = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> CodexStatus {
        CodexStatus(
            loggedIn: true, authMode: authMode, email: email, planType: planType,
            subscriptionActiveUntil: subscriptionActiveUntil,
            daysUntilRenewal: daysUntilRenewal, accountOwner: accountOwner,
            usage: usage, usageError: usageError,
            fetchedAt: Date(timeIntervalSince1970: 2_000_000), providerError: providerError
        )
    }

    private func window(_ used: Double, duration: Int? = nil) -> CodexUsageWindow {
        CodexUsageWindow(usedPercent: used, windowDurationMins: duration, resetsAt: nil)
    }

    private func section(_ status: CodexStatus?, now: Date = Date()) -> ProviderSectionContent {
        let state = ProviderState(descriptor: codexDescriptor, snapshot: status?.toSnapshot())
        return PopupContentBuilder.section(state, now: now)
    }

    func test_nilStatus_isLoadingNote() {
        let s = section(nil)
        XCTAssertEqual(s.descriptor.id, "codex")
        XCTAssertEqual(s.title, "Codex")
        XCTAssertEqual(s.rows, [.note("Loading…")])
    }

    func test_providerError_isSingleErrorRow() {
        let s = section(makeStatus(providerError: "no auth.json"))
        XCTAssertEqual(s.rows, [recovery("Codex error — retry", action: .retry, diagnostic: "no auth.json")])
    }

    func test_snapshotPlanTypeWinsOverJwtClaim() {
        let snap = CodexUsageSnapshot(primary: nil, secondary: nil, planType: "pro",
                                      creditsBalance: nil, rateLimitReachedType: nil)
        let s = section(makeStatus(usage: CodexUsage(snapshot: snap)))
        XCTAssertEqual(s.rows.first, .detail(key: "Plan", value: "pro"))
    }

    func test_fullSnapshot_rowOrder() {
        let snap = CodexUsageSnapshot(primary: window(42, duration: 300),
                                      secondary: window(56, duration: 10080),
                                      planType: nil, creditsBalance: "12.50",
                                      rateLimitReachedType: "primary")
        let s = section(makeStatus(usage: CodexUsage(snapshot: snap)))
        // Plan, 5h, weekly, Credits, rate-limit error, Auth, Account, Org, Renews in, Renews
        XCTAssertEqual(s.rows.count, 10)
        XCTAssertEqual(s.rows[0], .detail(key: "Plan", value: "plus"))
        guard case .window(let fh) = s.rows[1] else { return XCTFail("\(s.rows)") }
        XCTAssertEqual(fh.remainingPercent, 58)
        guard case .window(let wk) = s.rows[2] else { return XCTFail("\(s.rows)") }
        XCTAssertEqual(wk.remainingPercent, 44)
        XCTAssertEqual(s.rows[3], .detail(key: "Credits", value: "12.50"))
        XCTAssertEqual(s.rows[4], .error("rate limit reached: primary"))
        XCTAssertEqual(s.rows[5], .detail(key: "Auth", value: "chatgpt"))
        XCTAssertEqual(s.rows[6], .detail(key: "Account", value: "x@y.z"))
        XCTAssertEqual(s.rows[7], .detail(key: "Org", value: "Acme"))
        XCTAssertEqual(s.rows[8], .detail(key: "Renews in", value: "12 days"))
        guard case .detail(let key, _) = s.rows[9], key == "Renews" else { return XCTFail("\(s.rows)") }
    }

    func test_emptyCredits_skipped() {
        let snap = CodexUsageSnapshot(primary: nil, secondary: nil, planType: nil,
                                      creditsBalance: "", rateLimitReachedType: nil)
        let s = section(
            makeStatus(usage: CodexUsage(snapshot: snap), authMode: nil, email: nil,
                       accountOwner: nil, daysUntilRenewal: nil, subscriptionActiveUntil: nil))
        XCTAssertEqual(s.rows, [.detail(key: "Plan", value: "plus")])
    }

    func test_weeklyWindowInPrimary_rendersWithLongLabelWeekly() {
        let snap = CodexUsageSnapshot(primary: window(56, duration: 10080), secondary: nil,
                                      planType: nil, creditsBalance: nil,
                                      rateLimitReachedType: nil)
        let s = section(makeStatus(usage: CodexUsage(snapshot: snap)))
        guard case .window(let wk) = s.rows[1] else {
            return XCTFail("ожидалось окно, rows: \(s.rows)")
        }
        XCTAssertEqual(wk.shortLabel, "wk")
        XCTAssertEqual(wk.longLabel, "Weekly")
        XCTAssertEqual(wk.remainingPercent, 44)
        XCTAssertEqual(wk.remainingText, "44%")
    }

    func test_onlyWeeklyWindow_rendersNo5hRow() {
        let snap = CodexUsageSnapshot(primary: window(56, duration: 10080), secondary: nil,
                                      planType: nil, creditsBalance: nil,
                                      rateLimitReachedType: nil)
        let s = section(makeStatus(usage: CodexUsage(snapshot: snap)))
        XCTAssertFalse(s.rows.contains {
            if case .window(let w) = $0 { return w.shortLabel == "5h" }
            return false
        })
    }

    func test_usageError_shownWhenNoSnapshot() {
        let s = section(
            makeStatus(usageError: "app-server unavailable", authMode: nil, email: nil,
                       accountOwner: nil, daysUntilRenewal: nil, subscriptionActiveUntil: nil))
        XCTAssertEqual(s.rows, [.detail(key: "Plan", value: "plus"),
                                recovery("Codex error — retry", action: .retry, diagnostic: "app-server unavailable")])
    }

    func test_nonStandardDurationWindow_rendersWithFallbackLabelInsteadOfDisappearing() {
        let snap = CodexUsageSnapshot(primary: window(20, duration: 180), secondary: nil,
                                      planType: nil, creditsBalance: nil,
                                      rateLimitReachedType: nil)
        let s = section(makeStatus(usage: CodexUsage(snapshot: snap)))
        guard case .window(let w) = s.rows[1] else {
            return XCTFail("окно нестандартной длительности не должно молча пропадать, rows: \(s.rows)")
        }
        XCTAssertEqual(w.shortLabel, "3h")
        XCTAssertEqual(w.remainingPercent, 80)
    }

    func test_duplicateFiveHourDurations_bothWindowsRendered() {
        let snap = CodexUsageSnapshot(primary: window(10, duration: 300),
                                      secondary: window(20, duration: 300),
                                      planType: nil, creditsBalance: nil,
                                      rateLimitReachedType: nil)
        let s = section(makeStatus(usage: CodexUsage(snapshot: snap)))
        let windowRows: [WindowContent] = s.rows.compactMap {
            if case .window(let w) = $0 { return w }
            return nil
        }
        XCTAssertEqual(windowRows.count, 2, "оба окна с одинаковой длительностью должны отрисоваться, rows: \(s.rows)")
        XCTAssertEqual(windowRows[0].shortLabel, "5h")
        XCTAssertEqual(windowRows[1].shortLabel, "5h")
        XCTAssertEqual(windowRows[0].remainingPercent, 90)
        XCTAssertEqual(windowRows[1].remainingPercent, 80)
    }

    func test_pastRenewalDate_hidesBothRenewRows() {
        let past = Date(timeIntervalSince1970: 0) // 1970-01-01
        let now = Date(timeIntervalSince1970: 1_000_000) // after past
        let s = section(
            makeStatus(daysUntilRenewal: nil, subscriptionActiveUntil: past),
            now: now)
        for row in s.rows {
            if case .detail(let key, _) = row {
                XCTAssertNotEqual(key, "Renews in", "past renewal: 'Renews in' must be absent")
                XCTAssertNotEqual(key, "Renews", "past renewal: 'Renews' must be absent")
            }
        }
    }

    func test_futureRenewalDate_showsBothRenewRows() {
        let future = Date(timeIntervalSince1970: 1_800_000_000) // ~2027
        let now = Date(timeIntervalSince1970: 1_700_000_000) // before future
        let s = section(
            makeStatus(daysUntilRenewal: 12, subscriptionActiveUntil: future),
            now: now)
        XCTAssertTrue(s.rows.contains(.detail(key: "Renews in", value: "12 days")),
                      "future renewal: 'Renews in' must be present")
        XCTAssertTrue(s.rows.contains(where: { row in
            if case .detail(let key, _) = row, key == "Renews" { return true }
            return false
        }), "future renewal: 'Renews' must be present")
    }
}

private let kimiDescriptor = ProviderDescriptor(
    id: "kimi", displayName: "Kimi", shortName: "Kimi",
    menuBarSymbol: "K", accentColorHex: 0x7AA2F7, loginHelp: nil
)

/// Kimi — характеризационный тест на уже существующий generic-билдер:
/// новый провайдер не требует изменений в PopupContentBuilder (bd mac-limits-tracker-6gk.3).
final class PopupContentBuilderKimiTests: XCTestCase {
    private static let sentinel = Date(timeIntervalSince1970: 1_700_000_000)

    private func section(_ status: KimiStatus?) -> ProviderSectionContent {
        let state = ProviderState(descriptor: kimiDescriptor, snapshot: status?.toSnapshot())
        return PopupContentBuilder.section(state, now: Self.sentinel)
    }

    func test_loggedInWithPlan_showsPlanAndUsageUnavailableError() {
        let status = KimiStatus(loggedIn: true, plan: "kimi-pro", usage: nil,
                                usageError: "Kimi login expired — open Kimi Code to refresh",
                                providerError: nil, fetchedAt: Self.sentinel)
        let s = section(status)
        XCTAssertEqual(s.descriptor.id, "kimi")
        XCTAssertEqual(s.title, "Kimi")
        XCTAssertEqual(s.rows, [
            .detail(key: "Plan", value: "kimi-pro"),
            recovery("Kimi login expired — open Kimi Code to refresh", action: .openProviderCLI, diagnostic: "Kimi login expired — open Kimi Code to refresh")
        ])
    }

    func test_loggedInWithoutPlan_showsDashPlan() {
        let status = KimiStatus(loggedIn: true, plan: nil, usage: nil,
                                usageError: "Kimi login expired — open Kimi Code to refresh",
                                providerError: nil, fetchedAt: Self.sentinel)
        let s = section(status)
        XCTAssertEqual(s.rows.first, .detail(key: "Plan", value: "—"))
    }

    func test_notLoggedIn_showsSingleErrorRow() {
        let status = KimiStatus(loggedIn: false, plan: nil, usage: nil, usageError: nil,
                                providerError: "kimi-code refresh token missing",
                                fetchedAt: Self.sentinel)
        let s = section(status)
        XCTAssertEqual(s.rows, [recovery("Kimi not logged in — open Kimi Code to refresh", action: .openProviderCLI, diagnostic: "kimi-code refresh token missing")])
    }

    func test_nilStatus_isLoadingNote() {
        XCTAssertEqual(section(nil).rows, [.note("Loading…")])
    }
}

final class PopupContentBuilderUpdatedTextTests: XCTestCase {
    func test_bothNil_dash() {
        let states = [
            ProviderState(descriptor: claudeDescriptor, snapshot: nil),
            ProviderState(descriptor: codexDescriptor, snapshot: nil)
        ]
        XCTAssertEqual(PopupContentBuilder.updatedText(states: states), "—")
    }

    func test_latestOfTwoDates_used() {
        let claude = ClaudeStatus(
            loggedIn: true, authMethod: nil, apiProvider: nil, email: nil,
            subscriptionType: nil, orgName: nil, today: nil, latestDay: nil,
            lastComputedDate: nil, totalSessions: nil, totalMessages: nil,
            usage: nil, usageError: nil,
            fetchedAt: Date(timeIntervalSince1970: 100), providerError: nil)
        let states = [
            ProviderState(descriptor: claudeDescriptor, snapshot: claude.toSnapshot()),
            ProviderState(descriptor: codexDescriptor, snapshot: nil)
        ]
        let text = PopupContentBuilder.updatedText(states: states)
        XCTAssertTrue(text.hasPrefix("Updated "), "получено: \(text)")
    }
}

/// Тренд использования за трейлинг 7 дней: билдер вставляет `.sparkline` сразу после
/// строки своего окна, если в диапазоне ≥2 сэмплов; идентичность окна — windowMins,
/// никогда не индекс.
final class PopupContentBuilderSparklineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeState(
        fiveHourUsed: Double? = 28,
        fiveHourResetsAt: Date? = nil,
        weeklyUsed: Double? = 69,
        weeklyResetsAt: Date? = nil
    ) -> ProviderState {
        let snap = LimitsSnapshot(
            loggedIn: true, plan: "max",
            windows: [
                SnapshotWindow(windowDurationMins: 300, usedPercent: fiveHourUsed, resetsAt: fiveHourResetsAt),
                SnapshotWindow(windowDurationMins: 10080, usedPercent: weeklyUsed, resetsAt: weeklyResetsAt),
            ],
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: nil, fetchedAt: now
        )
        return ProviderState(descriptor: claudeDescriptor, snapshot: snap)
    }

    private func sample(windowMins: Int, hoursAgo: Double, used: Double, resetsAt: Date? = nil) -> UsageSample {
        UsageSample(providerId: "claude", windowMins: windowMins,
                    fetchedAt: now.addingTimeInterval(-hoursAgo * 3600),
                    usedPercent: used, resetsAt: resetsAt)
    }

    private func sparklines(_ s: ProviderSectionContent) -> [SparklineContent] {
        s.rows.compactMap {
            if case .sparkline(let c) = $0 { return c }
            return nil
        }
    }

    private func burnRates(_ s: ProviderSectionContent) -> [BurnRateContent] {
        s.rows.compactMap {
            if case .burnRate(let c) = $0 { return c }
            return nil
        }
    }

    func test_section_withHistory_insertsSparklineAfterMatchingWindowRow() {
        // Входные сэмплы хронологические: контракт PopupContentBuilder — HistoryStore
        // отдаёт их уже отсортированными по времени (сортировка в билдере убрана, bd #80).
        let history = [
            sample(windowMins: 300, hoursAgo: 10, used: 20),
            sample(windowMins: 300, hoursAgo: 5, used: 30),
            sample(windowMins: 300, hoursAgo: 2, used: 40),
        ]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)

        // Plan, 5h, burnRate 5h, sparkline 5h, wk (weekly has no history → empty state, no row).
        XCTAssertEqual(s.rows.count, 5)
        guard case .window(let fh) = s.rows[1] else { return XCTFail("rows: \(s.rows)") }
        XCTAssertEqual(fh.shortLabel, "5h")
        guard case .burnRate(let burn) = s.rows[2] else {
            return XCTFail("ожидался .burnRate сразу после строки 5h, rows: \(s.rows)")
        }
        XCTAssertEqual(burn.windowMins, 300)
        XCTAssertEqual(burn.shortLabel, "5h")
        XCTAssertTrue(burn.text.hasPrefix("Burn 5h:"))
        guard case .sparkline(let spark) = s.rows[3] else {
            return XCTFail("ожидался .sparkline после burnRate, rows: \(s.rows)")
        }
        XCTAssertEqual(spark.windowMins, 300)
        XCTAssertEqual(spark.shortLabel, "5h")
        XCTAssertEqual(spark.metric, .remainingPercent)
        // Точки отсортированы по времени по возрастанию и переведены в remainingPercent.
        XCTAssertEqual(spark.points.map(\.remainingPercent), [80, 70, 60])
        XCTAssertTrue(spark.points.map(\.time) == spark.points.map(\.time).sorted())
        XCTAssertEqual(spark.dataState, .ok)
        guard case .window(let wk) = s.rows[4] else { return XCTFail("rows: \(s.rows)") }
        XCTAssertEqual(wk.shortLabel, "wk")
    }

    func test_section_emptyHistory_noSparklineRows() {
        let s = PopupContentBuilder.section(makeState(), now: now, history: [])
        XCTAssertTrue(sparklines(s).isEmpty)
    }

    func test_section_samplesOlderThan7d_noSparklineRow() {
        let history = [
            sample(windowMins: 300, hoursAgo: 192, used: 40),
            sample(windowMins: 300, hoursAgo: 240, used: 20),
        ]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)
        XCTAssertTrue(sparklines(s).isEmpty)
    }

    func test_section_futureSamples_excludedFromTrend() {
        let history = [
            sample(windowMins: 300, hoursAgo: 2, used: 40),
            sample(windowMins: 300, hoursAgo: -1, used: 90),
        ]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)
        // Единственная допустимая точка → sparse; UsageTrendView покажет её маркером и note.
        let sparks = sparklines(s)
        XCTAssertEqual(sparks.count, 1)
        XCTAssertEqual(sparks.first?.dataState, .sparse(pointCount: 1, minimumNeeded: 2))
    }

    func test_section_samplesWithinRangeBoundary_included() {
        let history = [
            sample(windowMins: 300, hoursAgo: 2, used: 10),
            sample(windowMins: 300, hoursAgo: 1, used: 40),
        ]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)
        let sparks = sparklines(s)
        XCTAssertEqual(sparks.first?.points.map(\.remainingPercent), [90, 60])
    }

    func test_section_singleSample_noTrendRow() {
        let history = [sample(windowMins: 300, hoursAgo: 1, used: 40)]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)
        // Единственная точка → sparse; UsageTrendView покажет маркер с note, а не уверенный график.
        let sparks = sparklines(s)
        XCTAssertEqual(sparks.count, 1)
        XCTAssertEqual(sparks.first?.dataState, .sparse(pointCount: 1, minimumNeeded: 2))
    }

    func test_section_moreThanMaxPoints_downsamplesKeepingLatestPerBucket() {
        // 30 сэмплов на 7-дневный диапазон — больше лимита в 24 точки, значит
        // должен сработать даунсэмплинг с выбором ПОСЛЕДНЕГО сэмпла в бакете.
        var history: [UsageSample] = []
        for i in 0..<30 {
            let hoursAgo = Double(29 - i) * (24.0 * 7 / 30)
            history.append(sample(windowMins: 300, hoursAgo: hoursAgo, used: Double(i)))
        }
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)
        let sparks = sparklines(s)
        guard let points = sparks.first?.points else { return XCTFail("ожидался тренд") }
        XCTAssertLessThanOrEqual(points.count, 24)
        XCTAssertTrue(points.map(\.time) == points.map(\.time).sorted())
    }

    func test_section_windowWithNilUsedPercent_noSparklineRow() {
        let history = [sample(windowMins: 300, hoursAgo: 1, used: 40)]
        let s = PopupContentBuilder.section(makeState(fiveHourUsed: nil), now: now, history: history)
        // Окно без данных — .note, спарклайн ему не положен даже при наличии истории.
        guard case .note = s.rows[1] else { return XCTFail("rows: \(s.rows)") }
        XCTAssertTrue(sparklines(s).isEmpty)
    }

    func test_section_historyForOtherWindow_doesNotLeakIntoRow() {
        let history = [
            sample(windowMins: 10080, hoursAgo: 3, used: 55),
            sample(windowMins: 10080, hoursAgo: 12, used: 50),
        ]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)

        let sparks = sparklines(s)
        XCTAssertEqual(sparks.count, 1)
        XCTAssertEqual(sparks.first?.windowMins, 10080)
        XCTAssertEqual(sparks.first?.shortLabel, "wk")
        // Между строкой 5h и строкой wk спарклайна нет.
        guard case .window = s.rows[1], case .window = s.rows[2],
              case .sparkline = s.rows[3] else {
            return XCTFail("спарклайн weekly должен идти после строки wk, rows: \(s.rows)")
        }
    }

    func test_section_staleState_stillInsertsSparklineForLastGoodSnapshot() {
        let lastGood = LimitsSnapshot(
            loggedIn: true, plan: "max",
            windows: [
                SnapshotWindow(windowDurationMins: 300, usedPercent: 50, resetsAt: nil),
                SnapshotWindow(windowDurationMins: 10080, usedPercent: 50, resetsAt: nil),
            ],
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: nil, fetchedAt: now.addingTimeInterval(-3600)
        )
        let fresh = LimitsSnapshot(
            loggedIn: true, plan: nil, windows: nil,
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: "network down", fetchedAt: now
        )
        let state = ProviderState(descriptor: claudeDescriptor, snapshot: fresh, lastGoodSnapshot: lastGood)
        let history = [
            sample(windowMins: 300, hoursAgo: 2, used: 40),
            sample(windowMins: 300, hoursAgo: 1, used: 45),
        ]
        let s = PopupContentBuilder.section(state, now: now, history: history)

        XCTAssertTrue(s.isStale)
        guard case .window = s.rows[1], case .sparkline(let spark) = s.rows[2] else {
            return XCTFail("спарклайн обязан строиться по last-good снапшоту, rows: \(s.rows)")
        }
        XCTAssertEqual(spark.windowMins, 300)
        XCTAssertEqual(spark.points.map(\.remainingPercent), [60, 55])
        XCTAssertEqual(spark.metric, .remainingPercent)
    }

    func test_section_insufficientHistory_noBurnRateRow() {
        let history = [
            sample(windowMins: 300, hoursAgo: 5, used: 30),
            sample(windowMins: 300, hoursAgo: 1, used: 40),
        ]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)
        XCTAssertTrue(burnRates(s).isEmpty)
    }

    func test_section_flatHistory_noBurnRateRow() {
        let history = (0..<4).map { i in
            sample(windowMins: 300, hoursAgo: Double(i + 1) * 2, used: 30)
        }
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)
        XCTAssertTrue(burnRates(s).isEmpty)
    }

    func test_section_burnRateByWindowMins_doesNotLeakAcrossWindows() {
        let history = [
            sample(windowMins: 300, hoursAgo: 10, used: 20),
            sample(windowMins: 300, hoursAgo: 5, used: 30),
            sample(windowMins: 300, hoursAgo: 2, used: 40),
        ]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)
        let burns = burnRates(s)
        XCTAssertEqual(burns.count, 1)
        XCTAssertEqual(burns.first?.windowMins, 300)
    }

    func test_section_burnRateForecastBeyondReset_suppressed() {
        let reset = now.addingTimeInterval(2 * 3600)
        let history = [
            sample(windowMins: 300, hoursAgo: 10, used: 10, resetsAt: reset),
            sample(windowMins: 300, hoursAgo: 5, used: 20, resetsAt: reset),
            sample(windowMins: 300, hoursAgo: 2, used: 30, resetsAt: reset),
        ]
        let state = makeState(fiveHourUsed: 35, fiveHourResetsAt: reset)
        let s = PopupContentBuilder.section(state, now: now, history: history)
        XCTAssertTrue(burnRates(s).isEmpty, "прогноз за пределами ресета должен подавляться")
    }
}

/// Глобальная настройка showUsageTrends (bd mac-limits-tracker-gld.4): выключение
/// заменяет `.sparkline` компактной `.note`-строкой, не трогая соседнюю `.window`
/// (текущий remaining/reset остаётся) и не шумя, когда истории вовсе нет (.empty).
final class PopupContentBuilderShowTrendsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeState(fiveHourUsed: Double? = 28) -> ProviderState {
        let snap = LimitsSnapshot(
            loggedIn: true, plan: "max",
            windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: fiveHourUsed, resetsAt: nil)],
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: nil, fetchedAt: now
        )
        return ProviderState(descriptor: claudeDescriptor, snapshot: snap)
    }

    private func sample(hoursAgo: Double, used: Double) -> UsageSample {
        UsageSample(providerId: "claude", windowMins: 300,
                    fetchedAt: now.addingTimeInterval(-hoursAgo * 3600),
                    usedPercent: used, resetsAt: nil)
    }

    private func hasSparkline(_ s: ProviderSectionContent) -> Bool {
        s.rows.contains { if case .sparkline = $0 { return true }; return false }
    }

    private func notes(_ s: ProviderSectionContent) -> [String] {
        s.rows.compactMap { if case .note(let t) = $0 { return t }; return nil }
    }

    func test_showTrendsDefault_insertsSparklineRow() {
        let history = [sample(hoursAgo: 2, used: 20), sample(hoursAgo: 1, used: 40)]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)
        XCTAssertTrue(hasSparkline(s))
    }

    func test_showTrendsFalse_okData_replacesSparklineWithCompactNote() {
        let history = [sample(hoursAgo: 2, used: 20), sample(hoursAgo: 1, used: 40)]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history, showTrends: false)

        XCTAssertFalse(hasSparkline(s), "график не должен рендериться при showTrends == false")
        XCTAssertTrue(notes(s).contains { $0.contains("80%") && $0.contains("60%") },
                      "компактная строка должна нести остаток начала и конца тренда, notes: \(notes(s))")
    }

    func test_showTrendsFalse_windowRowUnaffected() {
        let history = [sample(hoursAgo: 2, used: 20), sample(hoursAgo: 1, used: 40)]
        let sOn = PopupContentBuilder.section(makeState(), now: now, history: history, showTrends: true)
        let sOff = PopupContentBuilder.section(makeState(), now: now, history: history, showTrends: false)

        guard case .window(let onWindow) = sOn.rows[1], case .window(let offWindow) = sOff.rows[1] else {
            return XCTFail("окно должно остаться первой строкой usage независимо от showTrends")
        }
        XCTAssertEqual(onWindow.remainingText, offWindow.remainingText)
        XCTAssertEqual(onWindow.resetText, offWindow.resetText)
    }

    func test_showTrendsFalse_sparseData_showsFallbackNote() {
        let history = [sample(hoursAgo: 1, used: 40)]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history, showTrends: false)

        XCTAssertFalse(hasSparkline(s))
        XCTAssertTrue(notes(s).contains { $0.contains("1 sample") },
                      "недостаточные данные должны нести тот же fallbackText, что и маркеры графика, notes: \(notes(s))")
    }

    func test_showTrendsFalse_noHistory_staysNeutralNoRow() {
        let s = PopupContentBuilder.section(makeState(), now: now, history: [], showTrends: false)

        XCTAssertFalse(hasSparkline(s))
        XCTAssertTrue(notes(s).isEmpty, "нет истории вовсе — молчим так же, как и при включённых трендах, notes: \(notes(s))")
    }
}

final class PopupContentBuilderDailyBudgetTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private var descriptor: ProviderDescriptor {
        ProviderDescriptor(id: "daily", displayName: "Daily", shortName: "Daily",
                           menuBarSymbol: "D", accentColorHex: 0, loginHelp: nil)
    }

    private func state(windows: [SnapshotWindow], providerError: String? = nil,
                       lastGoodWindows: [SnapshotWindow]? = nil) -> ProviderState {
        let snapshot = LimitsSnapshot(
            loggedIn: true, plan: "plus", windows: windows,
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: providerError, fetchedAt: now)
        let lastGood = lastGoodWindows.map {
            LimitsSnapshot(loggedIn: true, plan: "plus", windows: $0,
                           creditsBalance: nil, rateLimitReachedType: nil, details: [],
                           daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
                           providerError: nil, fetchedAt: now.addingTimeInterval(-60))
        }
        return ProviderState(descriptor: descriptor, snapshot: snapshot, lastGoodSnapshot: lastGood)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func dailyBudget(in section: ProviderSectionContent) -> DailyBudgetContent? {
        for row in section.rows {
            if case .dailyBudget(let content) = row { return content }
        }
        return nil
    }

    func test_freshWeeklyWindow_addsDailyBudgetAfterWindow() throws {
        let weekly = SnapshotWindow(windowDurationMins: 10080, usedPercent: 41,
                                    resetsAt: now.addingTimeInterval(86_400))
        let section = PopupContentBuilder.section(state(windows: [weekly]), now: now,
                                                  showDailyBudget: true, calendar: utcCalendar())
        XCTAssertEqual(section.rows.count, 4)
        guard case .window = section.rows[1], case .paceComparison = section.rows[2],
              case .dailyBudget = section.rows[3] else {
            return XCTFail("daily budget must follow the weekly window: \(section.rows)")
        }
        XCTAssertNotNil(dailyBudget(in: section))
    }

    func test_freshWeeklyWindow_addsDailyBudgetOnMenuBarSurface() throws {
        let weekly = SnapshotWindow(windowDurationMins: 10080, usedPercent: 41,
                                    resetsAt: now.addingTimeInterval(86_400))
        let section = PopupContentBuilder.section(
            state(windows: [weekly]), now: now, surface: .menuBar,
            showDailyBudget: true, calendar: utcCalendar())

        XCTAssertEqual(section.rows.count, 2)
        guard section.rows.count == 2,
              case .window = section.rows[0], case .dailyBudget = section.rows[1] else {
            return XCTFail("daily budget must follow the weekly window on the menu-bar surface: \(section.rows)")
        }
        XCTAssertNotNil(dailyBudget(in: section))
    }

    func test_showDailyBudgetFalse_omitsRow() {
        let weekly = SnapshotWindow(windowDurationMins: 10080, usedPercent: 41,
                                    resetsAt: now.addingTimeInterval(86_400))
        let section = PopupContentBuilder.section(state(windows: [weekly]), now: now,
                                                  showDailyBudget: false, calendar: utcCalendar())
        XCTAssertNil(dailyBudget(in: section))
        XCTAssertEqual(section.rows.count, 3)
    }

    func test_onlyFiveHourWindow_omitsRow() {
        let fiveHour = SnapshotWindow(windowDurationMins: 300, usedPercent: 41,
                                      resetsAt: now.addingTimeInterval(86_400))
        XCTAssertNil(dailyBudget(in: PopupContentBuilder.section(
            state(windows: [fiveHour]), now: now, calendar: utcCalendar())))
    }

    func test_invalidWeeklyData_omitsRow() {
        let missingUsed = SnapshotWindow(windowDurationMins: 10080, usedPercent: nil,
                                         resetsAt: now.addingTimeInterval(86_400))
        let missingReset = SnapshotWindow(windowDurationMins: 10080, usedPercent: 50,
                                          resetsAt: nil)
        let pastReset = SnapshotWindow(windowDurationMins: 10080, usedPercent: 50,
                                      resetsAt: now.addingTimeInterval(-1))
        XCTAssertNil(dailyBudget(in: PopupContentBuilder.section(
            state(windows: [missingUsed]), now: now, calendar: utcCalendar())))
        XCTAssertNil(dailyBudget(in: PopupContentBuilder.section(
            state(windows: [missingReset]), now: now, calendar: utcCalendar())))
        XCTAssertNil(dailyBudget(in: PopupContentBuilder.section(
            state(windows: [pastReset]), now: now, calendar: utcCalendar())))
    }

    func test_staleWeeklyData_omitsRow() {
        let weekly = SnapshotWindow(windowDurationMins: 10080, usedPercent: 41,
                                    resetsAt: now.addingTimeInterval(86_400))
        let section = PopupContentBuilder.section(
            state(windows: [weekly], providerError: "network", lastGoodWindows: [weekly]),
            now: now, calendar: utcCalendar())
        XCTAssertTrue(section.isStale)
        XCTAssertNil(dailyBudget(in: section))
    }

    func test_zeroRemaining_keepsDailyBudgetRow() throws {
        let weekly = SnapshotWindow(windowDurationMins: 10080, usedPercent: 100,
                                    resetsAt: now.addingTimeInterval(86_400))
        let section = PopupContentBuilder.section(state(windows: [weekly]), now: now,
                                                  calendar: utcCalendar())
        XCTAssertEqual(try XCTUnwrap(dailyBudget(in: section)).budgetPercent, 0)
    }
}

final class PopupContentBuilderSurfaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func state() -> ProviderState {
        let snapshot = LimitsSnapshot(
            loggedIn: true,
            plan: "plus",
            windows: [
                SnapshotWindow(windowDurationMins: 10080, usedPercent: 40, resetsAt: now.addingTimeInterval(86_400)),
                SnapshotWindow(windowDurationMins: 300, usedPercent: 20, resetsAt: now.addingTimeInterval(3_600))
            ],
            creditsBalance: "12",
            rateLimitReachedType: "primary",
            details: [SnapshotDetail(key: "Account", value: "user@example.com")],
            daysUntilRenewal: 3,
            renewalDate: now.addingTimeInterval(3 * 86_400),
            usageError: nil,
            providerError: nil,
            fetchedAt: now
        )
        return ProviderState(descriptor: claudeDescriptor, snapshot: snapshot)
    }

    func test_desktop_ordersWindowsAndAddsPaceRows() {
        let rows = PopupContentBuilder.section(state(), now: now, surface: .desktop).rows
        let windowLabels = rows.compactMap { row -> String? in
            guard case .window(let content) = row else { return nil }
            return content.shortLabel
        }
        let paceRows = rows.compactMap { row -> PaceComparisonContent? in
            guard case .paceComparison(let content) = row else { return nil }
            return content
        }

        XCTAssertEqual(windowLabels, ["5h", "wk"])
        XCTAssertEqual(paceRows.map(\.windowDurationMins), [300, 10080])
    }

    func test_menuBarOmitsDetailAndTechnicalRows() {
        let rows = PopupContentBuilder.section(state(), now: now, surface: .menuBar).rows

        XCTAssertFalse(rows.contains { row in
            switch row {
            case .detail, .burnRate, .sparkline, .paceComparison, .cost:
                return true
            case .dailyBudget:
                return false
            case .window, .error, .recovery, .note:
                return false
            }
        })
        XCTAssertTrue(rows.contains { if case .dailyBudget = $0 { return true }; return false })
        XCTAssertTrue(rows.contains { if case .window = $0 { return true }; return false })
        XCTAssertTrue(rows.contains(.error("rate limit reached: primary")))
    }
}

final class PopupContentBuilderStaleTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 2_000_000)
    private static let past = Date(timeIntervalSince1970: 1_000_000)

    private func claudeWindow(_ utilization: Double, resetsAt: Date? = nil) -> ClaudeUsageWindow {
        ClaudeUsageWindow(utilizationPercent: utilization, resetsAt: resetsAt,
                          limitDollars: nil, usedDollars: nil, remainingDollars: nil)
    }

    private func claudeStatus(
        subscriptionType: String? = "max",
        usage: ClaudeUsage? = nil,
        usageError: String? = nil,
        providerError: String? = nil,
        fetchedAt: Date = Date(timeIntervalSince1970: 2_000_000)
    ) -> ClaudeStatus {
        ClaudeStatus(
            loggedIn: true, authMethod: "claude.ai", apiProvider: nil, email: "a@b.co",
            subscriptionType: subscriptionType, orgName: nil,
            today: nil, latestDay: nil, lastComputedDate: nil,
            totalSessions: nil, totalMessages: nil,
            usage: usage, usageError: usageError,
            fetchedAt: fetchedAt, providerError: providerError
        )
    }

    func test_staleProviderError_rendersLastGoodDataWithNoteAndError() {
        let lastGood = claudeStatus(
            subscriptionType: "max",
            usage: ClaudeUsage(fiveHour: claudeWindow(50), sevenDay: claudeWindow(50)),
            fetchedAt: Self.past
        ).toSnapshot()
        let fresh = claudeStatus(providerError: "network down")
        let state = ProviderState(descriptor: claudeDescriptor, snapshot: fresh.toSnapshot(), lastGoodSnapshot: lastGood)
        let s = PopupContentBuilder.section(state, now: Self.now)

        XCTAssertTrue(s.isStale)
        XCTAssertEqual(s.rows.count, 5)
        XCTAssertEqual(s.rows[0], .detail(key: "Plan", value: "max"))
        guard case .window(let w) = s.rows[1] else {
            return XCTFail("ожидалось окно из last-good, rows: \(s.rows)")
        }
        XCTAssertEqual(w.remainingPercent, 50)
        guard case .note(let note) = s.rows[3] else {
            return XCTFail("ожидалась .note 'updated ... ago', rows: \(s.rows)")
        }
        XCTAssertTrue(note.hasPrefix("updated "), "note: \(note)")
        XCTAssertEqual(s.rows[4], recovery("Claude Code error — retry", action: .retry, diagnostic: "network down"))
    }

    func test_providerErrorWithoutLastGood_isSingleErrorRowAndNotStale() {
        let fresh = claudeStatus(providerError: "no auth.json")
        let state = ProviderState(descriptor: claudeDescriptor, snapshot: fresh.toSnapshot(), lastGoodSnapshot: nil)
        let s = PopupContentBuilder.section(state, now: Self.now)

        XCTAssertFalse(s.isStale)
        XCTAssertEqual(s.rows, [recovery("Claude Code error — retry", action: .retry, diagnostic: "no auth.json")])
    }

    func test_staleUsageError_mergesFreshPlanWithLastGoodWindows() {
        let lastGood = claudeStatus(
            subscriptionType: "old-plan",
            usage: ClaudeUsage(fiveHour: claudeWindow(30), sevenDay: claudeWindow(30)),
            fetchedAt: Self.past
        ).toSnapshot()
        let fresh = claudeStatus(subscriptionType: "new-plan", usageError: "usage endpoint 500")
        let state = ProviderState(descriptor: claudeDescriptor, snapshot: fresh.toSnapshot(), lastGoodSnapshot: lastGood)
        let s = PopupContentBuilder.section(state, now: Self.now)

        XCTAssertTrue(s.isStale)
        XCTAssertEqual(s.rows.count, 5)
        XCTAssertEqual(s.rows[0], .detail(key: "Plan", value: "new-plan"))
        guard case .window(let w) = s.rows[1] else {
            return XCTFail("ожидалось окно из last-good, rows: \(s.rows)")
        }
        XCTAssertEqual(w.remainingPercent, 70)
        guard case .note(let note) = s.rows[3] else {
            return XCTFail("ожидалась .note 'updated ... ago', rows: \(s.rows)")
        }
        XCTAssertTrue(note.hasPrefix("updated "), "note: \(note)")
        XCTAssertEqual(s.rows[4], recovery("Claude Code error — retry", action: .retry, diagnostic: "usage endpoint 500"))
    }

    func test_updatedText_staleUsesLastGoodFetchedAt() {
        let lastGood = claudeStatus(subscriptionType: "max", fetchedAt: Self.past).toSnapshot()
        let fresh = claudeStatus(providerError: "network down", fetchedAt: Self.now).toSnapshot()
        let state = ProviderState(descriptor: claudeDescriptor, snapshot: fresh, lastGoodSnapshot: lastGood)
        let text = PopupContentBuilder.updatedText(states: [state])

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        XCTAssertEqual(text, "Updated \(formatter.string(from: Self.past))")
    }
}

final class PopupContentBuilderSectionsTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 2_000_000)
    private static let past = Date(timeIntervalSince1970: 1_000_000)

    private func state(
        descriptor: ProviderDescriptor,
        plan: String? = nil,
        windows: [SnapshotWindow]?,
        providerError: String? = nil,
        lastGoodWindows: [SnapshotWindow]? = nil,
        lastGoodPlan: String? = nil,
        fetchedAt: Date = Date(timeIntervalSince1970: 2_000_000)
    ) -> ProviderState {
        let snapshot = LimitsSnapshot(
            loggedIn: true, plan: plan, windows: windows,
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: providerError, fetchedAt: fetchedAt
        )
        let lastGood: LimitsSnapshot? = lastGoodWindows.map {
            LimitsSnapshot(
                loggedIn: true, plan: lastGoodPlan, windows: $0,
                creditsBalance: nil, rateLimitReachedType: nil, details: [],
                daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
                providerError: nil, fetchedAt: Self.past
            )
        }
        return ProviderState(descriptor: descriptor, snapshot: snapshot, lastGoodSnapshot: lastGood)
    }

    private func sample(providerId: String, windowMins: Int, hoursAgo: Double, used: Double) -> UsageSample {
        UsageSample(
            providerId: providerId,
            windowMins: windowMins,
            fetchedAt: Self.now.addingTimeInterval(-hoursAgo * 3600),
            usedPercent: used,
            resetsAt: nil
        )
    }

    private func containsSparkline(_ rows: [PopupRow]) -> Bool {
        rows.contains { if case .sparkline = $0 { return true }; return false }
    }

    func test_sections_mapsStatesInOrder() {
        let states = [
            state(descriptor: claudeDescriptor, windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: 10, resetsAt: nil)]),
            state(descriptor: codexDescriptor, windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: 20, resetsAt: nil)])
        ]
        let sections: [ProviderSectionContent] = PopupContentBuilder.sections(states, now: Self.now)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].descriptor.id, "claude")
        XCTAssertEqual(sections[0].title, "Claude Code")
        XCTAssertEqual(sections[1].descriptor.id, "codex")
        XCTAssertEqual(sections[1].title, "Codex")
    }

    func test_sections_routesHistoryByProviderId() {
        var requestedIds: [String] = []
        let claudeState = state(descriptor: claudeDescriptor, windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: 10, resetsAt: nil)])
        let codexState = state(descriptor: codexDescriptor, windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: 20, resetsAt: nil)])
        let history: (String) -> [UsageSample] = { id in
            requestedIds.append(id)
            if id == "claude" {
                return [
                    self.sample(providerId: "claude", windowMins: 300, hoursAgo: 2, used: 25),
                    self.sample(providerId: "claude", windowMins: 300, hoursAgo: 1, used: 30),
                ]
            }
            return []
        }
        let sections: [ProviderSectionContent] = PopupContentBuilder.sections([claudeState, codexState], now: Self.now, history: history)
        XCTAssertEqual(requestedIds, ["claude", "codex"])
        XCTAssertTrue(containsSparkline(sections[0].rows))
        XCTAssertFalse(containsSparkline(sections[1].rows))
    }

    func test_sections_propagatesThresholds() {
        let strict = SeverityThresholds(warningRemaining: 60, criticalRemaining: 50)
        let s = state(
            descriptor: claudeDescriptor,
            windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: 50, resetsAt: nil)]
        )
        let strictSections: [ProviderSectionContent] = PopupContentBuilder.sections([s], now: Self.now, thresholds: strict)
        guard case .window(let w) = strictSections[0].rows[1] else {
            return XCTFail("expected window row, rows: \(strictSections[0].rows)")
        }
        XCTAssertEqual(w.severity, .critical)

        let standardSections: [ProviderSectionContent] = PopupContentBuilder.sections([s], now: Self.now)
        guard case .window(let w2) = standardSections[0].rows[1] else {
            return XCTFail("expected window row, rows: \(standardSections[0].rows)")
        }
        XCTAssertEqual(w2.severity, .normal)
    }

    func test_sections_emptyStates_returnsEmpty() {
        let sections: [ProviderSectionContent] = PopupContentBuilder.sections([], now: Self.now)
        XCTAssertEqual(sections, [])
    }

    func test_sections_staleState_rendersNoteAndErrorRows() {
        let lastGood = [SnapshotWindow(windowDurationMins: 300, usedPercent: 50, resetsAt: nil)]
        let s = state(
            descriptor: claudeDescriptor,
            plan: "max",
            windows: nil,
            providerError: "network down",
            lastGoodWindows: lastGood,
            lastGoodPlan: "max"
        )
        let sections: [ProviderSectionContent] = PopupContentBuilder.sections([s], now: Self.now)
        XCTAssertEqual(sections.count, 1)
        XCTAssertTrue(sections[0].isStale)
        XCTAssertEqual(sections[0].rows.count, 4)
        XCTAssertEqual(sections[0].rows[0], .detail(key: "Plan", value: "max"))
        guard case .window(let w) = sections[0].rows[1] else {
            return XCTFail("expected window from last-good, rows: \(sections[0].rows)")
        }
        XCTAssertEqual(w.remainingPercent, 50)
        guard case .note(let note) = sections[0].rows[2] else {
            return XCTFail("expected note 'updated ... ago', rows: \(sections[0].rows)")
        }
        XCTAssertTrue(note.hasPrefix("updated "), "note: \(note)")
        XCTAssertEqual(sections[0].rows[3], recovery("Claude Code error — retry", action: .retry, diagnostic: "network down"))
    }
}

private func recovery(_ primaryText: String, action: ProviderRecoveryAction, diagnostic: String) -> PopupRow {
    .recovery(ProviderRecoveryContent(primaryText: primaryText, action: action, diagnostic: diagnostic))
}

/// Контракт 7-дневного тренда: единая метрика remainingPercent, сортировка,
/// клемпирование, дедуп timestamp, минимум точек, разрывы, empty/sparse.
final class SparklineTrendContractTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var rangeStart: Date { now.addingTimeInterval(-7 * 24 * 3600) }
    private var rangeEnd: Date { now }

    private func sample(hoursAgo: Double, used: Double, windowMins: Int = 300) -> UsageSample {
        UsageSample(providerId: "claude", windowMins: windowMins,
                    fetchedAt: now.addingTimeInterval(-hoursAgo * 3600),
                    usedPercent: used, resetsAt: nil)
    }

    private func trendContent(
        samples: [UsageSample],
        currentUsed: Double = 50,
        windowMins: Int = 300,
        minPoints: Int = 2,
        gapThreshold: TimeInterval = 24 * 3600
    ) -> SparklineContent {
        PopupContentBuilder.trendContent(
            samples: samples,
            windowMins: windowMins,
            shortLabel: "5h",
            windowLabel: "5-hour",
            currentUsedPercent: currentUsed,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            minPoints: minPoints,
            gapThreshold: gapThreshold
        )
    }

    // MARK: — conversion/clamp/sort/dup

    func test_conversion_usedPercentBecomesRemainingPercent() {
        let trend = trendContent(samples: [
            sample(hoursAgo: 3, used: 20),
            sample(hoursAgo: 1, used: 40),
        ])
        XCTAssertEqual(trend.metric, .remainingPercent)
        XCTAssertEqual(trend.points.map(\.remainingPercent), [80, 60])
    }

    func test_clamp_remainingPercentClampedTo0To100() {
        let trend = trendContent(samples: [
            sample(hoursAgo: 2, used: -20),
            sample(hoursAgo: 1, used: 150),
        ])
        XCTAssertEqual(trend.points.map(\.remainingPercent), [100, 0])
    }

    func test_rangeBoundary_sampleAtRangeStart_isIncluded() {
        let trend = trendContent(samples: [
            sample(hoursAgo: 24 * 7 - 1, used: 10),
            sample(hoursAgo: 24 * 7 - 2, used: 20),
            sample(hoursAgo: 1, used: 40),
        ])
        XCTAssertEqual(trend.points.count, 3)
        XCTAssertEqual(trend.points.first?.remainingPercent, 90)
    }

    func test_sort_pointsAreChronological() {
        let trend = trendContent(samples: [
            sample(hoursAgo: 1, used: 10),
            sample(hoursAgo: 5, used: 30),
            sample(hoursAgo: 2, used: 20),
        ])
        XCTAssertEqual(trend.points.map(\.remainingPercent), [70, 80, 90])
        XCTAssertTrue(trend.points.map(\.time) == trend.points.map(\.time).sorted())
    }

    func test_duplicateTimestamp_keepsLast() {
        let trend = trendContent(samples: [
            sample(hoursAgo: 1, used: 10),
            sample(hoursAgo: 1, used: 50),
        ])
        XCTAssertEqual(trend.points.count, 1)
        XCTAssertEqual(trend.points.first?.remainingPercent, 50)
    }

    // MARK: — gap

    func test_gap_largeGapBetweenPoints_returnsGapState() {
        let trend = trendContent(samples: [
            sample(hoursAgo: 1, used: 20),
            sample(hoursAgo: 48, used: 30),
        ])
        guard case .gap(let gap, let threshold) = trend.dataState else {
            return XCTFail("ожидался .gap, получен \(trend.dataState)")
        }
        XCTAssertGreaterThan(gap, 24 * 3600)
        XCTAssertEqual(threshold, 24 * 3600)
    }

    // MARK: — empty/sparse/ok

    func test_empty_noSamples_returnsEmptyState() {
        let trend = trendContent(samples: [])
        XCTAssertEqual(trend.dataState, .empty)
        XCTAssertTrue(trend.points.isEmpty)
        XCTAssertEqual(trend.fallbackText, "7d — no history")
    }

    func test_sparse_oneSample_returnsSparseState() {
        let trend = trendContent(samples: [sample(hoursAgo: 1, used: 40)])
        guard case .sparse(let count, let min) = trend.dataState else {
            return XCTFail("ожидался .sparse, получен \(trend.dataState)")
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(min, 2)
        XCTAssertEqual(trend.fallbackText, "7d — 1 sample, need 2")
    }

    func test_ok_enoughPointsNoGap_returnsOkState() {
        let trend = trendContent(samples: [
            sample(hoursAgo: 3, used: 20),
            sample(hoursAgo: 2, used: 25),
            sample(hoursAgo: 1, used: 30),
        ])
        XCTAssertEqual(trend.dataState, .ok)
        XCTAssertEqual(trend.points.map(\.remainingPercent), [80, 75, 70])
    }
}
