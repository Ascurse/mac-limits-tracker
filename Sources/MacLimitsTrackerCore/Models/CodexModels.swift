import Foundation

/// Данные о лимитах Codex, собранные из `~/.codex/auth.json` (декод JWT, без печати токенов).
public struct CodexStatus: Equatable {
    public let loggedIn: Bool
    public let authMode: String?
    public let email: String?
    public let planType: String?
    public let subscriptionActiveUntil: Date?
    public let daysUntilRenewal: Int?
    public let accountOwner: String?
    public let fetchedAt: Date
    public let providerError: String?

    public var menuTitle: String {
        if providerError != nil { return "Codex: ?" }
        guard loggedIn else { return "Codex: —" }
        if let plan = planType, !plan.isEmpty {
            return "Codex: \(plan.capitalized)"
        }
        return "Codex"
    }
}

/// Сырой `~/.codex/auth.json`.
struct CodexAuthFileJSON: Decodable {
    let authMode: String?
    let OPENAI_API_KEY: String?
    let tokens: Tokens?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case OPENAI_API_KEY
        case tokens
    }

    struct Tokens: Decodable {
        let idToken: String?
        let accessToken: String?

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case accessToken = "access_token"
        }
    }
}

/// Заявки (claims) из JWT ChatGPT (без проверки подписи — только для чтения публичных метаданных).
struct ChatGPTClaims: Equatable {
    let email: String?
    let planType: String?
    let subscriptionActiveUntil: Date?
    let accountOwner: String?

    /// Извлекает payload JWT как JSON-словарь. Не проверяет подпись — заявки только читаются.
    static func payload(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var body = String(parts[1])
        body = body.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - body.count % 4) % 4
        body += String(repeating: "=", count: pad)
        guard let data = Data(base64Encoded: body),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }
}

/// Разбирает payload claims с учётом поля `https://api.openai.com/auth` (вложенный объект).
enum CodexClaimsParser {
    static let authClaimKey = "https://api.openai.com/auth"

    static func parse(_ token: String) -> ChatGPTClaims {
        guard let payload = ChatGPTClaims.payload(of: token) else {
            return ChatGPTClaims(email: nil, planType: nil,
                                 subscriptionActiveUntil: nil, accountOwner: nil)
        }
        let auth = payload[authClaimKey] as? [String: Any]

        let plan = (auth?["chatgpt_plan_type"] as? String)
            ?? (payload["chatgpt_plan_type"] as? String)
        let email = (payload["email"] as? String)
            ?? (auth?["email"] as? String)
        let owner: String? = {
            if let orgs = auth?["organizations"] as? [[String: Any]],
               let first = orgs.first,
               let title = first["title"] as? String {
                return title
            }
            return nil
        }()
        let until: Date? = {
            let raw = (auth?["chatgpt_subscription_active_until"] as? String)
                ?? (payload["chatgpt_subscription_active_until"] as? String)
            guard let raw else { return nil }
            return ISO8601DateFormatter().date(from: raw)
        }()
        return ChatGPTClaims(email: email, planType: plan,
                             subscriptionActiveUntil: until, accountOwner: owner)
    }

    /// Сколько дней до продления подписки (на основе `chatgpt_subscription_active_until`).
    static func daysUntilRenewal(from claims: ChatGPTClaims, referenceDate: Date = Date(),
                                 calendar: Calendar = .current) -> Int? {
        guard let until = claims.subscriptionActiveUntil else { return nil }
        let comps = calendar.dateComponents([.day], from: referenceDate, to: until)
        return comps.day.map { max(0, $0) }
    }
}