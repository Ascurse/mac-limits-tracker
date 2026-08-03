import XCTest
@testable import MacLimitsTrackerCore

final class DesktopDashboardLayoutTests: XCTestCase {
    func test_maxContentWidth_withinReadableRange() {
        // Спека bd gld.3: единая читабельная колонка ~760–900 pt.
        XCTAssertGreaterThanOrEqual(DesktopDashboardLayout.maxContentWidth, 760)
        XCTAssertLessThanOrEqual(DesktopDashboardLayout.maxContentWidth, 900)
    }

    func test_minContentWidth_belowMax_aboveZero() {
        XCTAssertGreaterThan(DesktopDashboardLayout.minContentWidth, 0)
        XCTAssertLessThan(DesktopDashboardLayout.minContentWidth,
                          DesktopDashboardLayout.maxContentWidth)
    }

    func test_windowMinWidth_coversMinColumnPlusPadding() {
        // Инвариант геометрии: при минимальной ширине окна колонка контента
        // не сжимается ниже minContentWidth — горизонтального скролла нет.
        let minWindow = DesktopDashboardLayout.minContentWidth
            + 2 * DesktopDashboardLayout.horizontalPadding
        XCTAssertGreaterThanOrEqual(DesktopDashboardLayout.minWindowWidth, minWindow)
    }
}
