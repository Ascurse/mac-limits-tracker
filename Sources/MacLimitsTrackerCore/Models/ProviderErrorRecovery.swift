import Foundation

/// Действие, которое пользователь может предпринять для восстановления провайдера.
public enum ProviderRecoveryAction: Equatable, Sendable {
    /// Открыть CLI провайдера (см. `ProviderDescriptor.loginHelp`).
    case openProviderCLI
    /// Повторить обновление вручную (существующий путь refresh в UI).
    case retry
}

/// Безопасное, понятное пользователю описание ошибки провайдера с рекомендуемым действием.
/// Сырой диагностический текст отделён и доступен через help/accessibility.
public struct ProviderRecoveryContent: Equatable, Sendable {
    public let primaryText: String
    public let action: ProviderRecoveryAction
    public let diagnostic: String

    public init(primaryText: String, action: ProviderRecoveryAction, diagnostic: String) {
        self.primaryText = primaryText
        self.action = action
        self.diagnostic = diagnostic
    }
}

/// Известные виды ошибок провайдеров, которые мы умеем переводить в безопасный copy.
public enum KnownProviderError: Equatable, Sendable {
    // Claude
    case claudeBinaryUnreachable
    case claudeStatsCacheUnreadable
    case claudeOAuthTokenMissing
    case claudeLoginExpired
    case claudeUsageResponseUnreadable
    case claudeUsageFetchFailed

    // Codex
    case codexAuthFileUnreadable
    case codexAuthTokensMissing
    case codexUsageResponseUnreadable
    case codexAppServerUnavailable

    // Kimi
    case kimiCredentialsUnreadable
    case kimiRefreshTokenMissing
    case kimiLoginExpired
    case kimiTokenRefreshFailed
    case kimiUsageResponseUnreadable
    case kimiUsageFetchFailed

    case unknown(String)
}

/// Чистая политика: сырой текст ошибки → безопасный copy + действие + диагностика.
///
/// Все сравнения — по префиксу, т.к. сырые строки могут включать локализованные
/// технические детали (NSError.localizedDescription), которые не должны попадать
/// в пользовательский copy.
public enum ProviderErrorRecoveryMapper {
    public static func classify(_ rawError: String) -> KnownProviderError {
        // Claude
        if rawError.hasPrefix("claude auth status failed:") { return .claudeBinaryUnreachable }
        if rawError.hasPrefix("stats cache read failed:") { return .claudeStatsCacheUnreadable }
        if rawError == "claude.ai oauth token not found" { return .claudeOAuthTokenMissing }
        if rawError == "claude.ai login expired — open Claude Code to refresh" { return .claudeLoginExpired }
        if rawError == "claude.ai usage response unreadable" { return .claudeUsageResponseUnreadable }
        if rawError.hasPrefix("claude.ai usage fetch failed:") { return .claudeUsageFetchFailed }

        // Codex
        if rawError.hasPrefix("auth.json read failed:") { return .codexAuthFileUnreadable }
        if rawError == "auth.json has no ChatGPT tokens" { return .codexAuthTokensMissing }
        if rawError == "codex usage response unreadable" { return .codexUsageResponseUnreadable }
        if rawError.hasPrefix("codex app-server:") { return .codexAppServerUnavailable }

        // Kimi
        if rawError.hasPrefix("kimi-code credentials read failed:") { return .kimiCredentialsUnreadable }
        if rawError == "kimi-code refresh token missing" { return .kimiRefreshTokenMissing }
        if rawError == "Kimi login expired — open Kimi Code to refresh" { return .kimiLoginExpired }
        if rawError.hasPrefix("Kimi token refresh failed:") { return .kimiTokenRefreshFailed }
        if rawError == "Kimi usage response unreadable" { return .kimiUsageResponseUnreadable }
        if rawError.hasPrefix("Kimi usage fetch failed:") { return .kimiUsageFetchFailed }

        return .unknown(rawError)
    }

    public static func recovery(
        for error: KnownProviderError,
        rawError: String,
        providerName: String
    ) -> ProviderRecoveryContent {
        switch error {
        case .claudeBinaryUnreachable:
            return content("\(providerName) is not reachable — open Claude Code to refresh", .openProviderCLI, diagnostic: rawError)
        case .claudeStatsCacheUnreadable:
            return content("Claude stats cache unavailable — open Claude Code to refresh", .openProviderCLI, diagnostic: rawError)
        case .claudeOAuthTokenMissing:
            return content("Claude.ai login not found — open Claude Code to refresh", .openProviderCLI, diagnostic: rawError)
        case .claudeLoginExpired:
            return content("Claude.ai login expired — open Claude Code to refresh", .openProviderCLI, diagnostic: rawError)
        case .claudeUsageResponseUnreadable:
            return content("Claude.ai response unreadable — retry", .retry, diagnostic: rawError)
        case .claudeUsageFetchFailed:
            return content("Claude.ai connection failed — retry", .retry, diagnostic: rawError)

        case .codexAuthFileUnreadable:
            return content("Codex auth file unreadable — open Codex to refresh", .openProviderCLI, diagnostic: rawError)
        case .codexAuthTokensMissing:
            return content("Codex not logged in — open Codex to refresh", .openProviderCLI, diagnostic: rawError)
        case .codexUsageResponseUnreadable:
            return content("Codex response unreadable — retry", .retry, diagnostic: rawError)
        case .codexAppServerUnavailable:
            return content("Codex app-server unavailable — retry", .retry, diagnostic: rawError)

        case .kimiCredentialsUnreadable:
            return content("Kimi credentials unreadable — open Kimi Code to refresh", .openProviderCLI, diagnostic: rawError)
        case .kimiRefreshTokenMissing:
            return content("Kimi not logged in — open Kimi Code to refresh", .openProviderCLI, diagnostic: rawError)
        case .kimiLoginExpired:
            return content("Kimi login expired — open Kimi Code to refresh", .openProviderCLI, diagnostic: rawError)
        case .kimiTokenRefreshFailed:
            return content("Kimi token refresh failed — retry", .retry, diagnostic: rawError)
        case .kimiUsageResponseUnreadable:
            return content("Kimi response unreadable — retry", .retry, diagnostic: rawError)
        case .kimiUsageFetchFailed:
            return content("Kimi connection failed — retry", .retry, diagnostic: rawError)

        case .unknown(let diagnostic):
            return content("\(providerName) error — retry", .retry, diagnostic: diagnostic)
        }
    }

    public static func recover(rawError: String, providerName: String) -> ProviderRecoveryContent {
        return recovery(for: classify(rawError), rawError: rawError, providerName: providerName)
    }

    private static func content(
        _ primaryText: String,
        _ action: ProviderRecoveryAction,
        diagnostic: String
    ) -> ProviderRecoveryContent {
        ProviderRecoveryContent(
            primaryText: primaryText,
            action: action,
            diagnostic: diagnostic
        )
    }
}

