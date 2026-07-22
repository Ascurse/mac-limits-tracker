import Foundation

/// Форматирование остатков и ресетов лимитов — общее для меню-бара и десктоп-виджета.
/// Общая для всех провайдеров: `usedPercent` — использованная доля (0…100),
/// осталось = разница (было раздельно `claudeRemainingPercent`/`codexRemainingPercent`).
public enum LimitsFormatting {
    public static func remainingPercent(usedPercent: Double) -> Double {
        max(0, 100 - usedPercent)
    }

    public static func remainingText(usedPercent: Double) -> String {
        String(format: "%.0f%%", remainingPercent(usedPercent: usedPercent))
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
