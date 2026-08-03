import XCTest
@testable import MacLimitsTrackerCore

/// Тесты политики отображения ошибок провайдеров: каждый известный вид ошибки
/// мапится в безопасный copy + действие; неизвестная — в generic fallback.
final class ProviderErrorRecoveryTests: XCTestCase {
    private let descriptor = ProviderDescriptor(
        id: "test", displayName: "Test Provider", shortName: "Test",
        menuBarSymbol: "T", accentColorHex: 0, loginHelp: nil
    )

    private func claude(_ s: String) -> String { "claude" }
    private func codex(_ s: String) -> String { "codex" }
    private func kimi(_ s: String) -> String { "kimi" }

    // MARK: - Classification

    func test_claudeAuthStatusFailed_classifiesAsBinaryUnreachable() {
        let e = classify("claude auth status failed: The file “claude” doesn’t exist.")
        XCTAssertEqual(e, .claudeBinaryUnreachable)
    }

    func test_claudeStatsCacheReadFailed_classifiesAsStatsCacheUnreadable() {
        let e = classify("stats cache read failed: file not found")
        XCTAssertEqual(e, .claudeStatsCacheUnreadable)
    }

    func test_claudeOAuthTokenNotFound_classifies() {
        let e = classify("claude.ai oauth token not found")
        XCTAssertEqual(e, .claudeOAuthTokenMissing)
    }

    func test_claudeLoginExpired_classifies() {
        let e = classify("claude.ai login expired — open Claude Code to refresh")
        XCTAssertEqual(e, .claudeLoginExpired)
    }

    func test_claudeUsageResponseUnreadable_classifies() {
        let e = classify("claude.ai usage response unreadable")
        XCTAssertEqual(e, .claudeUsageResponseUnreadable)
    }

    func test_claudeUsageFetchFailed_classifies() {
        let e = classify("claude.ai usage fetch failed: The request timed out.")
        XCTAssertEqual(e, .claudeUsageFetchFailed)
    }

    func test_codexAuthFileReadFailed_classifies() {
        let e = classify("auth.json read failed: file not found")
        XCTAssertEqual(e, .codexAuthFileUnreadable)
    }

    func test_codexAuthTokensMissing_classifies() {
        let e = classify("auth.json has no ChatGPT tokens")
        XCTAssertEqual(e, .codexAuthTokensMissing)
    }

    func test_codexUsageResponseUnreadable_classifies() {
        let e = classify("codex usage response unreadable")
        XCTAssertEqual(e, .codexUsageResponseUnreadable)
    }

    func test_codexAppServerFailed_classifies() {
        let e = classify("codex app-server: The operation couldn’t be completed. (MacLimitsTrackerCore.CodexAppServerRpc.Error error 1.)")
        XCTAssertEqual(e, .codexAppServerUnavailable)
    }

    func test_kimiCredentialsReadFailed_classifies() {
        let e = classify("kimi-code credentials read failed: file not found")
        XCTAssertEqual(e, .kimiCredentialsUnreadable)
    }

    func test_kimiRefreshTokenMissing_classifies() {
        let e = classify("kimi-code refresh token missing")
        XCTAssertEqual(e, .kimiRefreshTokenMissing)
    }

    func test_kimiLoginExpired_classifies() {
        let e = classify("Kimi login expired — open Kimi Code to refresh")
        XCTAssertEqual(e, .kimiLoginExpired)
    }

    func test_kimiTokenRefreshFailed_classifies() {
        let e = classify("Kimi token refresh failed: network unreachable")
        XCTAssertEqual(e, .kimiTokenRefreshFailed)
    }

    func test_kimiUsageResponseUnreadable_classifies() {
        let e = classify("Kimi usage response unreadable")
        XCTAssertEqual(e, .kimiUsageResponseUnreadable)
    }

    func test_kimiUsageFetchFailed_classifies() {
        let e = classify("Kimi usage fetch failed: HTTP 503")
        XCTAssertEqual(e, .kimiUsageFetchFailed)
    }

    func test_unknownError_classifiesAsUnknown() {
        let raw = "something completely unexpected happened"
        let e = classify(raw)
        XCTAssertEqual(e, .unknown(raw))
    }

    // MARK: - Recovery content

    func test_claudeBinaryUnreachable_recovery() {
        let r = recover("claude auth status failed: file not found", providerName: "Claude Code")
        XCTAssertEqual(r.action, .openProviderCLI)
        XCTAssertEqual(r.primaryText, "Claude Code is not reachable — open Claude Code to refresh")
        XCTAssertTrue(r.diagnostic.contains("claude auth status failed"))
    }

    func test_claudeStatsCacheUnreadable_recovery() {
        let r = recover("stats cache read failed: file not found", providerName: "Claude Code")
        XCTAssertEqual(r.action, .openProviderCLI)
        XCTAssertEqual(r.primaryText, "Claude stats cache unavailable — open Claude Code to refresh")
    }

    func test_claudeOAuthTokenMissing_recovery() {
        let r = recover("claude.ai oauth token not found", providerName: "Claude Code")
        XCTAssertEqual(r.action, .openProviderCLI)
        XCTAssertEqual(r.primaryText, "Claude.ai login not found — open Claude Code to refresh")
    }

    func test_claudeLoginExpired_recovery() {
        let r = recover("claude.ai login expired — open Claude Code to refresh", providerName: "Claude Code")
        XCTAssertEqual(r.action, .openProviderCLI)
        XCTAssertEqual(r.primaryText, "Claude.ai login expired — open Claude Code to refresh")
    }

    func test_claudeUsageResponseUnreadable_recovery() {
        let r = recover("claude.ai usage response unreadable", providerName: "Claude Code")
        XCTAssertEqual(r.action, .retry)
        XCTAssertEqual(r.primaryText, "Claude.ai response unreadable — retry")
    }

    func test_claudeUsageFetchFailed_recovery() {
        let r = recover("claude.ai usage fetch failed: connection lost", providerName: "Claude Code")
        XCTAssertEqual(r.action, .retry)
        XCTAssertEqual(r.primaryText, "Claude.ai connection failed — retry")
    }

    func test_codexAuthFileUnreadable_recovery() {
        let r = recover("auth.json read failed: file not found", providerName: "Codex")
        XCTAssertEqual(r.action, .openProviderCLI)
        XCTAssertEqual(r.primaryText, "Codex auth file unreadable — open Codex to refresh")
    }

    func test_codexAuthTokensMissing_recovery() {
        let r = recover("auth.json has no ChatGPT tokens", providerName: "Codex")
        XCTAssertEqual(r.action, .openProviderCLI)
        XCTAssertEqual(r.primaryText, "Codex not logged in — open Codex to refresh")
    }

    func test_codexUsageResponseUnreadable_recovery() {
        let r = recover("codex usage response unreadable", providerName: "Codex")
        XCTAssertEqual(r.action, .retry)
        XCTAssertEqual(r.primaryText, "Codex response unreadable — retry")
    }

    func test_codexAppServerUnavailable_recovery() {
        let r = recover("codex app-server: spawn failed", providerName: "Codex")
        XCTAssertEqual(r.action, .retry)
        XCTAssertEqual(r.primaryText, "Codex app-server unavailable — retry")
    }

    func test_kimiCredentialsUnreadable_recovery() {
        let r = recover("kimi-code credentials read failed: file not found", providerName: "Kimi")
        XCTAssertEqual(r.action, .openProviderCLI)
        XCTAssertEqual(r.primaryText, "Kimi credentials unreadable — open Kimi Code to refresh")
    }

    func test_kimiRefreshTokenMissing_recovery() {
        let r = recover("kimi-code refresh token missing", providerName: "Kimi")
        XCTAssertEqual(r.action, .openProviderCLI)
        XCTAssertEqual(r.primaryText, "Kimi not logged in — open Kimi Code to refresh")
    }

    func test_kimiLoginExpired_recovery() {
        let r = recover("Kimi login expired — open Kimi Code to refresh", providerName: "Kimi")
        XCTAssertEqual(r.action, .openProviderCLI)
        XCTAssertEqual(r.primaryText, "Kimi login expired — open Kimi Code to refresh")
    }

    func test_kimiTokenRefreshFailed_recovery() {
        let r = recover("Kimi token refresh failed: invalid_grant", providerName: "Kimi")
        XCTAssertEqual(r.action, .retry)
        XCTAssertEqual(r.primaryText, "Kimi token refresh failed — retry")
    }

    func test_kimiUsageResponseUnreadable_recovery() {
        let r = recover("Kimi usage response unreadable", providerName: "Kimi")
        XCTAssertEqual(r.action, .retry)
        XCTAssertEqual(r.primaryText, "Kimi response unreadable — retry")
    }

    func test_kimiUsageFetchFailed_recovery() {
        let r = recover("Kimi usage fetch failed: HTTP 503", providerName: "Kimi")
        XCTAssertEqual(r.action, .retry)
        XCTAssertEqual(r.primaryText, "Kimi connection failed — retry")
    }

    func test_unknownError_recoveryIsGenericFallback() {
        let raw = "exploded: secret-token=abc123 path=/Users/x"
        let r = recover(raw, providerName: "Codex")
        XCTAssertEqual(r.action, .retry)
        XCTAssertEqual(r.primaryText, "Codex error — retry")
        XCTAssertFalse(r.primaryText.contains("secret-token"))
        XCTAssertFalse(r.primaryText.contains("/Users"))
        XCTAssertEqual(r.diagnostic, raw)
    }

    // MARK: - PopupContentBuilder integration

    func test_builder_mapsKnownProviderErrorToRecoveryRow() {
        let descriptor = ProviderDescriptor(
            id: "codex", displayName: "Codex", shortName: "Codex",
            menuBarSymbol: "X", accentColorHex: 0, loginHelp: nil
        )
        let snapshot = LimitsSnapshot(
            loggedIn: true, plan: nil, windows: nil,
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil,
            usageError: nil,
            providerError: "codex app-server: The operation couldn’t be completed.",
            fetchedAt: Date()
        )
        let state = ProviderState(descriptor: descriptor, snapshot: snapshot)
        let section = PopupContentBuilder.section(state)

        XCTAssertEqual(section.rows.count, 1)
        guard case .recovery(let content) = section.rows[0] else {
            return XCTFail("expected .recovery row, got \(section.rows)")
        }
        XCTAssertEqual(content.primaryText, "Codex app-server unavailable — retry")
        XCTAssertEqual(content.action, .retry)
        XCTAssertTrue(content.diagnostic.contains("codex app-server"))
    }

    func test_builder_mapsUnknownProviderErrorToGenericRecovery() {
        let descriptor = ProviderDescriptor(
            id: "claude", displayName: "Claude Code", shortName: "Claude",
            menuBarSymbol: "C", accentColorHex: 0, loginHelp: nil
        )
        let snapshot = LimitsSnapshot(
            loggedIn: true, plan: nil, windows: nil,
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil,
            usageError: nil, providerError: "boom",
            fetchedAt: Date()
        )
        let state = ProviderState(descriptor: descriptor, snapshot: snapshot)
        let section = PopupContentBuilder.section(state)

        guard case .recovery(let content) = section.rows[0] else {
            return XCTFail("expected .recovery row, got \(section.rows)")
        }
        XCTAssertEqual(content.primaryText, "Claude Code error — retry")
        XCTAssertEqual(content.action, .retry)
        XCTAssertEqual(content.diagnostic, "boom")
    }

    // MARK: - Helpers

    private func classify(_ raw: String) -> KnownProviderError {
        ProviderErrorRecoveryMapper.classify(raw)
    }

    private func recover(_ raw: String, providerName: String) -> ProviderRecoveryContent {
        ProviderErrorRecoveryMapper.recover(rawError: raw, providerName: providerName)
    }
}
