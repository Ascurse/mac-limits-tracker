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
