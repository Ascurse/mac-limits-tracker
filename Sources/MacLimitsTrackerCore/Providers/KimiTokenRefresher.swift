import Foundation

/// Обновляет Kimi access_token через `POST auth.kimi.com/api/oauth/token`,
/// атомарно перезаписывая `~/.kimi-code/credentials/kimi-code.json`.
struct KimiTokenRefresher {
    private static let sharedDecoder = JSONDecoder()
    static let tokenURL = URL(string: "https://auth.kimi.com/api/oauth/token")!
    static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
    static let defaultDeviceIDURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".kimi-code/device_id")

    let fileReader: (URL) async throws -> Data
    let httpPostForm: (
        URL, [String: String], [(String, String)]
    ) async throws -> (statusCode: Int, body: Data)
    let deviceIDReader: (URL) async throws -> String
    let now: () -> Date

    init(
        fileReader: @escaping (URL) async throws -> Data = { try Data(contentsOf: $0) },
        httpPostForm: @escaping (
            URL, [String: String], [(String, String)]
        ) async throws -> (statusCode: Int, body: Data) = Http.httpPostForm,
        deviceIDReader: @escaping (URL) async throws -> String = {
            try String(contentsOf: $0, encoding: .utf8)
        },
        now: @escaping () -> Date = { Date() }
    ) {
        self.fileReader = fileReader
        self.httpPostForm = httpPostForm
        self.deviceIDReader = deviceIDReader
        self.now = now
    }

    func refreshedCredentials(
        old: KimiCredentialsFile, credentialsURL: URL
    ) async throws -> KimiCredentialsFile {
        if let fresh = try await freshCredentialsFromFile(
            old: old, credentialsURL: credentialsURL
        ) {
            return fresh
        }

        let deviceID = try await readDeviceID()

        let (statusCode, body): (Int, Data)
        do {
            (statusCode, body) = try await httpPostForm(
                Self.tokenURL,
                ["Accept": "application/json", "X-Msh-Device-Id": deviceID],
                [
                    ("client_id", Self.clientID),
                    ("grant_type", "refresh_token"),
                    ("refresh_token", old.refreshToken)
                ]
            )
        } catch {
            throw KimiTokenRefreshError.refreshFailed("network error: \(friendly(error))")
        }

        switch statusCode {
        case 200:
            let response: KimiOAuthTokenResponse
            do {
                response = try Self.sharedDecoder.decode(
                    KimiOAuthTokenResponse.self, from: body
                )
            } catch {
                throw KimiTokenRefreshError.refreshFailed("unreadable response")
            }
            let newExpiresAt = now().timeIntervalSince1970 + TimeInterval(response.expiresIn)
            let newCreds = KimiCredentialsFile(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: newExpiresAt,
                tokenType: response.tokenType ?? old.tokenType,
                scope: response.scope ?? old.scope
            )
            try await atomicallyWrite(
                credentials: newCreds, expiresIn: response.expiresIn, to: credentialsURL
            )
            return newCreds
        case 401, 403:
            if let fresh = try await freshCredentialsFromFile(
                old: old, credentialsURL: credentialsURL
            ) {
                return fresh
            }
            throw KimiTokenRefreshError.loginExpired
        default:
            if isInvalidGrant(body) {
                if let fresh = try await freshCredentialsFromFile(
                    old: old, credentialsURL: credentialsURL
                ) {
                    return fresh
                }
                throw KimiTokenRefreshError.loginExpired
            }
            throw KimiTokenRefreshError.refreshFailed("HTTP \(statusCode)")
        }
    }

    private func freshCredentialsFromFile(
        old: KimiCredentialsFile, credentialsURL: URL
    ) async throws -> KimiCredentialsFile? {
        guard let data = try? await fileReader(credentialsURL),
              let file = try? Self.sharedDecoder.decode(KimiCredentialsFile.self, from: data),
              !file.refreshToken.isEmpty,
              file.accessToken != old.accessToken,
              let expiresAt = file.expiresAt,
              expiresAt > now().timeIntervalSince1970
        else { return nil }
        return file
    }

    private func readDeviceID() async throws -> String {
        let raw: String
        do {
            raw = try await deviceIDReader(Self.defaultDeviceIDURL)
        } catch {
            throw KimiTokenRefreshError.refreshFailed("device_id unreadable")
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KimiTokenRefreshError.refreshFailed("device_id unreadable")
        }
        return trimmed
    }

    private func isInvalidGrant(_ body: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return false }
        return json["error"] as? String == "invalid_grant"
    }

    private func atomicallyWrite(
        credentials: KimiCredentialsFile, expiresIn: Int, to credentialsURL: URL
    ) async throws {
        let data: Data
        do {
            let raw = try await fileReader(credentialsURL)
            var dict = (try JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? [:]
            dict["access_token"] = credentials.accessToken
            dict["refresh_token"] = credentials.refreshToken
            dict["expires_at"] = credentials.expiresAt
            dict["expires_in"] = expiresIn
            if let tokenType = credentials.tokenType { dict["token_type"] = tokenType }
            if let scope = credentials.scope { dict["scope"] = scope }
            data = try JSONSerialization.data(withJSONObject: dict)
        } catch {
            var dict: [String: Any] = [
                "access_token": credentials.accessToken,
                "refresh_token": credentials.refreshToken,
                "expires_at": credentials.expiresAt as Any,
                "expires_in": expiresIn
            ]
            if let tokenType = credentials.tokenType { dict["token_type"] = tokenType }
            if let scope = credentials.scope { dict["scope"] = scope }
            data = try JSONSerialization.data(withJSONObject: dict)
        }

        let dir = credentialsURL.deletingLastPathComponent()
        let tmpURL = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            let created = FileManager.default.createFile(
                atPath: tmpURL.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            )
            guard created else {
                throw KimiTokenRefreshError.refreshFailed("write failed: createFile returned false")
            }
            _ = try FileManager.default.replaceItemAt(credentialsURL, withItemAt: tmpURL)
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            throw KimiTokenRefreshError.refreshFailed("write failed: \(friendly(error))")
        }
    }
}

enum KimiTokenRefreshError: Error, Equatable {
    case loginExpired
    case refreshFailed(String)
}
