import Foundation

/// Данные о лимитах Claude Code, собранные из локального состояния подписки и кеша статистики.
public struct ClaudeStatus: Equatable {
    public let loggedIn: Bool
    public let authMethod: String?
    public let apiProvider: String?
    public let email: String?
    public let subscriptionType: String?
    public let orgName: String?
    public let today: DayUsage?
    public let latestDay: DayUsage?
    public let lastComputedDate: String?
    public let totalSessions: Int?
    public let totalMessages: Int?
    /// Live-утилизация из `/api/oauth/usage`: 5-часовое окно и недельный лимит.
    public let usage: ClaudeUsage?
    /// Нефатальная ошибка получения usage (токен истёк / нет ключницы): попадает
    /// в секцию Claude отдельным рядом, не обнуляя всю секцию.
    public let usageError: String?
    public let fetchedAt: Date
    public let providerError: String?

    public struct DayUsage: Equatable {
        public let date: String
        public let messageCount: Int
        public let sessionCount: Int
        public let toolCallCount: Int
        public let tokens: Int
    }
}

extension ClaudeStatus {
    /// Удобный заголовок для меню: тип подписки или статус.
    public var menuTitle: String {
        if providerError != nil { return "Claude: ?" }
        guard loggedIn else { return "Claude: —" }
        if let sub = subscriptionType, !sub.isEmpty {
            return "Claude: \(sub.capitalized)"
        }
        return "Claude"
    }
}

/// Сырой JSON ответ `claude auth status`.
struct ClaudeAuthStatusJSON: Decodable {
    let loggedIn: Bool?
    let authMethod: String?
    let apiProvider: String?
    let email: String?
    let subscriptionType: String?
    let orgName: String?
}

struct ClaudeAuthStatus: Equatable {
    let loggedIn: Bool
    let authMethod: String?
    let apiProvider: String?
    let email: String?
    let subscriptionType: String?
    let orgName: String?
}

/// Чистый парсер stdin `claude auth status --json`.
enum ClaudeAuthParser {
    static func parse(_ data: Data) -> ClaudeAuthStatus {
        guard let json = try? JSONDecoder().decode(ClaudeAuthStatusJSON.self, from: data) else {
            return ClaudeAuthStatus(loggedIn: false, authMethod: nil, apiProvider: nil,
                                    email: nil, subscriptionType: nil, orgName: nil)
        }
        return ClaudeAuthStatus(
            loggedIn: json.loggedIn ?? false,
            authMethod: json.authMethod,
            apiProvider: json.apiProvider,
            email: json.email,
            subscriptionType: json.subscriptionType,
            orgName: json.orgName
        )
    }
}

/// Фрагмент `~/.claude/stats-cache.json`, нужный для показа «сегодня».
public struct StatsCache: Decodable, Equatable {
    public let version: Int?
    public let lastComputedDate: String?
    public let dailyActivity: [Day]
    public let dailyModelTokens: [DayTokens]
    public let totalSessions: Int?
    public let totalMessages: Int?

    public struct Day: Decodable, Equatable {
        public let date: String
        public let messageCount: Int
        public let sessionCount: Int
        public let toolCallCount: Int
    }

    public struct DayTokens: Decodable, Equatable {
        public let date: String
        public let tokensByModel: [String: Int]
    }
}

/// Одно окно утилизации из `/api/oauth/usage` (5h или недельное).
public struct ClaudeUsageWindow: Equatable {
    /// Доля использованного лимита, 0…100 (осталось = 100 − utilizationPercent).
    public let utilizationPercent: Double
    /// Когда окно обнулится.
    public let resetsAt: Date?
    public let limitDollars: Double?
    public let usedDollars: Double?
    public let remainingDollars: Double?
}

/// Live-утилизация лимитов Claude Code.
public struct ClaudeUsage: Equatable {
    public let fiveHour: ClaudeUsageWindow?
    public let sevenDay: ClaudeUsageWindow?
}

/// Сырой JSON ответа `GET https://claude.ai/api/oauth/usage`.
struct ClaudeUsageJSON: Decodable {
    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?
        let limitDollars: Double?
        let usedDollars: Double?
        let remainingDollars: Double?
    }
    let fiveHour: Window?
    let sevenDay: Window?
}

/// Чистый парсер ответа `/api/oauth/usage`.
enum ClaudeUsageParser {
    static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parse(_ data: Data) -> ClaudeUsage? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let json = try? decoder.decode(ClaudeUsageJSON.self, from: data) else { return nil }
        return ClaudeUsage(
            fiveHour: json.fiveHour.map(parseWindow),
            sevenDay: json.sevenDay.map(parseWindow)
        )
    }

    private static func parseWindow(_ w: ClaudeUsageJSON.Window) -> ClaudeUsageWindow {
        let resetsAt = w.resetsAt.flatMap { iso8601WithFractionalSeconds.date(from: $0) }
        return ClaudeUsageWindow(
            utilizationPercent: max(0, w.utilization ?? 0),
            resetsAt: resetsAt,
            limitDollars: w.limitDollars,
            usedDollars: w.usedDollars,
            remainingDollars: w.remainingDollars
        )
    }
}

/// Сырой JSON записи macOS Keychain `Claude Code-credentials`: нас интересует только `claudeAiOauth`.
struct ClaudeKeychainCredentialsJSON: Decodable {
    struct ClaudeAiOauth: Decodable {
        let accessToken: String
        let expiresAt: Int64?
    }
    let claudeAiOauth: ClaudeAiOauth?
}

/// Извлекает access-токен и срок его действия из ключичной записи Claude Code.
/// Сам токен не логируется и не персистится — только передаётся в HTTP-заголовок.
enum ClaudeKeychainCredentialsParser {
    static func accessToken(_ data: Data) -> (token: String, expiresAt: Date?)? {
        guard let json = try? JSONDecoder().decode(ClaudeKeychainCredentialsJSON.self, from: data),
              let oauth = json.claudeAiOauth else { return nil }
        let exp = oauth.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000.0) }
        return (oauth.accessToken, exp)
    }
}

/// Чистый выбор «сегодня» из кеша статистики, считает сумму токенов по моделям.
enum StatsCacheUsage {
    /// Claude Code пишет даты кеша статистики в America/Los_Angeles — сводим «сегодня» к тому же таймзону.
    static func laFormatter(calendar: Calendar = .current) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func todayUsage(from cache: StatsCache, on referenceDate: Date = Date(),
                           calendar: Calendar = .current) -> ClaudeStatus.DayUsage? {
        let todayKey = laFormatter(calendar: calendar).string(from: referenceDate)
        return usage(for: todayKey, in: cache)
    }

    static func latestUsage(from cache: StatsCache) -> ClaudeStatus.DayUsage? {
        guard let date = cache.dailyActivity.last?.date else { return nil }
        return usage(for: date, in: cache)
    }

    private static func usage(for dateKey: String, in cache: StatsCache) -> ClaudeStatus.DayUsage? {
        guard let day = cache.dailyActivity.first(where: { $0.date == dateKey }) else {
            return nil
        }
        let tokens = cache.dailyModelTokens
            .first(where: { $0.date == dateKey })?
            .tokensByModel.values.reduce(0, +) ?? 0
        return ClaudeStatus.DayUsage(
            date: day.date,
            messageCount: day.messageCount,
            sessionCount: day.sessionCount,
            toolCallCount: day.toolCallCount,
            tokens: tokens
        )
    }
}