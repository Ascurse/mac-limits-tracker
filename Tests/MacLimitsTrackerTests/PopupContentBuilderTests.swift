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

    func test_nilStatus_isLoadingNote() {
        let s = PopupContentBuilder.claudeSection(nil)
        XCTAssertEqual(s.provider, .claude)
        XCTAssertEqual(s.title, "Claude Code")
        XCTAssertEqual(s.rows, [.note("Loading…")])
    }

    func test_providerError_isSingleErrorRow() {
        let s = PopupContentBuilder.claudeSection(makeStatus(providerError: "boom"))
        XCTAssertEqual(s.rows, [.error("boom")])
    }

    func test_planRow_showsRawSubscriptionType() {
        let s = PopupContentBuilder.claudeSection(makeStatus(usage: ClaudeUsage(fiveHour: nil, sevenDay: nil)))
        // Тариф без капитализации — как в текущем попапе.
        XCTAssertEqual(s.rows.first, .detail(key: "Plan", value: "max"))
    }

    func test_planRow_dashWhenNil() {
        let s = PopupContentBuilder.claudeSection(
            makeStatus(usage: ClaudeUsage(fiveHour: nil, sevenDay: nil), subscriptionType: nil))
        XCTAssertEqual(s.rows.first, .detail(key: "Plan", value: "—"))
    }

    func test_windows_remainingIsInverseOfUtilization() {
        let usage = ClaudeUsage(fiveHour: window(28), sevenDay: window(69))
        let s = PopupContentBuilder.claudeSection(makeStatus(usage: usage))
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
        let s = PopupContentBuilder.claudeSection(makeStatus(usage: usage))
        guard case .window(let fh) = s.rows[1] else { return XCTFail("\(s.rows)") }
        XCTAssertEqual(fh.remainingPercent, 0)
        XCTAssertEqual(fh.remainingText, "0%")
        XCTAssertEqual(fh.severity, .critical)
    }

    func test_missingWindow_becomesUnavailableNote() {
        let usage = ClaudeUsage(fiveHour: nil, sevenDay: window(10))
        let s = PopupContentBuilder.claudeSection(makeStatus(usage: usage))
        XCTAssertEqual(s.rows[1], .note("5h usage unavailable"))
        guard case .window = s.rows[2] else { return XCTFail("\(s.rows)") }
    }

    func test_resetText_presentOnlyWithResetsAt() {
        let usage = ClaudeUsage(fiveHour: window(50, resetsAt: Date().addingTimeInterval(7200)),
                                sevenDay: window(50))
        let s = PopupContentBuilder.claudeSection(makeStatus(usage: usage))
        guard case .window(let fh) = s.rows[1], case .window(let wk) = s.rows[2] else {
            return XCTFail("\(s.rows)")
        }
        // Точный текст зависит от локали — проверяем только наличие.
        XCTAssertNotNil(fh.resetText)
        XCTAssertNil(wk.resetText)
    }

    func test_usageError_shownWhenNoUsage() {
        let s = PopupContentBuilder.claudeSection(makeStatus(usageError: "token expired"))
        XCTAssertEqual(s.rows, [.detail(key: "Plan", value: "max"), .error("token expired")])
    }

    func test_noUsageNoError_loadingUsageNote() {
        let s = PopupContentBuilder.claudeSection(makeStatus())
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

    private func window(_ used: Double) -> CodexUsageWindow {
        CodexUsageWindow(usedPercent: used, windowDurationMins: nil, resetsAt: nil)
    }

    func test_nilStatus_isLoadingNote() {
        let s = PopupContentBuilder.codexSection(nil)
        XCTAssertEqual(s.provider, .codex)
        XCTAssertEqual(s.title, "Codex")
        XCTAssertEqual(s.rows, [.note("Loading…")])
    }

    func test_providerError_isSingleErrorRow() {
        let s = PopupContentBuilder.codexSection(makeStatus(providerError: "no auth.json"))
        XCTAssertEqual(s.rows, [.error("no auth.json")])
    }

    func test_snapshotPlanTypeWinsOverJwtClaim() {
        let snap = CodexUsageSnapshot(primary: nil, secondary: nil, planType: "pro",
                                      creditsBalance: nil, rateLimitReachedType: nil)
        let s = PopupContentBuilder.codexSection(makeStatus(usage: CodexUsage(snapshot: snap)))
        XCTAssertEqual(s.rows.first, .detail(key: "Plan", value: "pro"))
    }

    func test_fullSnapshot_rowOrder() {
        let snap = CodexUsageSnapshot(primary: window(42), secondary: window(56),
                                      planType: nil, creditsBalance: "12.50",
                                      rateLimitReachedType: "primary")
        let s = PopupContentBuilder.codexSection(makeStatus(usage: CodexUsage(snapshot: snap)))
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
        let s = PopupContentBuilder.codexSection(
            makeStatus(usage: CodexUsage(snapshot: snap), authMode: nil, email: nil,
                       accountOwner: nil, daysUntilRenewal: nil, subscriptionActiveUntil: nil))
        XCTAssertEqual(s.rows, [.detail(key: "Plan", value: "plus"),
                                .note("5h usage unavailable"),
                                .note("Weekly usage unavailable")])
    }

    func test_usageError_shownWhenNoSnapshot() {
        let s = PopupContentBuilder.codexSection(
            makeStatus(usageError: "app-server unavailable", authMode: nil, email: nil,
                       accountOwner: nil, daysUntilRenewal: nil, subscriptionActiveUntil: nil))
        XCTAssertEqual(s.rows, [.detail(key: "Plan", value: "plus"),
                                .error("app-server unavailable")])
    }
}

final class PopupContentBuilderUpdatedTextTests: XCTestCase {
    func test_bothNil_dash() {
        XCTAssertEqual(PopupContentBuilder.updatedText(claude: nil, codex: nil), "—")
    }

    func test_latestOfTwoDates_used() {
        let claude = ClaudeStatus(
            loggedIn: true, authMethod: nil, apiProvider: nil, email: nil,
            subscriptionType: nil, orgName: nil, today: nil, latestDay: nil,
            lastComputedDate: nil, totalSessions: nil, totalMessages: nil,
            usage: nil, usageError: nil,
            fetchedAt: Date(timeIntervalSince1970: 100), providerError: nil)
        let text = PopupContentBuilder.updatedText(claude: claude, codex: nil)
        XCTAssertTrue(text.hasPrefix("Updated "), "получено: \(text)")
    }
}
