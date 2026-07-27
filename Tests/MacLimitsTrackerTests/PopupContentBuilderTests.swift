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

final class SeverityThresholdsTests: XCTestCase {
    /// Инвариант: critical строго ниже warning, иначе зона warning недостижима.
    func test_init_clampsCriticalBelowWarning() {
        let t = SeverityThresholds(warningRemaining: 20, criticalRemaining: 25)
        XCTAssertEqual(t.warningRemaining, 20)
        XCTAssertLessThan(t.criticalRemaining, t.warningRemaining)
    }

    func test_standard_matchesHardcodedDefaults() {
        XCTAssertEqual(SeverityThresholds.standard.warningRemaining, 40)
        XCTAssertEqual(SeverityThresholds.standard.criticalRemaining, 15)
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
        XCTAssertEqual(s.rows, [.error("boom")])
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
        guard case .window(let fh) = s.rows[1], case .window(let wk) = s.rows[2] else {
            return XCTFail("ожидались окна, rows: \(s.rows)")
        }
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
        guard case .window(let fh) = s.rows[1], case .window(let wk) = s.rows[2] else {
            return XCTFail("\(s.rows)")
        }
        // Точный текст зависит от локали — проверяем только наличие.
        XCTAssertNotNil(fh.resetText)
        XCTAssertNil(wk.resetText)
    }

    func test_usageError_shownWhenNoUsage() {
        let s = section(makeStatus(usageError: "token expired"))
        XCTAssertEqual(s.rows, [.detail(key: "Plan", value: "max"), .error("token expired")])
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
        XCTAssertEqual(s.rows, [.error("no auth.json")])
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
                                .error("app-server unavailable")])
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
            .error("Kimi login expired — open Kimi Code to refresh")
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
        XCTAssertEqual(s.rows, [.error("kimi-code refresh token missing")])
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

/// Спарклайн использования за 24ч: билдер вставляет `.sparkline` сразу после
/// строки своего окна; идентичность окна — windowMins, никогда не индекс.
final class PopupContentBuilderSparklineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeState(fiveHourUsed: Double? = 28, weeklyUsed: Double? = 69) -> ProviderState {
        let snap = LimitsSnapshot(
            loggedIn: true, plan: "max",
            windows: [
                SnapshotWindow(windowDurationMins: 300, usedPercent: fiveHourUsed, resetsAt: nil),
                SnapshotWindow(windowDurationMins: 10080, usedPercent: weeklyUsed, resetsAt: nil),
            ],
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: nil, fetchedAt: now
        )
        return ProviderState(descriptor: claudeDescriptor, snapshot: snap)
    }

    private func sample(windowMins: Int, hoursAgo: Double, used: Double) -> UsageSample {
        UsageSample(providerId: "claude", windowMins: windowMins,
                    fetchedAt: now.addingTimeInterval(-hoursAgo * 3600),
                    usedPercent: used, resetsAt: nil)
    }

    private func sparklines(_ s: ProviderSectionContent) -> [SparklineContent] {
        s.rows.compactMap {
            if case .sparkline(let c) = $0 { return c }
            return nil
        }
    }

    func test_section_withHistory_insertsSparklineAfterMatchingWindowRow() {
        // Порядок входных сэмплов намеренно не хронологический.
        let history = [
            sample(windowMins: 300, hoursAgo: 2, used: 40),
            sample(windowMins: 300, hoursAgo: 10, used: 20),
            sample(windowMins: 300, hoursAgo: 5, used: 30),
        ]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)

        XCTAssertEqual(s.rows.count, 4)
        guard case .window(let fh) = s.rows[1] else { return XCTFail("rows: \(s.rows)") }
        XCTAssertEqual(fh.shortLabel, "5h")
        guard case .sparkline(let spark) = s.rows[2] else {
            return XCTFail("ожидался .sparkline сразу после строки 5h, rows: \(s.rows)")
        }
        XCTAssertEqual(spark.windowMins, 300)
        XCTAssertEqual(spark.shortLabel, "5h")
        // Точки отсортированы по времени по возрастанию.
        XCTAssertEqual(spark.points.map(\.usedPercent), [20, 30, 40])
        XCTAssertTrue(spark.points.map(\.time) == spark.points.map(\.time).sorted())
        guard case .window(let wk) = s.rows[3] else { return XCTFail("rows: \(s.rows)") }
        XCTAssertEqual(wk.shortLabel, "wk")
    }

    func test_section_emptyHistory_noSparklineRows() {
        let s = PopupContentBuilder.section(makeState(), now: now, history: [])
        XCTAssertTrue(sparklines(s).isEmpty)
    }

    func test_section_samplesOlderThan24h_noSparklineRow() {
        let history = [
            sample(windowMins: 300, hoursAgo: 25, used: 40),
            sample(windowMins: 300, hoursAgo: 48, used: 20),
        ]
        let s = PopupContentBuilder.section(makeState(), now: now, history: history)
        XCTAssertTrue(sparklines(s).isEmpty)
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
        let history = [sample(windowMins: 300, hoursAgo: 1, used: 45)]
        let s = PopupContentBuilder.section(state, now: now, history: history)

        XCTAssertTrue(s.isStale)
        guard case .window = s.rows[1], case .sparkline(let spark) = s.rows[2] else {
            return XCTFail("спарклайн обязан строиться по last-good снапшоту, rows: \(s.rows)")
        }
        XCTAssertEqual(spark.windowMins, 300)
        XCTAssertEqual(spark.points.map(\.usedPercent), [45])
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
        XCTAssertEqual(s.rows[4], .error("network down"))
    }

    func test_providerErrorWithoutLastGood_isSingleErrorRowAndNotStale() {
        let fresh = claudeStatus(providerError: "no auth.json")
        let state = ProviderState(descriptor: claudeDescriptor, snapshot: fresh.toSnapshot(), lastGoodSnapshot: nil)
        let s = PopupContentBuilder.section(state, now: Self.now)

        XCTAssertFalse(s.isStale)
        XCTAssertEqual(s.rows, [.error("no auth.json")])
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
        XCTAssertEqual(s.rows[4], .error("usage endpoint 500"))
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
