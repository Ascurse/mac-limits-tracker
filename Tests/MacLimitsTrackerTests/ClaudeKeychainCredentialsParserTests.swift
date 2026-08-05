import XCTest
@testable import MacLimitsTrackerCore

final class ClaudeKeychainCredentialsParserTests: XCTestCase {

    func test_accessToken_validJsonWithExpiry_returnsTokenAndDate() {
        let jsonString = """
        {
            "claudeAiOauth": {
                "accessToken": "sk-ant-api03-test123",
                "expiresAt": 1718000000000
            }
        }
        """
        let data = jsonString.data(using: .utf8)!

        let result = ClaudeKeychainCredentialsParser.accessToken(data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.token, "sk-ant-api03-test123")
        XCTAssertEqual(result?.expiresAt, Date(timeIntervalSince1970: 1718000000.0))
    }

    func test_accessToken_validJsonMissingExpiry_returnsTokenAndNilDate() {
        let jsonString = """
        {
            "claudeAiOauth": {
                "accessToken": "sk-ant-api03-test456"
            }
        }
        """
        let data = jsonString.data(using: .utf8)!

        let result = ClaudeKeychainCredentialsParser.accessToken(data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.token, "sk-ant-api03-test456")
        XCTAssertNil(result?.expiresAt)
    }

    func test_accessToken_missingOauthObject_returnsNil() {
        let jsonString = """
        {
            "otherKey": "value"
        }
        """
        let data = jsonString.data(using: .utf8)!

        let result = ClaudeKeychainCredentialsParser.accessToken(data)

        XCTAssertNil(result)
    }

    func test_accessToken_invalidJson_returnsNil() {
        let jsonString = "not-a-json"
        let data = jsonString.data(using: .utf8)!

        let result = ClaudeKeychainCredentialsParser.accessToken(data)

        XCTAssertNil(result)
    }
}
