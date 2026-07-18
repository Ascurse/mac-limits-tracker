import Foundation

/// Форматирование остатков и ресетов лимитов — общее для меню-бара и десктоп-виджета.
public enum LimitsFormatting {
    /// utilization — использованная доля (0…100); осталось — разница.
    public static func claudeRemainingPercent(_ window: ClaudeUsageWindow) -> Double {
        max(0, 100 - window.utilizationPercent)
    }

    /// usedPercent — ИСПОЛЬЗОВАНО; остаётся = 100 − это (зеркало claudeRemainingPercent).
    public static func codexRemainingPercent(_ window: CodexUsageWindow) -> Double {
        max(0, 100 - window.usedPercent)
    }

    public static func claudeRemainingText(_ window: ClaudeUsageWindow) -> String {
        String(format: "%.0f%%", claudeRemainingPercent(window))
    }

    public static func codexRemainingText(_ window: CodexUsageWindow) -> String {
        String(format: "%.0f%%", codexRemainingPercent(window))
    }

    public static func resetText(resetsAt: Date?, relativeTo now: Date = Date()) -> String {
        guard let resetsAt else { return "—" }
        return relativeFormatter.localizedString(for: resetsAt, relativeTo: now)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
