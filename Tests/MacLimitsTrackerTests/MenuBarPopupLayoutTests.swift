import XCTest
@testable import MacLimitsTrackerCore

final class MenuBarPopupLayoutTests: XCTestCase {
    func test_menuBarPopupLayout_matchesContract() {
        XCTAssertEqual(MenuBarPopupLayout.minWidth, 320)
        XCTAssertEqual(MenuBarPopupLayout.idealWidth, 340)
        XCTAssertEqual(MenuBarPopupLayout.maxHeight, 520)
        XCTAssertGreaterThan(MenuBarPopupLayout.minWidth, 0)
        XCTAssertGreaterThan(MenuBarPopupLayout.idealWidth, MenuBarPopupLayout.minWidth)
        XCTAssertGreaterThan(MenuBarPopupLayout.maxHeight, MenuBarPopupLayout.idealWidth)
    }
}
