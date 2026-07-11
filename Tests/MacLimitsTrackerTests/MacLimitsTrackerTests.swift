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
            fileReader: { _ in throw StubError() }
        )
        let status = await provider.fetch()
        XCTAssertTrue(status.providerError?.contains("claude auth status failed") ?? false)
        XCTAssertTrue(status.providerError?.contains("stats cache read failed") ?? false)
    }

    func test_fetchReportsOnlyStatsCacheErrorWhenAuthSucceeds() async {
        let authJSON = Data("""
        {"loggedIn": true}
        """.utf8)
        let provider = ClaudeLimitsProvider(
            claudeBinary: "/bin/does-not-matter",
            statsCacheURL: URL(fileURLWithPath: "/does/not/matter.json"),
            processRunner: { _, _ in authJSON },
            fileReader: { _ in throw StubError() }
        )
        let status = await provider.fetch()
        XCTAssertTrue(status.providerError?.hasPrefix("stats cache read failed") ?? false)
        XCTAssertFalse(status.providerError?.contains("claude auth status failed") ?? true)
    }
}