import XCTest
@testable import MacLimitsTrackerCore

final class KimiOAuthTokenResponseTests: XCTestCase {
    func test_decodeFullPayload_allFieldsPresent() throws {
        let json = Data("""
        {"access_token":"a","refresh_token":"r","expires_in":900,"scope":"kimi-code","token_type":"Bearer"}
        """.utf8)
        let response = try JSONDecoder().decode(KimiOAuthTokenResponse.self, from: json)
        XCTAssertEqual(response.accessToken, "a")
        XCTAssertEqual(response.refreshToken, "r")
        XCTAssertEqual(response.expiresIn, 900)
        XCTAssertEqual(response.tokenType, "Bearer")
        XCTAssertEqual(response.scope, "kimi-code")
    }

    func test_decodeMinimalPayload_optionalFieldsAreNil() throws {
        let json = Data("""
        {"access_token":"a","refresh_token":"r","expires_in":900}
        """.utf8)
        let response = try JSONDecoder().decode(KimiOAuthTokenResponse.self, from: json)
        XCTAssertEqual(response.accessToken, "a")
        XCTAssertEqual(response.refreshToken, "r")
        XCTAssertEqual(response.expiresIn, 900)
        XCTAssertNil(response.tokenType)
        XCTAssertNil(response.scope)
    }
}

final class KimiTokenRefresherTests: XCTestCase {
    private struct StubError: Error {}

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kimi-refresher-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeCredentialsURL(in dir: URL) -> URL {
        dir.appendingPathComponent("kimi-code.json")
    }

    private func makeCredentialsFile(
        accessToken: String = "old-access",
        refreshToken: String = "old-refresh",
        expiresAt: Double = 100_000,
        tokenType: String? = "Bearer",
        scope: String? = "read",
        extra: [String: String] = [:]
    ) -> KimiCredentialsFile {
        KimiCredentialsFile(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            tokenType: tokenType,
            scope: scope
        )
    }

    private func credentialsData(
        accessToken: String = "old-access",
        refreshToken: String = "old-refresh",
        expiresAt: Double = 100_000,
        tokenType: String? = "Bearer",
        scope: String? = "read",
        extra: [String: String] = [:]
    ) -> Data {
        var dict: [String: Any] = [
            "access_token": accessToken,
            "refresh_token": refreshToken,
            "expires_at": expiresAt
        ]
        if let tokenType { dict["token_type"] = tokenType }
        if let scope { dict["scope"] = scope }
        for (k, v) in extra { dict[k] = v }
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    private func createFile0600(at url: URL, contents: Data) throws {
        FileManager.default.createFile(atPath: url.path, contents: contents, attributes: [.posixPermissions: 0o600])
    }

    private func posixPermissions(of url: URL) throws -> UInt16 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let value = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        return value & 0o777
    }

    private func jsonDict(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private let fixedNow = Date(timeIntervalSince1970: 1_000_000)

    func test_refresh_200_writesFileAtomicallyWith0600AndReturnsNewCreds() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let credentialsURL = makeCredentialsURL(in: dir)
        let deviceIDURL = dir.appendingPathComponent("device_id")
        try "  dev-id\n".write(to: deviceIDURL, atomically: true, encoding: .utf8)
        try createFile0600(at: credentialsURL, contents: credentialsData(extra: ["future_field": "x"]))

        let oldCreds = makeCredentialsFile()
        let response = Data("""
        {"access_token":"new-access","refresh_token":"new-refresh","expires_in":900,"token_type":"Bearer","scope":"kimi-code"}
        """.utf8)

        var httpCalls = 0
        let refresher = KimiTokenRefresher(
            fileReader: { try Data(contentsOf: $0) },
            httpPostForm: { _, _, _ in
                httpCalls += 1
                return (200, response)
            },
            deviceIDReader: { _ in try String(contentsOf: deviceIDURL, encoding: .utf8) },
            now: { self.fixedNow }
        )

        let newCreds = try await refresher.refreshedCredentials(old: oldCreds, credentialsURL: credentialsURL)

        XCTAssertEqual(newCreds.accessToken, "new-access")
        XCTAssertEqual(newCreds.refreshToken, "new-refresh")
        XCTAssertEqual(newCreds.tokenType, "Bearer")
        XCTAssertEqual(newCreds.scope, "kimi-code")
        XCTAssertEqual(newCreds.expiresAt ?? 0, fixedNow.timeIntervalSince1970 + 900, accuracy: 0.001)
        XCTAssertEqual(httpCalls, 1)

        let finalDict = try jsonDict(at: credentialsURL)
        XCTAssertEqual(finalDict["access_token"] as? String, "new-access")
        XCTAssertEqual(finalDict["refresh_token"] as? String, "new-refresh")
        XCTAssertEqual(finalDict["future_field"] as? String, "x")
        XCTAssertEqual(finalDict["expires_in"] as? Int, 900)
        let finalExpiresAt = finalDict["expires_at"] as? Double ?? 0
        XCTAssertEqual(finalExpiresAt, fixedNow.timeIntervalSince1970 + 900, accuracy: 0.001)
        XCTAssertEqual(try posixPermissions(of: credentialsURL), 0o600)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(leftovers.allSatisfy { !$0.contains(".tmp") }, "leftover tmp files: \(leftovers)")
    }

    func test_refresh_preRace_fileAlreadyFresh_skipsHttp() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let credentialsURL = makeCredentialsURL(in: dir)
        let freshCreds = makeCredentialsFile(accessToken: "fresh-access", expiresAt: fixedNow.timeIntervalSince1970 + 1000)
        try createFile0600(at: credentialsURL, contents: credentialsData(accessToken: "fresh-access", expiresAt: fixedNow.timeIntervalSince1970 + 1000))

        let oldCreds = makeCredentialsFile(accessToken: "old-access")
        let refresher = KimiTokenRefresher(
            fileReader: { try Data(contentsOf: $0) },
            httpPostForm: { _, _, _ in
                XCTFail("HTTP must not be called when pre-race check finds fresh creds")
                return (0, Data())
            },
            deviceIDReader: { _ in
                XCTFail("device_id must not be read when pre-race check finds fresh creds")
                return "id"
            },
            now: { self.fixedNow }
        )

        let result = try await refresher.refreshedCredentials(old: oldCreds, credentialsURL: credentialsURL)
        XCTAssertEqual(result.accessToken, freshCreds.accessToken)
        XCTAssertEqual(result.expiresAt, freshCreds.expiresAt)
    }

    func test_refresh_invalidGrant_fileUntouched_throwsLoginExpired() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let credentialsURL = makeCredentialsURL(in: dir)
        try createFile0600(at: credentialsURL, contents: credentialsData())
        let original = try Data(contentsOf: credentialsURL)
        let oldCreds = makeCredentialsFile()

        var httpCalls = 0
        let refresher = KimiTokenRefresher(
            fileReader: { try Data(contentsOf: $0) },
            httpPostForm: { _, _, _ in
                httpCalls += 1
                return (400, Data(#"{"error":"invalid_grant"}"#.utf8))
            },
            deviceIDReader: { _ in "dev-id" },
            now: { self.fixedNow }
        )

        var thrown: KimiTokenRefreshError?
        do {
            _ = try await refresher.refreshedCredentials(old: oldCreds, credentialsURL: credentialsURL)
            XCTFail("expected loginExpired")
        } catch {
            thrown = error as? KimiTokenRefreshError
        }
        XCTAssertEqual(thrown, .loginExpired)
        XCTAssertEqual(httpCalls, 1)
        XCTAssertEqual(try Data(contentsOf: credentialsURL), original)
    }

    func test_refresh_invalidGrant_butFileNowFresh_returnsFreshCreds() async throws {
        let credentialsURL = makeCredentialsURL(in: try tempDir())
        let oldCreds = makeCredentialsFile()
        let freshCreds = makeCredentialsFile(accessToken: "fresh-access", expiresAt: fixedNow.timeIntervalSince1970 + 1000)
        let freshData = credentialsData(accessToken: "fresh-access", expiresAt: fixedNow.timeIntervalSince1970 + 1000)
        let oldData = credentialsData()

        var readCount = 0
        var httpCalls = 0
        let refresher = KimiTokenRefresher(
            fileReader: { _ in
                readCount += 1
                return readCount == 1 ? oldData : freshData
            },
            httpPostForm: { _, _, _ in
                httpCalls += 1
                return (400, Data(#"{"error":"invalid_grant"}"#.utf8))
            },
            deviceIDReader: { _ in "dev-id" },
            now: { self.fixedNow }
        )

        let result = try await refresher.refreshedCredentials(old: oldCreds, credentialsURL: credentialsURL)
        XCTAssertEqual(result.accessToken, freshCreds.accessToken)
        XCTAssertEqual(result.expiresAt, freshCreds.expiresAt)
        XCTAssertEqual(readCount, 2)
        XCTAssertEqual(httpCalls, 1)
    }

    func test_refresh_503_throwsRefreshFailed_fileUntouched() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let credentialsURL = makeCredentialsURL(in: dir)
        try createFile0600(at: credentialsURL, contents: credentialsData())
        let original = try Data(contentsOf: credentialsURL)
        let oldCreds = makeCredentialsFile()

        let refresher = KimiTokenRefresher(
            fileReader: { try Data(contentsOf: $0) },
            httpPostForm: { _, _, _ in (503, Data("{}".utf8)) },
            deviceIDReader: { _ in "dev-id" },
            now: { self.fixedNow }
        )

        var thrown: KimiTokenRefreshError?
        do {
            _ = try await refresher.refreshedCredentials(old: oldCreds, credentialsURL: credentialsURL)
            XCTFail("expected refreshFailed")
        } catch {
            thrown = error as? KimiTokenRefreshError
        }
        XCTAssertEqual(thrown, .refreshFailed("HTTP 503"))
        XCTAssertEqual(try Data(contentsOf: credentialsURL), original)
    }

    func test_refresh_networkThrow_throwsRefreshFailed() async {
        let oldCreds = makeCredentialsFile()
        let credentialsURL = makeCredentialsURL(in: try! tempDir())
        let refresher = KimiTokenRefresher(
            fileReader: { _ in Data(#"{"access_token":"a","refresh_token":"r","expires_at":1}"#.utf8) },
            httpPostForm: { _, _, _ in throw URLError(.notConnectedToInternet) },
            deviceIDReader: { _ in "dev-id" },
            now: { self.fixedNow }
        )

        var thrown: KimiTokenRefreshError?
        do {
            _ = try await refresher.refreshedCredentials(old: oldCreds, credentialsURL: credentialsURL)
            XCTFail("expected refreshFailed")
        } catch {
            thrown = error as? KimiTokenRefreshError
        }
        XCTAssertNotNil(thrown)
        if case let .refreshFailed(msg) = thrown {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("expected .refreshFailed, got \(String(describing: thrown))")
        }
    }

    func test_refresh_missingDeviceId_throwsRefreshFailed() async {
        let oldCreds = makeCredentialsFile()
        let credentialsURL = makeCredentialsURL(in: try! tempDir())
        var httpCalled = false
        let refresher = KimiTokenRefresher(
            fileReader: { _ in Data(#"{"access_token":"a","refresh_token":"r","expires_at":1}"#.utf8) },
            httpPostForm: { _, _, _ in
                httpCalled = true
                return (200, Data())
            },
            deviceIDReader: { _ in throw StubError() },
            now: { self.fixedNow }
        )

        var thrown: KimiTokenRefreshError?
        do {
            _ = try await refresher.refreshedCredentials(old: oldCreds, credentialsURL: credentialsURL)
            XCTFail("expected refreshFailed")
        } catch {
            thrown = error as? KimiTokenRefreshError
        }
        XCTAssertEqual(thrown, .refreshFailed("device_id unreadable"))
        XCTAssertFalse(httpCalled)
    }

    func test_refresh_formBodyIsCorrectlyEncoded() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let credentialsURL = makeCredentialsURL(in: dir)
        let deviceIDURL = dir.appendingPathComponent("device_id")
        try "  dev-id\n".write(to: deviceIDURL, atomically: true, encoding: .utf8)
        try createFile0600(at: credentialsURL, contents: credentialsData())

        let oldCreds = makeCredentialsFile()
        var capturedURL: URL?
        var capturedHeaders: [String: String]?
        var capturedForm: [(String, String)]?
        var httpCalls = 0

        let refresher = KimiTokenRefresher(
            fileReader: { try Data(contentsOf: $0) },
            httpPostForm: { url, headers, form in
                capturedURL = url
                capturedHeaders = headers
                capturedForm = form
                httpCalls += 1
                return (503, Data("{}".utf8))
            },
            deviceIDReader: { _ in try String(contentsOf: deviceIDURL, encoding: .utf8) },
            now: { self.fixedNow }
        )

        _ = try? await refresher.refreshedCredentials(old: oldCreds, credentialsURL: credentialsURL)

        XCTAssertEqual(httpCalls, 1)
        XCTAssertEqual(capturedURL?.absoluteString, "https://auth.kimi.com/api/oauth/token")
        XCTAssertEqual(capturedHeaders?["X-Msh-Device-Id"], "dev-id")
        let formDict = Dictionary(uniqueKeysWithValues: capturedForm ?? [])
        XCTAssertEqual(formDict["client_id"], "17e5f671-d194-4dfb-9706-5516cb48c098")
        XCTAssertEqual(formDict["grant_type"], "refresh_token")
        XCTAssertEqual(formDict["refresh_token"], oldCreds.refreshToken)
    }
}
