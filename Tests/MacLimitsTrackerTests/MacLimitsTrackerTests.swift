import XCTest
@testable import MacLimitsTrackerCore

final class ClaudeAuthParserTests: XCTestCase {
    func test_parsesMinimalAuthStatus() throws {
        let json = """
        {"loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty",
         "email": "a@b.co", "subscriptionType": "max",
         "orgName": "a@b.co's Organization"}
        """
        let status = ClaudeAuthParser.parse(json.data(using: .utf8)!)
        XCTAssertTrue(status.loggedIn)
        XCTAssertEqual(status.subscriptionType, "max")
        XCTAssertEqual(status.email, "a@b.co")
        XCTAssertEqual(status.authMethod, "claude.ai")
    }

    func test_returnsLoggedOutOnMalformedJSON() {
        let status = ClaudeAuthParser.parse(Data("garbage".utf8))
        XCTAssertFalse(status.loggedIn)
        XCTAssertNil(status.subscriptionType)
    }
}

final class StatsCacheUsageTests: XCTestCase {
    private func makeCache(todayKey: String) -> StatsCache {
        StatsCache(
            version: 4,
            lastComputedDate: todayKey,
            dailyActivity: [
                .init(date: "2026-04-23", messageCount: 1, sessionCount: 1, toolCallCount: 0),
                .init(date: todayKey, messageCount: 325, sessionCount: 1, toolCallCount: 92)
            ],
            dailyModelTokens: [
                .init(date: "2026-04-23", tokensByModel: ["claude-opus-4-7": 100]),
                .init(date: todayKey, tokensByModel: ["claude-opus-4-7": 1000, "claude-haiku-4-5": 200])
            ],
            totalSessions: 2,
            totalMessages: 326
        )
    }

    func test_todayUsageAggregatesAcrossModels() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var refComps = DateComponents()
        refComps.year = 2026; refComps.month = 7; refComps.day = 11
        let ref = cal.date(from: refComps)!

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        formatter.dateFormat = "yyyy-MM-dd"
        let todayKey = formatter.string(from: ref)

        let cache = makeCache(todayKey: todayKey)
        let usage = StatsCacheUsage.todayUsage(from: cache, on: ref, calendar: cal)
        XCTAssertEqual(usage?.messageCount, 325)
        XCTAssertEqual(usage?.sessionCount, 1)
        XCTAssertEqual(usage?.toolCallCount, 92)
        XCTAssertEqual(usage?.tokens, 1200)
    }

    func test_todayUsageReturnsNilWhenNoDayMatches() {
        let cache = makeCache(todayKey: "2026-04-23")
        let usage = StatsCacheUsage.todayUsage(from: cache, on: Date(timeIntervalSince1970: 0),
                                               calendar: .current)
        XCTAssertNil(usage)
    }
}

final class CodexClaimsParserTests: XCTestCase {
    /// JWT с payload { ... chatgpt_plan_type: "plus", email: ..., ... }.
    /// Сгенерирован локально: header.payload.signature без подписи — нам важен только payload.
    func jwt(payload: [String: Any]) -> String {
        let header = Data("{\"alg\":\"none\"}".utf8).base64URLEncodedString()
            .replacingOccurrences(of: "=", with: "")
        let body = try! JSONSerialization.data(withJSONObject: payload)
        let bodyB64 = body.base64URLEncodedString()
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(bodyB64).sig"
    }

    func test_parsesPlusPlanAndEmail() {
        let payload: [String: Any] = [
            "email": "tester@example.com",
            "https://api.openai.com/auth": [
                "chatgpt_plan_type": "plus",
                "chatgpt_subscription_active_until": "2026-08-01T00:00:00+00:00",
                "organizations": [["title": "Personal", "is_default": true, "role": "owner"]]
            ]
        ]
        let claims = CodexClaimsParser.parse(jwt(payload: payload))
        XCTAssertEqual(claims.planType, "plus")
        XCTAssertEqual(claims.email, "tester@example.com")
        XCTAssertEqual(claims.accountOwner, "Personal")
        XCTAssertNotNil(claims.subscriptionActiveUntil)
    }

    func test_handlesMalformedToken() {
        let claims = CodexClaimsParser.parse("not.a.valid-base64!@#")
        XCTAssertNil(claims.planType)
        XCTAssertNil(claims.email)
    }

    func test_daysUntilRenewal_returnsPositiveDays_forFutureDate() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 11
        let now = Calendar(identifier: .gregorian).date(from: comps)!
        var untilComps = DateComponents()
        untilComps.year = 2026; untilComps.month = 7; untilComps.day = 25
        let until = Calendar(identifier: .gregorian).date(from: untilComps)!
        let claims = ChatGPTClaims(email: nil, planType: "plus",
                                    subscriptionActiveUntil: until, accountOwner: nil)
        let days = CodexClaimsParser.daysUntilRenewal(from: claims, referenceDate: now,
                                                       calendar: .current)
        XCTAssertEqual(days, 14)
    }

    func test_daysUntilRenewal_returnsNil_forPastDate() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 11
        let now = Calendar(identifier: .gregorian).date(from: comps)!
        let past = ChatGPTClaims(email: nil, planType: nil,
                                  subscriptionActiveUntil: now.addingTimeInterval(-86_400),
                                  accountOwner: nil)
        XCTAssertNil(CodexClaimsParser.daysUntilRenewal(from: past,
                                                         referenceDate: now,
                                                         calendar: .current))
    }

    func test_daysUntilRenewal_returnsNil_whenClaimMissing() {
        let claims = ChatGPTClaims(email: nil, planType: nil,
                                    subscriptionActiveUntil: nil, accountOwner: nil)
        XCTAssertNil(CodexClaimsParser.daysUntilRenewal(from: claims))
    }

    func test_authFileDecodesAuthModeAndTokens() throws {
        let payload: [String: Any] = ["email": "e@f.co",
            "https://api.openai.com/auth": ["chatgpt_plan_type": "plus"]]
        let token = "h.\(Data("{\"email\":\"e@f.co\",\"https://api.openai.com/auth\":{\"chatgpt_plan_type\":\"plus\"}}".utf8).base64URLEncodedString().replacingOccurrences(of: "=", with: "")).sig"
        let json = """
        {"auth_mode":"chatgpt","OPENAI_API_KEY":null,
         "tokens":{"id_token":"\(token)","access_token":null}}
        """
        let file = try JSONDecoder().decode(CodexAuthFileJSON.self,
                                            from: Data(json.utf8))
        XCTAssertEqual(file.authMode, "chatgpt")
        XCTAssertEqual(file.tokens?.idToken, token)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}

final class DefaultClaudeBinaryTests: XCTestCase {
    func test_prefersExplicitClaudeBinEnv() {
        let path = ProcessRunner.defaultClaudeBinary(
            environment: ["CLAUDE_BIN": "/custom/path/claude", "HOME": "/Users/test"],
            fileExists: { _ in false }
        )
        XCTAssertEqual(path, "/custom/path/claude")
    }

    func test_picksFirstExistingCandidate() {
        let path = ProcessRunner.defaultClaudeBinary(
            environment: ["HOME": "/Users/test"],
            fileExists: { $0 == "/opt/homebrew/bin/claude" }
        )
        XCTAssertEqual(path, "/opt/homebrew/bin/claude")
    }

    func test_prefersLocalBinOverHomebrewWhenBothExist() {
        let path = ProcessRunner.defaultClaudeBinary(
            environment: ["HOME": "/Users/test"],
            fileExists: { _ in true }
        )
        XCTAssertEqual(path, "/Users/test/.local/bin/claude")
    }

    func test_fallsBackToLastCandidateWhenNoneExist() {
        let path = ProcessRunner.defaultClaudeBinary(
            environment: ["HOME": "/Users/test"],
            fileExists: { _ in false }
        )
        XCTAssertEqual(path, "/usr/local/bin/claude")
    }
}

final class ClaudeLimitsProviderTests: XCTestCase {
    private struct StubError: Error {}

    func test_fetchCombinesErrorsFromBothSourcesWhenBothFail() async {
        let provider = ClaudeLimitsProvider(
            claudeBinary: "/bin/does-not-matter",
            statsCacheURL: URL(fileURLWithPath: "/does/not/matter.json"),
            processRunner: { _, _ in throw StubError() },
            fileReader: { _ in throw StubError() },
            keychainReader: { throw StubError() },
            httpGet: { _, _ in throw StubError() }
        )
        let status = await provider.fetch()
        XCTAssertTrue(status.providerError?.contains("claude auth status failed") ?? false)
        XCTAssertTrue(status.providerError?.contains("stats cache read failed") ?? false)
        // Failure keychain/usage должна попасть в usageError, а не в providerError.
        XCTAssertNil(status.usage)
        XCTAssertNotNil(status.usageError)
        XCTAssertFalse(status.providerError?.contains("usage") ?? true)
    }

    func test_fetchReportsOnlyStatsCacheErrorWhenAuthSucceeds() async {
        let authJSON = Data("""
        {"loggedIn": true}
        """.utf8)
        let provider = ClaudeLimitsProvider(
            claudeBinary: "/bin/does-not-matter",
            statsCacheURL: URL(fileURLWithPath: "/does/not/matter.json"),
            processRunner: { _, _ in authJSON },
            fileReader: { _ in throw StubError() },
            keychainReader: { throw StubError() },
            httpGet: { _, _ in throw StubError() }
        )
        let status = await provider.fetch()
        XCTAssertTrue(status.providerError?.hasPrefix("stats cache read failed") ?? false)
        XCTAssertFalse(status.providerError?.contains("claude auth status failed") ?? true)
        XCTAssertNotNil(status.usageError)
    }

    func test_fetchPopulatesUsageFromKeychainAndHttp() async throws {
        let authJSON = Data(#"{"loggedIn": true}"#.utf8)
        let credentialsJSON = Data("""
        {"claudeAiOauth":{"accessToken":"tok-abc","expiresAt":9999999999999},"organizationUuid":"x"}
        """.utf8)
        let usageJSON = Data("""
        {"five_hour":{"utilization":11.0,"resets_at":"2026-07-11T20:59:59.513044+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null},
         "seven_day":{"utilization":22.0,"resets_at":"2026-07-16T05:59:59.513065+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null}}
        """.utf8)
        var requestedURL: URL?
        var requestedBearer: String?
        let provider = ClaudeLimitsProvider(
            claudeBinary: "/bin/does-not-matter",
            statsCacheURL: URL(fileURLWithPath: "/does/not/matter.json"),
            processRunner: { _, _ in authJSON },
            fileReader: { _ in Data(#"{"version":1,"dailyActivity":[],"dailyModelTokens":[]}"#.utf8) },
            keychainReader: { credentialsJSON },
            httpGet: { url, bearer in
                requestedURL = url
                requestedBearer = bearer
                return usageJSON
            }
        )
        let status = await provider.fetch()
        XCTAssertNil(status.providerError)
        let usage = try XCTUnwrap(status.usage)
        let fiveHour = try XCTUnwrap(usage.fiveHour)
        let sevenDay = try XCTUnwrap(usage.sevenDay)
        XCTAssertEqual(fiveHour.utilizationPercent, 11.0, accuracy: 0.001)
        XCTAssertEqual(sevenDay.utilizationPercent, 22.0, accuracy: 0.001)
        XCTAssertNotNil(fiveHour.resetsAt)
        XCTAssertNotNil(sevenDay.resetsAt)
        XCTAssertEqual(requestedBearer, "tok-abc")
        XCTAssertEqual(requestedURL?.absoluteString, "https://claude.ai/api/oauth/usage")
        XCTAssertNil(status.usageError)
    }

    func test_usageErrorWhenTokenExpired() async {
        let authJSON = Data(#"{"loggedIn": true}"#.utf8)
        let expiredMS = Int64(Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000)
        let credentialsJSON = Data("""
        {"claudeAiOauth":{"accessToken":"tok-abc","expiresAt":\(expiredMS)}}
        """.utf8)
        var httpCalled = false
        let provider = ClaudeLimitsProvider(
            claudeBinary: "/bin/does-not-matter",
            statsCacheURL: URL(fileURLWithPath: "/does/not/matter.json"),
            processRunner: { _, _ in authJSON },
            fileReader: { _ in Data(#"{"version":1,"dailyActivity":[],"dailyModelTokens":[]}"#.utf8) },
            keychainReader: { credentialsJSON },
            httpGet: { _, _ in httpCalled = true; return Data() }
        )
        let status = await provider.fetch()
        XCTAssertNil(status.usage)
        XCTAssertTrue(status.usageError?.contains("expired") ?? false)
        XCTAssertFalse(httpCalled)
    }

    func test_usageErrorWhenKeychainMissing() async {
        let authJSON = Data(#"{"loggedIn": true}"#.utf8)
        let provider = ClaudeLimitsProvider(
            claudeBinary: "/bin/does-not-matter",
            statsCacheURL: URL(fileURLWithPath: "/does/not/matter.json"),
            processRunner: { _, _ in authJSON },
            fileReader: { _ in Data(#"{"version":1,"dailyActivity":[],"dailyModelTokens":[]}"#.utf8) },
            keychainReader: { throw StubError() },
            httpGet: { _, _ in throw StubError() }
        )
        let status = await provider.fetch()
        XCTAssertNil(status.usage)
        XCTAssertTrue(status.usageError?.contains("claude.ai") ?? false)
    }
}

final class ClaudeUsageParserTests: XCTestCase {
    func test_parsesFiveHourAndSevenDay() throws {
        let json = Data("""
        {"five_hour":{"utilization":11.0,"resets_at":"2026-07-11T20:59:59.513044+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null},
         "seven_day":{"utilization":22.0,"resets_at":"2026-07-16T05:59:59.513065+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null}}
        """.utf8)
        let usage = try XCTUnwrap(ClaudeUsageParser.parse(json))
        let fiveHour = try XCTUnwrap(usage.fiveHour)
        let sevenDay = try XCTUnwrap(usage.sevenDay)
        XCTAssertEqual(fiveHour.utilizationPercent, 11.0, accuracy: 0.001)
        XCTAssertEqual(sevenDay.utilizationPercent, 22.0, accuracy: 0.001)
        XCTAssertNotNil(fiveHour.resetsAt)
        XCTAssertNotNil(sevenDay.resetsAt)
        XCTAssertNil(fiveHour.limitDollars)
    }

    func test_handlesNullWindows() {
        let usage = ClaudeUsageParser.parse(Data(#"{"five_hour":null,"seven_day":null}"#.utf8))
        XCTAssertNotNil(usage)
        XCTAssertNil(usage?.fiveHour)
        XCTAssertNil(usage?.sevenDay)
    }

    func test_handlesEmptyObject() {
        let usage = ClaudeUsageParser.parse(Data("{}".utf8))
        XCTAssertNotNil(usage)
        XCTAssertNil(usage?.fiveHour)
        XCTAssertNil(usage?.sevenDay)
    }

    func test_returnsNilOnGarbage() {
        XCTAssertNil(ClaudeUsageParser.parse(Data("not-json".utf8)))
    }
}

final class ClaudeKeychainCredentialsParserTests: XCTestCase {
    func test_parsesAccessTokenAndExpiry() throws {
        let json = Data("""
        {"claudeAiOauth":{"accessToken":"tok-abc","expiresAt":1783798118577,"refreshToken":"r","scopes":[]},"organizationUuid":"x"}
        """.utf8)
        let creds = try XCTUnwrap(ClaudeKeychainCredentialsParser.accessToken(json))
        XCTAssertEqual(creds.token, "tok-abc")
        let expected = Date(timeIntervalSince1970: 1783798118577.0 / 1000.0)
        XCTAssertEqual(try XCTUnwrap(creds.expiresAt).timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_returnsNilWhenClaudeAiOauthMissing() {
        let json = Data(#"{"mcpOAuth":{"x":1},"organizationUuid":"x"}"#.utf8)
        XCTAssertNil(ClaudeKeychainCredentialsParser.accessToken(json))
    }

    func test_returnsNilOnGarbage() {
        XCTAssertNil(ClaudeKeychainCredentialsParser.accessToken(Data("not-json".utf8)))
    }
}

// MARK: - MenuBarDisplayModeTests

final class MenuBarDisplayModeTests: XCTestCase {
    private static let sentinel = Date(timeIntervalSince1970: 0)

    private func makeClaudeStatus(
        subscriptionType: String? = "max",
        usage: ClaudeUsage? = nil
    ) -> ClaudeStatus {
        ClaudeStatus(
            loggedIn: true,
            authMethod: nil,
            apiProvider: nil,
            email: nil,
            subscriptionType: subscriptionType,
            orgName: nil,
            today: nil,
            latestDay: nil,
            lastComputedDate: nil,
            totalSessions: nil,
            totalMessages: nil,
            usage: usage,
            usageError: nil,
            fetchedAt: Self.sentinel,
            providerError: nil
        )
    }

    private func makeCodexStatus(
        planType: String? = "plus",
        usage: CodexUsage? = nil
    ) -> CodexStatus {
        CodexStatus(
            loggedIn: true,
            authMode: nil,
            email: nil,
            planType: planType,
            subscriptionActiveUntil: nil,
            daysUntilRenewal: nil,
            accountOwner: nil,
            usage: usage,
            usageError: nil,
            fetchedAt: Self.sentinel,
            providerError: nil
        )
    }

    private func makeCodexUsage(primary: Double? = nil, secondary: Double? = nil) -> CodexUsage {
        let snapshot = CodexUsageSnapshot(
            primary: primary.map { CodexUsageWindow(usedPercent: $0, windowDurationMins: 300, resetsAt: nil) },
            secondary: secondary.map { CodexUsageWindow(usedPercent: $0, windowDurationMins: 10080, resetsAt: nil) },
            planType: "plus",
            creditsBalance: nil,
            rateLimitReachedType: nil
        )
        return CodexUsage(snapshot: snapshot, error: nil)
    }

    private func makeUsage(fiveHour: Double? = nil, sevenDay: Double? = nil) -> ClaudeUsage {
        ClaudeUsage(
            fiveHour: fiveHour.map { ClaudeUsageWindow(utilizationPercent: $0, resetsAt: nil,
                                                       limitDollars: nil, usedDollars: nil,
                                                       remainingDollars: nil) },
            sevenDay: sevenDay.map { ClaudeUsageWindow(utilizationPercent: $0, resetsAt: nil,
                                                       limitDollars: nil, usedDollars: nil,
                                                       remainingDollars: nil) }
        )
    }

    func test_iconAndText_showsPlanNames() {
        let claude = makeClaudeStatus()
        let codex = makeCodexStatus()
        XCTAssertEqual(MenuBarDisplayMode.iconAndText.menuBarText(claude: claude, codex: codex),
                       "Claude: Max · Codex: Plus")
    }

    func test_iconAnd5h_showsPercentRemaining() {
        let claude = makeClaudeStatus(usage: makeUsage(fiveHour: 22))
        let codex = makeCodexStatus()
        XCTAssertEqual(MenuBarDisplayMode.iconAnd5h.menuBarText(claude: claude, codex: codex),
                       "C 78% · X —")
    }

    func test_iconAnd5hWeekly_showsPercentAndWeekly() {
        let claude = makeClaudeStatus(usage: makeUsage(fiveHour: 22, sevenDay: 5))
        let codex = makeCodexStatus()
        XCTAssertEqual(MenuBarDisplayMode.iconAnd5hWeekly.menuBarText(claude: claude, codex: codex),
                       "C 5h 78% / 95% · X 5h — / —")
    }

    func test_iconOnly_returnsNil() {
        XCTAssertNil(MenuBarDisplayMode.iconOnly.menuBarText(claude: makeClaudeStatus(),
                                                             codex: makeCodexStatus()))
    }

    func test_claudeNil_showsDashes() {
        let codex = makeCodexStatus()
        XCTAssertEqual(MenuBarDisplayMode.iconAnd5h.menuBarText(claude: nil, codex: codex),
                       "C — · X —")
    }

    func test_fiveHourNil_showsDash() {
        let claude = makeClaudeStatus(usage: makeUsage(fiveHour: nil, sevenDay: 10))
        let codex = makeCodexStatus()
        XCTAssertEqual(MenuBarDisplayMode.iconAnd5h.menuBarText(claude: claude, codex: codex),
                       "C — · X —")
    }

    func test_codexPlanFallsBackToCodex() {
        let claude = makeClaudeStatus(subscriptionType: nil)
        let codex = makeCodexStatus(planType: nil)
        XCTAssertEqual(MenuBarDisplayMode.iconAndText.menuBarText(claude: claude, codex: codex),
                       "Claude: Claude · Codex: Codex")
    }

    func test_iconAnd5h_showsCodexPercentFromUsage() {
        let claude = makeClaudeStatus(usage: makeUsage(fiveHour: 22))
        let codex = makeCodexStatus(usage: makeCodexUsage(primary: 1))
        XCTAssertEqual(MenuBarDisplayMode.iconAnd5h.menuBarText(claude: claude, codex: codex),
                       "C 78% · X 99%")
    }

    func test_iconAnd5hWeekly_showsCodexWindowsFromUsage() {
        let claude = makeClaudeStatus(usage: makeUsage(fiveHour: 22, sevenDay: 5))
        let codex = makeCodexStatus(usage: makeCodexUsage(primary: 1, secondary: 18))
        XCTAssertEqual(MenuBarDisplayMode.iconAnd5hWeekly.menuBarText(claude: claude, codex: codex),
                       "C 5h 78% / 95% · X 5h 99% / 82%")
    }

    func test_iconAnd5hWeekly_weeklyInPrimary_showsWeeklyValueUnderWeeklySlot() {
        let weekly = CodexUsageWindow(usedPercent: 18, windowDurationMins: 10080, resetsAt: nil)
        let snapshot = CodexUsageSnapshot(
            primary: weekly, secondary: nil,
            planType: "plus", creditsBalance: nil, rateLimitReachedType: nil
        )
        let codex = makeCodexStatus(usage: CodexUsage(snapshot: snapshot, error: nil))
        let claude = makeClaudeStatus(usage: makeUsage(fiveHour: 22, sevenDay: 5))
        XCTAssertEqual(MenuBarDisplayMode.iconAnd5hWeekly.menuBarText(claude: claude, codex: codex),
                       "C 5h 78% / 95% · X 5h — / 82%")
    }

    func test_iconAnd5h_omits5hWhenNo300Window() {
        let weekly = CodexUsageWindow(usedPercent: 18, windowDurationMins: 10080, resetsAt: nil)
        let snapshot = CodexUsageSnapshot(
            primary: weekly, secondary: nil,
            planType: "plus", creditsBalance: nil, rateLimitReachedType: nil
        )
        let codex = makeCodexStatus(usage: CodexUsage(snapshot: snapshot, error: nil))
        let claude = makeClaudeStatus(usage: makeUsage(fiveHour: 22))
        XCTAssertEqual(MenuBarDisplayMode.iconAnd5h.menuBarText(claude: claude, codex: codex),
                       "C 78% · X —")
    }
}

final class CodexUsageParserTests: XCTestCase {
    private func envelope(_ resultJSON: String) -> Data {
        Data("{\"id\":2,\"result\":\(resultJSON)}".utf8)
    }

    func test_parsesFullSnapshotWithBothWindows() throws {
        let ok = envelope("""
        {"rateLimits":{"limitId":"codex","planType":"plus",
          "primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":1783816559},
          "secondary":{"usedPercent":18,"windowDurationMins":10080,"resetsAt":1784374937},
          "credits":{"hasCredits":false,"unlimited":false,"balance":"0"},
          "individualLimit":null,"rateLimitReachedType":null},
         "rateLimitsByLimitId":{},"rateLimitResetCredits":{"availableCount":0}}
        """)
        let snap = try XCTUnwrap(CodexUsageParser.parse(ok))
        XCTAssertEqual(snap.planType, "plus")
        let p = try XCTUnwrap(snap.primary)
        XCTAssertEqual(p.usedPercent, 1, accuracy: 0.001)
        XCTAssertEqual(p.windowDurationMins, 300)
        XCTAssertEqual(try XCTUnwrap(p.resetsAt).timeIntervalSince1970, 1783816559, accuracy: 0.001)
        let s = try XCTUnwrap(snap.secondary)
        XCTAssertEqual(s.usedPercent, 18, accuracy: 0.001)
        XCTAssertEqual(s.windowDurationMins, 10080)
        XCTAssertNil(snap.rateLimitReachedType)
    }

    func test_handlesNullWindows() {
        let ok = envelope("""
        {"rateLimits":{"primary":null,"secondary":null,"planType":"free",
          "credits":null,"rateLimitReachedType":null}}
        """)
        let snap = CodexUsageParser.parse(ok)
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.planType, "free")
        XCTAssertNil(snap?.primary)
        XCTAssertNil(snap?.secondary)
        XCTAssertNil(snap?.creditsBalance)
    }

    func test_rateLimitReachedTypeIsPassedThrough() throws {
        let ok = envelope("""
        {"rateLimits":{"primary":{"usedPercent":100,"windowDurationMins":300},
          "planType":"plus","rateLimitReachedType":"rate_limit_reached"}}
        """)
        let snap = try XCTUnwrap(CodexUsageParser.parse(ok))
        XCTAssertEqual(snap.rateLimitReachedType, "rate_limit_reached")
    }

    func test_returnsNilWhenRateLimitsIsNullOrNull() {
        XCTAssertNil(CodexUsageParser.parse(envelope(#"{"rateLimits":null}"#)))
        XCTAssertNil(CodexUsageParser.parse(envelope(#"{}"#)))
    }

    func test_returnsNilOnGarbage() {
        XCTAssertNil(CodexUsageParser.parse(Data("not-json".utf8)))
        XCTAssertNil(CodexUsageParser.parse(Data(#"{"id":2,"error":{"message":"x"}}"#.utf8)))
    }
}

final class CodexLimitsProviderTests: XCTestCase {
    private struct StubError: Error {}

    private func jwtPlanOnly(_ plan: String) -> String {
        let header = Data("{\"alg\":\"none\"}".utf8)
            .base64EncodedString().replacingOccurrences(of: "=", with: "")
        let body = Data("{\"https://api.openai.com/auth\":{\"chatgpt_plan_type\":\"\(plan)\"}}".utf8)
        let bodyB64 = body.base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "\(header).\(bodyB64).sig"
    }

    private func authFile(_ token: String?) -> Data {
        if let token {
            return Data(#"{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{"id_token":"\#(token)","access_token":null}}"#.utf8)
        }
        return Data(#"{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":null}"#.utf8)
    }

    func test_fetchPopulatesUsageFromAppServer() async throws {
        let rateLimitsEnvelope = Data("""
        {"id":2,"result":{"rateLimits":{"planType":"plus",
          "primary":{"usedPercent":5,"windowDurationMins":300,"resetsAt":1783816559},
          "secondary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1784374937},
          "credits":{"hasCredits":true,"unlimited":false,"balance":"3"},
          "individualLimit":null,"rateLimitReachedType":null},
          "rateLimitsByLimitId":{},"rateLimitResetCredits":{"availableCount":0}}}
        """.utf8)
        let provider = CodexLimitsProvider(
            authFileURL: URL(fileURLWithPath: "/does/not/matter.json"),
            fileReader: { _ in
                self.authFile(self.jwtPlanOnly("plus"))
            },
            appServerReader: { rateLimitsEnvelope }
        )
        let status = await provider.fetch()
        XCTAssertNil(status.providerError)
        XCTAssertTrue(status.loggedIn)
        let usage = try XCTUnwrap(status.usage)
        let snap = try XCTUnwrap(usage.snapshot)
        XCTAssertEqual(snap.planType, "plus")
        XCTAssertEqual(try XCTUnwrap(snap.primary).usedPercent, 5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snap.secondary).usedPercent, 42, accuracy: 0.001)
        XCTAssertEqual(snap.creditsBalance, "3")
        XCTAssertNil(status.usageError)
        // menuTitle использует planType из app-server.
        XCTAssertEqual(status.menuTitle, "Codex: Plus")
    }

    func test_usageErrorWhenAppServerThrows() async {
        let provider = CodexLimitsProvider(
            authFileURL: URL(fileURLWithPath: "/does/not/matter.json"),
            fileReader: { _ in
                self.authFile(self.jwtPlanOnly("plus"))
            },
            appServerReader: { throw StubError() }
        )
        let status = await provider.fetch()
        XCTAssertNil(status.providerError)
        XCTAssertTrue(status.loggedIn)
        XCTAssertNil(status.usage?.snapshot)
        XCTAssertNotNil(status.usageError)
        // JWT plan остаётся как fallback.
        XCTAssertEqual(status.menuTitle, "Codex: Plus")
    }

    func test_usageErrorWhenAppServerReturnsNullRateLimits() async {
        let envelope = Data("""
        {"id":2,"result":{"rateLimits":null,"rateLimitsByLimitId":{},"rateLimitResetCredits":{"availableCount":0}}}
        """.utf8)
        let provider = CodexLimitsProvider(
            authFileURL: URL(fileURLWithPath: "/does/not/matter.json"),
            fileReader: { _ in self.authFile(self.jwtPlanOnly("free")) },
            appServerReader: { envelope }
        )
        let status = await provider.fetch()
        XCTAssertNil(status.providerError)
        XCTAssertNil(status.usage?.snapshot)
        XCTAssertNotNil(status.usageError)
        XCTAssertEqual(status.menuTitle, "Codex: Free")
    }

    func test_providerErrorWhenAuthJSONMissing() async {
        let provider = CodexLimitsProvider(
            authFileURL: URL(fileURLWithPath: "/does/not/matter.json"),
            fileReader: { _ in throw StubError() },
            appServerReader: { Data(#"{"id":2,"result":{}}"#.utf8) }
        )
        let status = await provider.fetch()
        XCTAssertNotNil(status.providerError)
        XCTAssertFalse(status.loggedIn)
        XCTAssertNil(status.usage)
    }
}

final class DefaultCodexBinaryTests: XCTestCase {
    func test_prefersExplicitCodexBinEnv() {
        let path = ProcessRunner.defaultCodexBinary(
            environment: ["CODEX_BIN": "/custom/path/codex", "HOME": "/Users/test"],
            fileExists: { _ in false }
        )
        XCTAssertEqual(path, "/custom/path/codex")
    }

    func test_prefersLocalBinOverHomebrewWhenBothExist() {
        let path = ProcessRunner.defaultCodexBinary(
            environment: ["HOME": "/Users/test"],
            fileExists: { _ in true }
        )
        XCTAssertEqual(path, "/Users/test/.local/bin/codex")
    }

    func test_fallsBackToLastCandidateWhenNoneExist() {
        let path = ProcessRunner.defaultCodexBinary(
            environment: ["HOME": "/Users/test"],
            fileExists: { _ in false }
        )
        XCTAssertEqual(path, "/usr/local/bin/codex")
    }
}

final class CodexUsageSnapshotWindowLookupTests: XCTestCase {
    private func window(used: Double, duration: Int?, resetsAt: Date? = nil) -> CodexUsageWindow {
        CodexUsageWindow(usedPercent: used, windowDurationMins: duration, resetsAt: resetsAt)
    }

    func testFiveHourWindow_findsWindowByDuration300_regardlessOfPosition() {
        let fiveHour = window(used: 10, duration: 300)
        let weekly = window(used: 20, duration: 10080)
        let snapshot = CodexUsageSnapshot(
            primary: weekly, secondary: fiveHour,
            planType: nil, creditsBalance: nil, rateLimitReachedType: nil
        )
        XCTAssertEqual(snapshot.fiveHourWindow, fiveHour)
    }

    func testFiveHourWindow_returnsNil_whenNoWindowHas300Mins() {
        let weekly = window(used: 20, duration: 10080)
        let snapshot = CodexUsageSnapshot(
            primary: weekly, secondary: nil,
            planType: nil, creditsBalance: nil, rateLimitReachedType: nil
        )
        XCTAssertNil(snapshot.fiveHourWindow)
    }

    func testWeeklyWindow_findsWindowByDuration10080_inPrimarySlot() {
        let weekly = window(used: 20, duration: 10080)
        let snapshot = CodexUsageSnapshot(
            primary: weekly, secondary: nil,
            planType: nil, creditsBalance: nil, rateLimitReachedType: nil
        )
        XCTAssertEqual(snapshot.weeklyWindow, weekly)
    }

    func testRateLimitWindowLabel_300_is5h5h() {
        let labels = RateLimitWindowLabel.labels(forDurationMins: 300)
        XCTAssertEqual(labels.short, "5h")
        XCTAssertEqual(labels.long, "5h")
    }

    func testRateLimitWindowLabel_10080_isWkWeekly() {
        let labels = RateLimitWindowLabel.labels(forDurationMins: 10080)
        XCTAssertEqual(labels.short, "wk")
        XCTAssertEqual(labels.long, "Weekly")
    }

    func testRateLimitWindowLabel_unknownDuration_computesLabel() {
        let labels = RateLimitWindowLabel.labels(forDurationMins: 1440)
        XCTAssertEqual(labels.short, "24h")
    }

    func testRateLimitWindowLabel_nilDuration_returnsSensibleFallback() {
        let labels = RateLimitWindowLabel.labels(forDurationMins: nil)
        XCTAssertEqual(labels.short, "?")
        XCTAssertEqual(labels.long, "Unknown")
    }
}
