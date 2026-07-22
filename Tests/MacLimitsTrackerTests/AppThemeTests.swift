import XCTest
@testable import MacLimitsTrackerCore

final class AppThemeTests: XCTestCase {
    func test_rawValuesStable_forPersistence() {
        // rawValue персистится в @AppStorage — менять нельзя.
        XCTAssertEqual(AppTheme.system.rawValue, "system")
        XCTAssertEqual(AppTheme.terminal.rawValue, "terminal")
        XCTAssertEqual(AppTheme.phosphor.rawValue, "phosphor")
        XCTAssertEqual(AppTheme.tui.rawValue, "tui")
    }

    func test_allCasesOrder_systemFirst() {
        XCTAssertEqual(AppTheme.allCases, [.system, .terminal, .phosphor, .tui])
    }

    func test_titles() {
        XCTAssertEqual(AppTheme.system.title, "System")
        XCTAssertEqual(AppTheme.terminal.title, "Terminal")
        XCTAssertEqual(AppTheme.phosphor.title, "Phosphor")
        XCTAssertEqual(AppTheme.tui.title, "TUI")
    }
}
