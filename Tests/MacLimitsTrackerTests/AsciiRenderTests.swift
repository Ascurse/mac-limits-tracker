import XCTest
@testable import MacLimitsTrackerCore

final class AsciiBarTests: XCTestCase {
    func test_empty_full_half() {
        XCTAssertEqual(AsciiBar.render(remainingPercent: 0), String(repeating: "░", count: 14))
        XCTAssertEqual(AsciiBar.render(remainingPercent: 100), String(repeating: "█", count: 14))
        XCTAssertEqual(AsciiBar.render(remainingPercent: 50),
                       String(repeating: "█", count: 7) + String(repeating: "░", count: 7))
    }

    func test_clampsOutOfRange() {
        XCTAssertEqual(AsciiBar.render(remainingPercent: -5), String(repeating: "░", count: 14))
        XCTAssertEqual(AsciiBar.render(remainingPercent: 140), String(repeating: "█", count: 14))
    }

    func test_customWidth() {
        XCTAssertEqual(AsciiBar.render(remainingPercent: 50, width: 4), "██░░")
    }
}
