import Foundation

/// Текстовая полоса прогресса темы Phosphor: `██████░░░░` (заполнено = остаток).
public enum AsciiBar {
    private static let empty: Character = "░"

    public static func render(remainingPercent: Double, width: Int = 14) -> String {
        render(remainingPercent: remainingPercent, severity: .normal, width: width)
    }

    /// Глиф заполнения зависит от severity: монохромной теме нужен нецветовой
    /// признак. Ряд «сплошное → плотное → разреженное» читается как убывание
    /// остатка; доля заполнения при этом одинакова для всех состояний.
    public static func render(remainingPercent: Double,
                              severity: Severity,
                              width: Int = 14) -> String {
        let clamped = min(100, max(0, remainingPercent))
        let filled = Int((clamped / 100 * Double(width)).rounded())
        return String(repeating: fillGlyph(severity), count: filled)
             + String(repeating: empty, count: width - filled)
    }

    private static func fillGlyph(_ severity: Severity) -> Character {
        switch severity {
        case .normal:   return "█"
        case .warning:  return "▓"
        case .critical: return "▒"
        }
    }
}

/// Мини-гистограмма (sparkline) темы Terminal/Phosphor: `▃▇▅▁█` (заполнено = остаток,
/// чтобы направление линии совпадало с процентом remaining рядом в summary).
public enum AsciiSparkline {
    private static let blocks = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    public static func render(usedPercents: [Double], width: Int = 24) -> String {
        guard !usedPercents.isEmpty else { return "" }

        let values: [Double]

        if usedPercents.count <= width {
            values = usedPercents
        } else {
            // Бакетирование: width корзин, в каждой — максимум
            let bucketSize = usedPercents.count / width
            let remainder = usedPercents.count % width
            var bucketed: [Double] = []
            var idx = 0
            for i in 0..<width {
                let size = bucketSize + (i < remainder ? 1 : 0)
                let slice = usedPercents[idx..<idx + size]
                bucketed.append(slice.max()!)
                idx += size
            }
            values = bucketed
        }

        return values.map { v in
            let clamped = min(100, max(0, v))
            let index = Int(clamped / 100 * 7)
            return blocks[index]
        }.joined()
    }

    /// Трейлинг 7-дневный тренд (Core-модель `SparklineContent`): рендер его точек
    /// спарклайном заданной ширины. Пустая история → пустая строка (не ложная серия).
    public static func render(_ trend: SparklineContent, width: Int = 24) -> String {
        render(usedPercents: trend.points.map(\.remainingPercent), width: width)
    }
}

/// Датчик темы TUI `[||||······]`: число заполненных делений (заполнено = остаток).
public enum TuiGauge {
    public static func filledCount(remainingPercent: Double, width: Int = 14) -> Int {
        let clamped = min(100, max(0, remainingPercent))
        return Int((clamped / 100 * Double(width)).rounded())
    }
}
