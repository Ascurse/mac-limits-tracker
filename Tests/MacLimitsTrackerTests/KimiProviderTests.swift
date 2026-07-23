import XCTest
@testable import MacLimitsTrackerCore

/// Синтетические JWT для тестов: header.payload.signature без подписи (нам важен только payload).
/// НИКОГДА не использовать реальные токены — только тестовые данные.
private func makeJwt(payload: [String: Any]) -> String {
    let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncodedNoPadding()
    let body = try! JSONSerialization.data(withJSONObject: payload)
    return "\(header).\(body.base64URLEncodedNoPadding()).sig"
}

private extension Data {
    func base64URLEncodedNoPadding() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

final class KimiJwtPayloadParserTests: XCTestCase {
    func test_planClaim_foundByKnownKey() {
        let token = makeJwt(payload: ["plan": "kimi-pro", "sub": "user-1"])
        XCTAssertEqual(KimiJwtPayloadParser.planClaim(fromToken: token), "kimi-pro")
    }

    func test_planClaim_noRecognizableClaim_returnsNil() {
        let token = makeJwt(payload: ["sub": "user-1", "exp": 123])
        XCTAssertNil(KimiJwtPayloadParser.planClaim(fromToken: token))
    }

    func test_planClaim_malformedToken_returnsNilWithoutThrowing() {
        XCTAssertNil(KimiJwtPayloadParser.planClaim(fromToken: "not-a-jwt"))
    }
}

final class KimiCredentialsFileTests: XCTestCase {
    func test_decodesSnakeCaseFields() throws {
        let json = Data("""
        {"access_token":"acc-tok","refresh_token":"ref-tok",
         "expires_at":1783798118,"token_type":"Bearer","scope":"read write"}
        """.utf8)
        let creds = try JSONDecoder().decode(KimiCredentialsFile.self, from: json)
        XCTAssertEqual(creds.accessToken, "acc-tok")
        XCTAssertEqual(creds.refreshToken, "ref-tok")
        XCTAssertEqual(creds.tokenType, "Bearer")
    }

    func test_emptyRefreshToken_decodesButIsEmpty() throws {
        let json = Data(#"{"access_token":"acc-tok","refresh_token":"","expires_at":1}"#.utf8)
        let creds = try JSONDecoder().decode(KimiCredentialsFile.self, from: json)
        XCTAssertTrue(creds.refreshToken.isEmpty)
    }
}

final class KimiLimitsProviderTests: XCTestCase {
    private struct StubError: Error {}

    private func credentialsJSON(accessToken: String, refreshToken: String) -> Data {
        Data("""
        {"access_token":"\(accessToken)","refresh_token":"\(refreshToken)",
         "expires_at":1,"token_type":"Bearer","scope":"read"}
        """.utf8)
    }

    /// Без стаба `httpGet` дефолт бьёт в реальную сеть — expiresAt=1 (в прошлом) гарантирует,
    /// что fetchUsage вернёт "login expired" без сетевого вызова (см. DI-тесты ниже на сам httpGet).
    func test_fetch_loggedInWithPlanClaim_populatesPlanAndUsageError() async {
        let token = makeJwt(payload: ["plan": "kimi-pro"])
        let provider = KimiLimitsProvider(
            credentialsURL: URL(fileURLWithPath: "/does/not/matter.json"),
            fileReader: { _ in self.credentialsJSON(accessToken: token, refreshToken: "refresh-1") }
        )
        let snapshot = await provider.fetch()
        XCTAssertTrue(snapshot.loggedIn)
        XCTAssertEqual(snapshot.plan, "kimi-pro")
        XCTAssertNil(snapshot.windows)
        XCTAssertNotNil(snapshot.usageError)
        XCTAssertNil(snapshot.providerError)
    }

    func test_fetch_loggedInWithoutPlanClaim_planIsNilNoError() async {
        let token = makeJwt(payload: ["sub": "user-1"])
        let provider = KimiLimitsProvider(
            credentialsURL: URL(fileURLWithPath: "/does/not/matter.json"),
            fileReader: { _ in self.credentialsJSON(accessToken: token, refreshToken: "refresh-1") }
        )
        let snapshot = await provider.fetch()
        XCTAssertTrue(snapshot.loggedIn)
        XCTAssertNil(snapshot.plan)
        XCTAssertNil(snapshot.providerError)
    }

    func test_fetch_emptyRefreshToken_notLoggedInWithProviderError() async {
        let provider = KimiLimitsProvider(
            credentialsURL: URL(fileURLWithPath: "/does/not/matter.json"),
            fileReader: { _ in self.credentialsJSON(accessToken: "acc", refreshToken: "") }
        )
        let snapshot = await provider.fetch()
        XCTAssertFalse(snapshot.loggedIn)
        XCTAssertNotNil(snapshot.providerError)
    }

    func test_fetch_credentialsFileMissing_notLoggedInWithProviderError() async {
        let provider = KimiLimitsProvider(
            credentialsURL: URL(fileURLWithPath: "/does/not/matter.json"),
            fileReader: { _ in throw StubError() }
        )
        let snapshot = await provider.fetch()
        XCTAssertFalse(snapshot.loggedIn)
        XCTAssertNotNil(snapshot.providerError)
        XCTAssertNil(snapshot.windows)
    }

    func test_descriptor_hasKimiIdentity() {
        let provider = KimiLimitsProvider()
        XCTAssertEqual(provider.descriptor.id, "kimi")
        XCTAssertEqual(provider.descriptor.displayName, "Kimi")
        XCTAssertEqual(provider.descriptor.menuBarSymbol, "K")
        XCTAssertNil(provider.descriptor.loginHelp)
    }
}

/// DI-тесты на реальный запрос usage через `httpGet` (bd mac-limits-tracker-6gk.8).
/// Сеть подменяется замыканием — в тестах никогда не ходим в реальный API.
final class KimiLimitsProviderUsageTests: XCTestCase {
    private struct StubError: Error {}

    private func credentialsJSON(expiresAt: Double) -> Data {
        Data("""
        {"access_token":"acc-tok","refresh_token":"ref-tok",
         "expires_at":\(expiresAt),"token_type":"Bearer","scope":"read"}
        """.utf8)
    }

    private let sampleUsagesJSON = Data("""
    {"user":{"membership":{"level":"LEVEL_INTERMEDIATE"}},
     "usage":{"limit":"100","used":"44","remaining":"56","resetTime":"2026-07-27T10:15:06Z"},
     "limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},
                "detail":{"limit":"100","remaining":"100","resetTime":"2026-07-23T08:15:06Z"}}],
     "parallel":{"limit":"20"},"totalQuota":{},"subType":"TYPE_PURCHASE"}
    """.utf8)

    func test_fetch_httpGetReturnsSample_snapshotHasWindowAndPlan() async {
        let futureExpiry = Date().addingTimeInterval(900).timeIntervalSince1970
        let provider = KimiLimitsProvider(
            credentialsURL: URL(fileURLWithPath: "/does/not/matter.json"),
            fileReader: { _ in self.credentialsJSON(expiresAt: futureExpiry) },
            httpGet: { _, _ in self.sampleUsagesJSON }
        )
        let snapshot = await provider.fetch()
        XCTAssertTrue(snapshot.loggedIn)
        XCTAssertEqual(snapshot.plan, "Intermediate")
        XCTAssertEqual(snapshot.windows, [
            SnapshotWindow(windowDurationMins: 300, usedPercent: 0,
                          resetsAt: ISO8601DateFormatter().date(from: "2026-07-23T08:15:06Z"))
        ])
        XCTAssertNil(snapshot.usageError)
    }

    func test_fetch_httpGetThrows401_expiredUsageErrorButStillLoggedIn() async {
        let futureExpiry = Date().addingTimeInterval(900).timeIntervalSince1970
        let provider = KimiLimitsProvider(
            credentialsURL: URL(fileURLWithPath: "/does/not/matter.json"),
            fileReader: { _ in self.credentialsJSON(expiresAt: futureExpiry) },
            httpGet: { _, _ in
                throw NSError(domain: "Network", code: 401,
                             userInfo: [NSLocalizedDescriptionKey: "HTTP 401"])
            }
        )
        let snapshot = await provider.fetch()
        XCTAssertTrue(snapshot.loggedIn)
        XCTAssertNil(snapshot.windows)
        XCTAssertEqual(snapshot.usageError, "Kimi login expired — open Kimi Code to refresh")
    }

    func test_fetch_httpGetThrowsNetworkError_usageErrorMentionsFailure() async {
        let futureExpiry = Date().addingTimeInterval(900).timeIntervalSince1970
        let provider = KimiLimitsProvider(
            credentialsURL: URL(fileURLWithPath: "/does/not/matter.json"),
            fileReader: { _ in self.credentialsJSON(expiresAt: futureExpiry) },
            httpGet: { _, _ in throw StubError() }
        )
        let snapshot = await provider.fetch()
        XCTAssertTrue(snapshot.loggedIn)
        XCTAssertNil(snapshot.windows)
        XCTAssertTrue(snapshot.usageError?.hasPrefix("Kimi usage fetch failed:") == true)
    }

    func test_fetch_expiresAtInPast_httpGetNeverCalled() async {
        var httpGetCalled = false
        let provider = KimiLimitsProvider(
            credentialsURL: URL(fileURLWithPath: "/does/not/matter.json"),
            fileReader: { _ in self.credentialsJSON(expiresAt: 1) },
            httpGet: { _, _ in
                httpGetCalled = true
                return self.sampleUsagesJSON
            }
        )
        let snapshot = await provider.fetch()
        XCTAssertFalse(httpGetCalled)
        XCTAssertEqual(snapshot.usageError, "Kimi login expired — open Kimi Code to refresh")
    }
}

final class KimiLimitsProviderAvailabilityTests: XCTestCase {
    private func tempCredentialsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kimi-test-\(UUID().uuidString).json")
    }

    func test_hasUsableCredentials_trueWhenFileExistsWithRefreshToken() throws {
        let url = tempCredentialsURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"access_token":"a","refresh_token":"r","expires_at":1}"#.utf8).write(to: url)
        XCTAssertTrue(KimiLimitsProvider.hasUsableCredentials(at: url))
    }

    func test_hasUsableCredentials_falseWhenFileMissing() {
        XCTAssertFalse(KimiLimitsProvider.hasUsableCredentials(at: tempCredentialsURL()))
    }

    func test_hasUsableCredentials_falseWhenRefreshTokenEmpty() throws {
        let url = tempCredentialsURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"access_token":"a","refresh_token":"","expires_at":1}"#.utf8).write(to: url)
        XCTAssertFalse(KimiLimitsProvider.hasUsableCredentials(at: url))
    }
}

final class ProviderRegistryKimiTests: XCTestCase {
    private func tempCredentialsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kimi-registry-test-\(UUID().uuidString).json")
    }

    func test_makeDefault_omitsKimiWhenCredentialsMissing() {
        let providers = ProviderRegistry.makeDefault(kimiCredentialsURL: tempCredentialsURL())
        XCTAssertFalse(providers.contains { $0.descriptor.id == "kimi" })
        XCTAssertEqual(providers.map(\.descriptor.id), ["claude", "codex"])
    }

    func test_makeDefault_includesKimiWhenCredentialsUsable() throws {
        let url = tempCredentialsURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"access_token":"a","refresh_token":"r","expires_at":1}"#.utf8).write(to: url)
        let providers = ProviderRegistry.makeDefault(kimiCredentialsURL: url)
        XCTAssertEqual(providers.map(\.descriptor.id), ["claude", "codex", "kimi"])
    }
}
