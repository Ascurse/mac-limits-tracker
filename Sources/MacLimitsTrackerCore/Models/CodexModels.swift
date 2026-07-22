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
    /// Live rate-limits через `codex app-server` JSON-RPC `account/rateLimits/read`.
    /// Нефатально: nil при недоступности app-server — секция не обнуляется, показывается usageError.
    public let usage: CodexUsage?
    public let usageError: String?
    public let fetchedAt: Date
    public let providerError: String?

    public var menuTitle: String {
        if providerError != nil { return "Codex: ?" }
        guard loggedIn else { return "Codex: —" }
        // Приоритет: app-server planType (актуальный) над JWT-claimом (может отстать при продлении).
        let plan = usage?.snapshot?.planType ?? planType
        if let p = plan, !p.isEmpty {
            return "Codex: \(p.capitalized)"
        }
        return "Codex"
    }
}

/// Одно окно rate-limit Codex. `usedPercent` — использовано (0…100);
/// осталось = `100 − usedPercent` (инверсия, как у ClaudeUsageWindow).
/// `primary` = 5h (`windowDurationMins: 300`), `secondary` = weekly (`10080`).
public struct CodexUsageWindow: Equatable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Date?
}

/// Live snapshot rate-limits Codex из app-server `account/rateLimits/read`.
public struct CodexUsageSnapshot: Equatable {
    public let primary: CodexUsageWindow?
    public let secondary: CodexUsageWindow?
    public let planType: String?
    public let creditsBalance: String?
    public let rateLimitReachedType: String?

    /// Окно 5h (300 минут) независимо от того, primary или secondary оно пришло.
    public var fiveHourWindow: CodexUsageWindow? {
        [primary, secondary].compactMap { $0 }.first { $0.windowDurationMins == 300 }
    }

    /// Окно weekly (10080 минут) независимо от позиции в ответе API.
    public var weeklyWindow: CodexUsageWindow? {
        [primary, secondary].compactMap { $0 }.first { $0.windowDurationMins == 10080 }
    }
}

/// Метки для окон rate-limit по длительности в минутах.
public enum RateLimitWindowLabel {
    public static func labels(forDurationMins minutes: Int?) -> (short: String, long: String) {
        guard let minutes = minutes else { return ("?", "Unknown") }
        switch minutes {
        case 300: return ("5h", "5h")
        case 10080: return ("wk", "Weekly")
        default: return (shortLabel(for: minutes), shortLabel(for: minutes))
        }
    }

    private static func shortLabel(for minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else if minutes % 60 == 0 {
            return "\(minutes / 60)h"
        } else {
            return "\(minutes / 60)h\(minutes % 60)m"
        }
    }
}

public struct CodexUsage: Equatable {
    public let snapshot: CodexUsageSnapshot?
    public let error: String?

    public init(snapshot: CodexUsageSnapshot? = nil, error: String? = nil) {
        self.snapshot = snapshot
        self.error = error
    }
}

/// Сырой JSON `result` ответа `account/rateLimits/read`. camelCase (без snake_case decoding).
struct CodexUsageResponseJSON: Decodable {
    struct Snapshot: Decodable {
        struct Window: Decodable {
            let usedPercent: Double?
            let windowDurationMins: Int?
            let resetsAt: Int64?
        }
        struct Credits: Decodable {
            let hasCredits: Bool?
            let unlimited: Bool?
            let balance: String?
        }
        let primary: Window?
        let secondary: Window?
        let planType: String?
        let credits: Credits?
        let rateLimitReachedType: String?
    }
    let rateLimits: Snapshot?
}

/// Принимает body JSON-RPC envelope `{"id":N,"result":{...}}`, достаёт `.result.rateLimits`.
enum CodexUsageParser {
    static func parse(_ data: Data) -> CodexUsageSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? [String: Any],
              let resultData = try? JSONSerialization.data(withJSONObject: result) else {
            return nil
        }
        let decoder = JSONDecoder()
        guard let resp = try? decoder.decode(CodexUsageResponseJSON.self, from: resultData),
              let snapshot = resp.rateLimits else {
            return nil
        }
        return CodexUsageSnapshot(
            primary: snapshot.primary.map(parseWindow),
            secondary: snapshot.secondary.map(parseWindow),
            planType: snapshot.planType,
            creditsBalance: snapshot.credits?.balance,
            rateLimitReachedType: snapshot.rateLimitReachedType
        )
    }

    private static func parseWindow(_ w: CodexUsageResponseJSON.Snapshot.Window) -> CodexUsageWindow {
        let resetsAt = w.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return CodexUsageWindow(
            usedPercent: max(0, w.usedPercent ?? 0),
            windowDurationMins: w.windowDurationMins,
            resetsAt: resetsAt
        )
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
        return comps.day.flatMap { $0 > 0 ? $0 : nil }
    }
}