import XCTest
@testable import MacLimitsTrackerCore

/// Гейт контраста палитр тём. Сами view лежат в executable-таргете и тестам
/// недоступны, но цвета — это числа в Core, и их можно проверить здесь.
///
/// Пороги WCAG 2.1 AA: 4.5:1 для обычного текста, 3:1 для нетекстовых
/// элементов (полосы, датчики, рамки).
final class ThemePaletteContrastTests: XCTestCase {
    private let textThreshold = 4.5
    private let nonTextThreshold = 3.0

    // MARK: - Вспомогательное

    private func assertText(_ name: String, _ fg: UInt32, on bg: UInt32,
                            file: StaticString = #filePath, line: UInt = #line) {
        let ratio = WcagContrast.ratio(fg, bg)
        XCTAssertGreaterThanOrEqual(
            ratio, textThreshold,
            String(format: "%@ contrast %.2f:1 below AA text threshold %.1f:1",
                   name, ratio, textThreshold),
            file: file, line: line)
    }

    private func assertNonText(_ name: String, _ fg: UInt32, on bg: UInt32,
                               file: StaticString = #filePath, line: UInt = #line) {
        let ratio = WcagContrast.ratio(fg, bg)
        XCTAssertGreaterThanOrEqual(
            ratio, nonTextThreshold,
            String(format: "%@ contrast %.2f:1 below AA non-text threshold %.1f:1",
                   name, ratio, nonTextThreshold),
            file: file, line: line)
    }

    // MARK: - Опорные значения формулы

    func test_ratio_blackOnWhite_is21() {
        XCTAssertEqual(WcagContrast.ratio(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
    }

    func test_ratio_whiteOnBlack_is21() {
        XCTAssertEqual(WcagContrast.ratio(0xFFFFFF, 0x000000), 21, accuracy: 0.01)
    }

    func test_ratio_identicalColors_is1() {
        XCTAssertEqual(WcagContrast.ratio(0x1A1B26, 0x1A1B26), 1, accuracy: 0.001)
    }

    func test_ratio_isSymmetric() {
        let a = WcagContrast.ratio(0x5C6497, 0x1A1B26)
        let b = WcagContrast.ratio(0x1A1B26, 0x5C6497)
        XCTAssertEqual(a, b, accuracy: 0.0001)
    }

    func test_ratio_knownValues() {
        XCTAssertEqual(WcagContrast.ratio(0x5C6497, 0x1A1B26), 3.03, accuracy: 0.01)
        XCTAssertEqual(WcagContrast.ratio(0x101216, 0xD0D5DD), 12.71, accuracy: 0.01)
        XCTAssertEqual(WcagContrast.ratio(0x1A1B26, 0xC0CAF5), 10.58, accuracy: 0.01)
    }

    // MARK: - Terminal

    func test_terminalTextTokens_meetAA() {
        let bg = ThemePalette.Terminal.bg
        assertText("terminal.fg", ThemePalette.Terminal.fg, on: bg)
        assertText("terminal.dim", ThemePalette.Terminal.dim, on: bg)
        assertText("terminal.cyan", ThemePalette.Terminal.cyan, on: bg)
        assertText("terminal.warning", ThemePalette.Terminal.warning, on: bg)
        assertText("terminal.critical", ThemePalette.Terminal.critical, on: bg)
    }

    func test_terminalTrack_meetsNonTextAA() {
        assertNonText("terminal.track", ThemePalette.Terminal.track,
                      on: ThemePalette.Terminal.bg)
    }

    // MARK: - Phosphor

    func test_phosphorTextTokens_meetAA() {
        let bg = ThemePalette.Phosphor.bg
        assertText("phosphor.bright", ThemePalette.Phosphor.bright, on: bg)
        assertText("phosphor.mid", ThemePalette.Phosphor.mid, on: bg)
        assertText("phosphor.dim", ThemePalette.Phosphor.dim, on: bg)
        assertText("phosphor.heading", ThemePalette.Phosphor.heading, on: bg)
    }

    /// Критичное окно рисуется инверсией: тёмный текст на яркой плашке.
    func test_phosphorCriticalInversion_meetsAA() {
        assertText("phosphor.bg on bright", ThemePalette.Phosphor.bg,
                   on: ThemePalette.Phosphor.bright)
    }

    // MARK: - TUI

    func test_tuiTextTokens_meetAA() {
        let bg = ThemePalette.Tui.bg
        assertText("tui.fg", ThemePalette.Tui.fg, on: bg)
        assertText("tui.dim", ThemePalette.Tui.dim, on: bg)
        assertText("tui.normal", ThemePalette.Tui.normal, on: bg)
        assertText("tui.warning", ThemePalette.Tui.warning, on: bg)
        assertText("tui.critical", ThemePalette.Tui.critical, on: bg)
    }

    func test_tuiBorder_meetsNonTextAA() {
        assertNonText("tui.border", ThemePalette.Tui.border, on: ThemePalette.Tui.bg)
    }

    // MARK: - Stale-состояние

    /// Секция с устаревшими данными рисуется через `.opacity(0.55)`, то есть
    /// каждый токен смешивается с фоном. Гейт проверяет именно смешанный цвет —
    /// иначе «приглушённый» текст проседает по контрасту незаметно для палитры.
    func test_staleOpacity_keepsTextTokensReadable() {
        let staleOpacity = StaleAppearance.opacity
        let cases: [(String, UInt32, UInt32)] = [
            ("terminal.dim", ThemePalette.Terminal.dim, ThemePalette.Terminal.bg),
            ("terminal.fg", ThemePalette.Terminal.fg, ThemePalette.Terminal.bg),
            ("phosphor.mid", ThemePalette.Phosphor.mid, ThemePalette.Phosphor.bg),
            ("phosphor.dim", ThemePalette.Phosphor.dim, ThemePalette.Phosphor.bg),
            ("tui.dim", ThemePalette.Tui.dim, ThemePalette.Tui.bg),
            ("tui.fg", ThemePalette.Tui.fg, ThemePalette.Tui.bg),
        ]
        for (name, fg, bg) in cases {
            let blended = blend(fg, over: bg, opacity: staleOpacity)
            let ratio = WcagContrast.ratio(blended, bg)
            XCTAssertGreaterThanOrEqual(
                ratio, nonTextThreshold,
                String(format: "stale %@ contrast %.2f:1 below %.1f:1",
                       name, ratio, nonTextThreshold))
        }
    }

    /// Альфа-композитинг в sRGB — так же, как это делает SwiftUI `.opacity`.
    private func blend(_ fg: UInt32, over bg: UInt32, opacity: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let f = Double((fg >> shift) & 0xFF)
            let b = Double((bg >> shift) & 0xFF)
            return UInt32((f * opacity + b * (1 - opacity)).rounded())
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }
}
