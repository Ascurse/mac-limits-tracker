import XCTest
@testable import MacLimitsTrackerCore

final class ProviderDescriptorTests: XCTestCase {
    func test_equatable_sameValues_areEqual() {
        let a = ProviderDescriptor(
            id: "claude", displayName: "Claude Code", shortName: "Claude",
            menuBarSymbol: "C", accentColorHex: 0xFF9E64,
            loginHelp: LoginHelp(helpText: "Open Claude Code to refresh the claude.ai login",
                                  binaryPath: "/usr/local/bin/claude")
        )
        let b = ProviderDescriptor(
            id: "claude", displayName: "Claude Code", shortName: "Claude",
            menuBarSymbol: "C", accentColorHex: 0xFF9E64,
            loginHelp: LoginHelp(helpText: "Open Claude Code to refresh the claude.ai login",
                                  binaryPath: "/usr/local/bin/claude")
        )
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentId_areNotEqual() {
        let a = ProviderDescriptor(id: "claude", displayName: "Claude Code", shortName: "Claude",
                                    menuBarSymbol: "C", accentColorHex: 0xFF9E64, loginHelp: nil)
        let b = ProviderDescriptor(id: "codex", displayName: "Codex", shortName: "Codex",
                                    menuBarSymbol: "X", accentColorHex: 0x9ECE6A, loginHelp: nil)
        XCTAssertNotEqual(a, b)
    }

    func test_loginHelp_optional() {
        let d = ProviderDescriptor(id: "codex", displayName: "Codex", shortName: "Codex",
                                    menuBarSymbol: "X", accentColorHex: 0x9ECE6A, loginHelp: nil)
        XCTAssertNil(d.loginHelp)
    }
}
