import Foundation

/// Общий декодер payload JWT (base64url, без проверки подписи) — используется
/// провайдерами, которым нужны только claims из токена (Kimi, Codex). Ранее
/// декод был продублирован в `KimiJwtPayloadParser` и `ChatGPTClaims.payload`
/// (см. bd mac-limits-tracker-6gk.7).
enum JwtPayloadDecoder {
    /// Декодирует второй сегмент (payload) в JSON-словарь. Требует минимум 2
    /// сегмента, а не ровно 3 — токен без подписи (`alg: none`) тоже валиден.
    static func decode(token: String) -> [String: Any]? {
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
