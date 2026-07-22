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
