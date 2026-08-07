import Foundation

/// View-state единого блока тренда (UsageTrendView). Чистое значение, общее для
/// всех четырёх тем: рендерер только рисует, все решения — здесь.
public struct UsageTrendViewState: Equatable, Sendable {
    public let shortLabel: String
    public let windowLabel: String
    /// Явная подпись метрики у шкалы — без неё 0...100 нечитаем.
    public let metricLabel: String
    public let currentText: String
    public let severity: Severity
    /// Текстовый маркер severity («warning»/«critical»/«»): цвет — не единственный канал.
    public let severityCue: String
    /// Фиксированный домен Y — никакого автомасштаба.
    public let yDomain: ClosedRange<Double>
    /// Подписанные направляющие шкалы.
    public let scaleGuides: [Double]
    /// Фиксированный домен X — границы окна тренда из контракта.
    public let xDomain: ClosedRange<Date>
    public let trendRangeLabel: String
    public let periodStartLabel: String
    public let periodEndLabel: String
    /// Сегменты линии: разрыв больше порога режет серию (дисконтинуити вместо
    /// сплошной линии через пропуск данных).
    public let segments: [[SparklinePoint]]
    /// Рисовать ли соединяющую линию. false — только маркеры: sparse/stale не
    /// должны выглядеть уверенным трендом.
    public let showsLine: Bool
    /// fallbackText контракта для не-ok состояний; nil при .ok.
    public let noteText: String?
    public let accessibilityLabel: String
    public let accessibilityValue: String
}

/// Политика представления тренда: единственное место маппинга
/// SparklineContent (gld.1) → UsageTrendViewState. Темы получают одинаковую
/// геометрию, шкалу и подписи by construction.
public enum UsageTrendPresentationPolicy {
    public static let yDomain: ClosedRange<Double> = 0...100
    public static let scaleGuides: [Double] = [0, 50, 100]
    public static let metricLabel = "remaining %"

    private static let periodFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    public static func viewState(for content: SparklineContent) -> UsageTrendViewState {
        let severity = Severity.from(remainingPercent: content.currentPercent)
        let severityCue = severityCue(for: severity)

        let (segments, showsLine) = buildSegmentsAndLine(for: content)

        let fallback = content.fallbackText
        let noteText = fallback.isEmpty ? nil : fallback
        let currentText = String(format: "%.0f%%", content.currentPercent)
        let trendRangeLabel = trendRangeLabel(start: content.rangeStart, end: content.rangeEnd)

        let accessibilityValue = buildAccessibilityValue(
            currentText: currentText,
            severityCue: severityCue,
            noteText: noteText
        )

        return UsageTrendViewState(
            shortLabel: content.shortLabel,
            windowLabel: content.windowLabel,
            metricLabel: metricLabel,
            currentText: currentText,
            severity: severity,
            severityCue: severityCue,
            yDomain: yDomain,
            scaleGuides: scaleGuides,
            xDomain: content.rangeStart...content.rangeEnd,
            trendRangeLabel: trendRangeLabel,
            periodStartLabel: periodFormatter.string(from: content.rangeStart),
            periodEndLabel: periodFormatter.string(from: content.rangeEnd),
            segments: segments,
            showsLine: showsLine,
            noteText: noteText,
            accessibilityLabel: "\(content.shortLabel) \(trendRangeLabel) usage trend",
            accessibilityValue: accessibilityValue
        )
    }

    private static func severityCue(for severity: Severity) -> String {
        switch severity {
        case .normal: return ""
        case .warning: return "warning"
        case .critical: return "critical"
        }
    }

    private static func buildSegmentsAndLine(for content: SparklineContent) -> (segments: [[SparklinePoint]], showsLine: Bool) {
        switch content.dataState {
        case .ok:
            return (content.points.isEmpty ? [] : [content.points], true)
        case .gap(_, let thresholdSeconds):
            return (splitAtGaps(content.points, threshold: thresholdSeconds), true)
        case .sparse, .stale:
            // Точки есть, но уверенной линии нет — только маркеры.
            return (content.points.isEmpty ? [] : [content.points], false)
        case .empty, .loading:
            return ([], false)
        }
    }

    private static func buildAccessibilityValue(currentText: String, severityCue: String, noteText: String?) -> String {
        return [currentText + " remaining", severityCue, noteText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func splitAtGaps(_ points: [SparklinePoint], threshold: TimeInterval) -> [[SparklinePoint]] {
        guard !points.isEmpty else { return [] }
        var segments: [[SparklinePoint]] = [[points[0]]]
        for point in points.dropFirst() {
            if point.time.timeIntervalSince(segments[segments.count - 1].last!.time) > threshold {
                segments.append([point])
            } else {
                segments[segments.count - 1].append(point)
            }
        }
        return segments
    }

    private static func trendRangeLabel(start: Date, end: Date) -> String {
        let days = Int((end.timeIntervalSince(start) / 86400).rounded())
        return "\(days)d"
    }
}
