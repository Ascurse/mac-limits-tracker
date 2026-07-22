import Foundation

/// Данные о лимитах Kimi (Moonshot AI), собранные из
/// `~/.kimi-code/credentials/kimi-code.json`. Внутренний DTO шага `fetch()` —
/// публично наружу уходит только `LimitsSnapshot` (см. `toSnapshot()`).
struct KimiStatus: Equatable {
    let loggedIn: Bool
    let plan: String?
    let usageError: String?
    let providerError: String?
    let fetchedAt: Date
}

/// Сырой `~/.kimi-code/credentials/kimi-code.json`. `access_token` живёт ~900с,
/// поэтому логин определяется по наличию непустого `refresh_token`, а не по
/// `expires_at` (см. bd mac-limits-tracker-6gk.3).
struct KimiCredentialsFile: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Double?
    let tokenType: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case tokenType = "token_type"
        case scope
    }
}

/// Читает payload JWT (без проверки подписи — нужны только claims для чтения).
/// Ищет claim, похожий на план/тариф, по списку известных имён; если payload
/// не парсится или знакомого claim нет — nil без ошибки (см. bd mac-limits-tracker-6gk.3).
enum KimiJwtPayloadParser {
    private static let planClaimKeys = [
        "plan", "plan_type", "planType", "subscription_plan", "subscriptionPlan", "tier"
    ]

    static func planClaim(fromToken token: String) -> String? {
        guard let payload = decodePayload(token) else { return nil }
        for key in planClaimKeys {
            if let value = payload[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func decodePayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2, let data = base64URLDecode(String(segments[1])) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - normalized.count % 4) % 4
        normalized += String(repeating: "=", count: padding)
        return Data(base64Encoded: normalized)
    }
}
