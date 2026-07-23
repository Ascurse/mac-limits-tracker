import Foundation

/// Данные о лимитах Kimi (Moonshot AI), собранные из
/// `~/.kimi-code/credentials/kimi-code.json` + `GET /coding/v1/usages`. Внутренний DTO
/// шага `fetch()` — публично наружу уходит только `LimitsSnapshot` (см. `toSnapshot()`).
struct KimiStatus: Equatable {
    let loggedIn: Bool
    let plan: String?
    /// Live usage-данные из `/coding/v1/usages`. nil — не удалось получить
    /// (нет токена/протух/сеть/401), причина — в `usageError`.
    let usage: KimiUsage?
    let usageError: String?
    let providerError: String?
    let fetchedAt: Date
}

/// Одно окно лимита из `limits[]` ответа `/coding/v1/usages`.
struct KimiUsageWindow: Equatable {
    let windowDurationMins: Int?
    let usedPercent: Double?
    let resetsAt: Date?
}

/// Верхнеуровневый `usage` (лимит/использовано/остаток) ответа `/coding/v1/usages`.
/// API не указывает период (`subType: TYPE_PURCHASE` — покупной пул, не календарное
/// окно), поэтому в снапшот идёт деталью, а не окном с придуманной длительностью.
struct KimiQuotaDetail: Equatable {
    let limit: Int?
    let used: Int?
    let remaining: Int?
    let resetsAt: Date?
}

/// Разобранный ответ `/coding/v1/usages`.
struct KimiUsage: Equatable {
    let windows: [KimiUsageWindow]
    let quota: KimiQuotaDetail?
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
        guard let payload = JwtPayloadDecoder.decode(token: token) else { return nil }
        for key in planClaimKeys {
            if let value = payload[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}

/// Сырой JSON `GET /coding/v1/usages`. `limit`/`used`/`remaining` приходят строками,
/// `window.duration` — числом; любое поле может отсутствовать — не должно валить парсинг.
struct KimiUsagesResponseJSON: Decodable {
    struct User: Decodable {
        struct Membership: Decodable {
            let level: String?
        }
        let membership: Membership?
    }
    struct Usage: Decodable {
        let limit: String?
        let used: String?
        let remaining: String?
        let resetTime: String?
    }
    struct Limit: Decodable {
        struct Window: Decodable {
            let duration: Int?
            let timeUnit: String?
        }
        struct Detail: Decodable {
            let limit: String?
            let remaining: String?
            let resetTime: String?
        }
        let window: Window?
        let detail: Detail?
    }

    let user: User?
    let usage: Usage?
    let limits: [Limit]?
}

/// Приводит `membership.level` ("LEVEL_INTERMEDIATE") к читаемому виду ("Intermediate").
enum KimiMembershipLevelFormatter {
    private static let levelPrefix = "LEVEL_"

    static func prettify(_ level: String) -> String? {
        let withoutPrefix = level.hasPrefix(levelPrefix) ? String(level.dropFirst(levelPrefix.count)) : level
        guard !withoutPrefix.isEmpty else { return nil }
        return withoutPrefix
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

/// Парсит `/coding/v1/usages` в `KimiUsage` + сырой `membership.level` (форматирование
/// плана — забота вызывающей стороны, тут только извлечение данных).
enum KimiUsagesParser {
    struct Parsed: Equatable {
        let usage: KimiUsage
        let membershipLevel: String?
    }

    static func parse(_ data: Data) -> Parsed? {
        guard let resp = try? JSONDecoder().decode(KimiUsagesResponseJSON.self, from: data) else {
            return nil
        }
        let windows = (resp.limits ?? [])
            .map(parseWindow)
            .sorted { ($0.windowDurationMins ?? Int.max) < ($1.windowDurationMins ?? Int.max) }
        let usage = KimiUsage(windows: windows, quota: resp.usage.map(parseQuota))
        return Parsed(usage: usage, membershipLevel: resp.user?.membership?.level)
    }

    private static func parseWindow(_ limit: KimiUsagesResponseJSON.Limit) -> KimiUsageWindow {
        let durationMins = windowDurationMins(duration: limit.window?.duration, timeUnit: limit.window?.timeUnit)
        let limitValue = limit.detail?.limit.flatMap(Int.init)
        let remainingValue = limit.detail?.remaining.flatMap(Int.init)
        return KimiUsageWindow(
            windowDurationMins: durationMins,
            usedPercent: usedPercent(limit: limitValue, remaining: remainingValue),
            resetsAt: limit.detail?.resetTime.flatMap(parseISO8601)
        )
    }

    private static func parseQuota(_ usage: KimiUsagesResponseJSON.Usage) -> KimiQuotaDetail {
        KimiQuotaDetail(
            limit: usage.limit.flatMap(Int.init),
            used: usage.used.flatMap(Int.init),
            remaining: usage.remaining.flatMap(Int.init),
            resetsAt: usage.resetTime.flatMap(parseISO8601)
        )
    }

    /// `timeUnit` неизвестен/`TIME_UNIT_MINUTE` — значение как есть (минуты уже).
    private static func windowDurationMins(duration: Int?, timeUnit: String?) -> Int? {
        guard let duration else { return nil }
        switch timeUnit {
        case "TIME_UNIT_HOUR": return duration * 60
        case "TIME_UNIT_DAY": return duration * 1440
        default: return duration
        }
    }

    private static func usedPercent(limit: Int?, remaining: Int?) -> Double? {
        guard let limit, limit > 0, let remaining else { return nil }
        return Double(limit - remaining) / Double(limit) * 100.0
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw)
    }
}
