import XCTest
@testable import MacLimitsTrackerCore

final class CodexModelsTests: XCTestCase {

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

    func test_payloadOf_returnsDictionaryForValidJWT() {
        let expectedPayload: [String: Any] = ["email": "test@example.com", "chatgpt_plan_type": "plus"]
        let token = jwt(payload: expectedPayload)

        let decoded = ChatGPTClaims.payload(of: token)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?["email"] as? String, "test@example.com")
        XCTAssertEqual(decoded?["chatgpt_plan_type"] as? String, "plus")
    }

    func test_payloadOf_returnsNilForInvalidTokenFormat() {
        XCTAssertNil(ChatGPTClaims.payload(of: "invalid_token_without_dots"))
        XCTAssertNil(ChatGPTClaims.payload(of: "header.not_base64_body.sig"))
    }

    func test_payloadOf_returnsNilForValidBase64ButNotJSON() {
        let header = base64URLEncode(Data(#"{"alg":"none"}"#.utf8))
        let body = base64URLEncode(Data("just a string".utf8))
        let token = "\(header).\(body).sig"

        XCTAssertNil(ChatGPTClaims.payload(of: token))
    }
}
