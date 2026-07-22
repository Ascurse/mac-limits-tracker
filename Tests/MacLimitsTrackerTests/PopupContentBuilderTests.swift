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
}

private let claudeDescriptor = ProviderDescriptor(
    id: "claude", displayName: "Claude Code", shortName: "Claude",
    menuBarSymbol: "C", accentColorHex: 0xFF9E64, loginHelp: nil
)

private let codexDescriptor = ProviderDescriptor(
    id: "codex", displayName: "Codex", shortName: "Codex",
    menuBarSymbol: "X", accentColorHex: 0x9ECE6A, loginHelp: nil
)

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
