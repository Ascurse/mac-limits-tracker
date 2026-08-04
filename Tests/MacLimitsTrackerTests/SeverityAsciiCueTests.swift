import XCTest
@testable import MacLimitsTrackerCore

/// Монохромные темы не могут различать severity цветом, поэтому каждое
/// состояние несёт два независимых нецветовых признака: текстуру полосы
/// и текстовый маркер. Тест держит контракт «три состояния — три вида».
final class SeverityAsciiCueTests: XCTestCase {
    private let width = 14

    // MARK: - Текстура полосы

    func test_barTexture_differsForEverySeverity() {
        let bars = [Severity.normal, .warning, .critical].map {
            AsciiBar.render(remainingPercent: 50, severity: $0, width: width)
        }
        XCTAssertEqual(Set(bars).count, 3, "полосы трёх состояний должны отличаться: \(bars)")
    }

    func test_barTexture_keepsWidthAcrossSeverities() {
        for severity in [Severity.normal, .warning, .critical] {
            for percent in [0.0, 33.0, 50.0, 100.0] {
                let bar = AsciiBar.render(remainingPercent: percent,
                                          severity: severity, width: width)
                XCTAssertEqual(bar.count, width,
                               "\(severity) at \(percent)% дал ширину \(bar.count)")
            }
        }
    }

    func test_barTexture_fillLengthMatchesRemaining() {
        // Доля заполнения не зависит от severity — меняется только глиф.
        for severity in [Severity.normal, .warning, .critical] {
            let bar = AsciiBar.render(remainingPercent: 50, severity: severity, width: width)
            let empty = bar.filter { $0 == "░" }.count
            XCTAssertEqual(empty, width / 2, "\(severity): ожидалось \(width / 2) пустых ячеек")
        }
    }

    func test_normalSeverity_matchesPlainRender() {
        // Обычное состояние выглядит ровно как раньше — регрессии вида нет.
        XCTAssertEqual(
            AsciiBar.render(remainingPercent: 42, severity: .normal, width: width),
            AsciiBar.render(remainingPercent: 42, width: width))
    }

    // MARK: - Текстовый маркер

    func test_asciiMarker_escalatesWithSeverity() {
        XCTAssertEqual(Severity.normal.asciiMarker, "")
        XCTAssertEqual(Severity.warning.asciiMarker, "!")
        XCTAssertEqual(Severity.critical.asciiMarker, "!!")
    }

    func test_asciiMarker_isUniquePerSeverity() {
        let markers = [Severity.normal, .warning, .critical].map(\.asciiMarker)
        XCTAssertEqual(Set(markers).count, 3)
    }

    // MARK: - Ярлык для VoiceOver

    func test_accessibilityLabel_namesEverySeverity() {
        XCTAssertEqual(Severity.normal.accessibilityLabel, "normal")
        XCTAssertEqual(Severity.warning.accessibilityLabel, "warning")
        XCTAssertEqual(Severity.critical.accessibilityLabel, "critical")
    }
}
