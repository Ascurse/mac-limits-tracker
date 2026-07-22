import XCTest
@testable import MacLimitsTrackerCore

/// Тесты общего декодера payload JWT — вынесен из дублирующихся
/// KimiJwtPayloadParser и ChatGPTClaims.payload (bd mac-limits-tracker-6gk.7).
final class JwtPayloadDecodingTests: XCTestCase {
    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func jwt(payload: [String: Any]) -> String {
        let header = base64URLEncode(Data(#"{"alg":"none"}"#.utf8))
        let body = try! JSONSerialization.data(withJSONObject: payload)
        return "\(header).\(base64URLEncode(body)).sig"
    }

    func test_decodesValidPayloadMissingPadding() {
        // "plan" длиной 12 символов JSON-тела даёт base64 без штатного паддинга —
        // проверяем, что декодер сам его достраивает.
        let token = jwt(payload: ["plan": "kimi-pro"])
        let payload = JwtPayloadDecoder.decode(token: token)
        XCTAssertEqual(payload?["plan"] as? String, "kimi-pro")
    }

    func test_decodesTwoSegmentTokenWithoutSignature() {
        let header = base64URLEncode(Data(#"{"alg":"none"}"#.utf8))
        let body = base64URLEncode(try! JSONSerialization.data(withJSONObject: ["sub": "user-1"]))
        let token = "\(header).\(body)"
        let payload = JwtPayloadDecoder.decode(token: token)
        XCTAssertEqual(payload?["sub"] as? String, "user-1")
    }

    func test_invalidTokenWithoutDotsReturnsNil() {
        XCTAssertNil(JwtPayloadDecoder.decode(token: "not-a-jwt"))
    }

    func test_invalidBase64PayloadReturnsNil() {
        XCTAssertNil(JwtPayloadDecoder.decode(token: "h.!!!not-base64!!!.sig"))
    }

    func test_validBase64ButNotJsonReturnsNil() {
        let notJson = base64URLEncode(Data("plain text, not json".utf8))
        XCTAssertNil(JwtPayloadDecoder.decode(token: "h.\(notJson).sig"))
    }
}
