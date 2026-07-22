import Foundation

/// Текстовая полоса прогресса темы Phosphor: `██████░░░░` (заполнено = остаток).
public enum AsciiBar {
    public static func render(remainingPercent: Double, width: Int = 14) -> String {
        let clamped = min(100, max(0, remainingPercent))
        let filled = Int((clamped / 100 * Double(width)).rounded())
        return String(repeating: "█", count: filled)
             + String(repeating: "░", count: width - filled)
    }
}
