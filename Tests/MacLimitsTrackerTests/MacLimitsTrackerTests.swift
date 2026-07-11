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

    func test_daysUntilRenewalFloorsAtZero() {
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

        let past = ChatGPTClaims(email: nil, planType: nil,
                                  subscriptionActiveUntil: now.addingTimeInterval(-86_400),
                                  accountOwner: nil)
        XCTAssertEqual(CodexClaimsParser.daysUntilRenewal(from: past,
                                                           referenceDate: now,
                                                           calendar: .current), 0)
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