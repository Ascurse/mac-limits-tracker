import XCTest
@testable import MacLimitsTrackerCore

final class MenuBarDisplayModeTests: XCTestCase {
    private static let sentinel = Date(timeIntervalSince1970: 0)

    private let claudeDescriptor = ProviderDescriptor(
        id: "claude", displayName: "Claude Code", shortName: "Claude",
        menuBarSymbol: "C", accentColorHex: 0xFF9E64, loginHelp: nil
    )

    private let codexDescriptor = ProviderDescriptor(
        id: "codex", displayName: "Codex", shortName: "Codex",
        menuBarSymbol: "X", accentColorHex: 0x9ECE6A, loginHelp: nil
    )

    private func makeSnapshot(
        loggedIn: Bool = true,
        plan: String? = nil,
        windows: [SnapshotWindow]? = nil,
        providerError: String? = nil
    ) -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: loggedIn,
            plan: plan,
            windows: windows,
            creditsBalance: nil,
            rateLimitReachedType: nil,
            details: [],
            daysUntilRenewal: nil,
            renewalDate: nil,
            usageError: nil,
            providerError: providerError,
            fetchedAt: Self.sentinel
        )
    }

    // MARK: - iconAndText

    func test_iconAndText_withPlan_showsCapitalizedPlan() {
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: makeSnapshot(plan: "max")
        )
        let codexState = ProviderState(
            descriptor: codexDescriptor,
            snapshot: makeSnapshot(plan: "plus")
        )

        let text = MenuBarDisplayMode.iconAndText.menuBarText(states: [claudeState, codexState])
        XCTAssertEqual(text, "Claude: Max · Codex: Plus")
    }

    func test_iconAndText_withoutPlan_loggedIn_showsShortName() {
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: makeSnapshot(plan: nil)
        )
        let text = MenuBarDisplayMode.iconAndText.menuBarText(states: [claudeState])
        XCTAssertEqual(text, "Claude: Claude")
    }

    func test_iconAndText_emptyPlan_loggedIn_showsShortName() {
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: makeSnapshot(plan: "")
        )
        let text = MenuBarDisplayMode.iconAndText.menuBarText(states: [claudeState])
        XCTAssertEqual(text, "Claude: Claude")
    }

    func test_iconAndText_notLoggedIn_showsDash() {
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: makeSnapshot(loggedIn: false, plan: nil)
        )
        let text = MenuBarDisplayMode.iconAndText.menuBarText(states: [claudeState])
        XCTAssertEqual(text, "Claude: —")
    }

    func test_iconAndText_providerError_showsQuestionMark() {
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: makeSnapshot(plan: nil, providerError: "failed")
        )
        let text = MenuBarDisplayMode.iconAndText.menuBarText(states: [claudeState])
        XCTAssertEqual(text, "Claude: ?")
    }

    func test_iconAndText_nilSnapshot_showsShortName() {
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: nil
        )
        let text = MenuBarDisplayMode.iconAndText.menuBarText(states: [claudeState])
        XCTAssertEqual(text, "Claude: Claude")
    }

    // MARK: - iconAnd5h

    func test_iconAnd5h_with300MinWindow_showsPercentRemaining() {
        let windows = [
            SnapshotWindow(windowDurationMins: 300, usedPercent: 22, resetsAt: nil)
        ]
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: makeSnapshot(windows: windows)
        )

        let text = MenuBarDisplayMode.iconAnd5h.menuBarText(states: [claudeState])
        XCTAssertEqual(text, "C 78%")
    }

    func test_iconAnd5h_without300MinWindow_showsDash() {
        let windows = [
            SnapshotWindow(windowDurationMins: 10080, usedPercent: 22, resetsAt: nil)
        ]
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: makeSnapshot(windows: windows)
        )

        let text = MenuBarDisplayMode.iconAnd5h.menuBarText(states: [claudeState])
        XCTAssertEqual(text, "C —")
    }

    func test_iconAnd5h_nilUsedPercent_showsDash() {
        let windows = [
            SnapshotWindow(windowDurationMins: 300, usedPercent: nil, resetsAt: nil)
        ]
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: makeSnapshot(windows: windows)
        )

        let text = MenuBarDisplayMode.iconAnd5h.menuBarText(states: [claudeState])
        XCTAssertEqual(text, "C —")
    }

    func test_iconAnd5h_nilSnapshot_showsDash() {
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: nil
        )
        let text = MenuBarDisplayMode.iconAnd5h.menuBarText(states: [claudeState])
        XCTAssertEqual(text, "C —")
    }

    // MARK: - iconAnd5hWeekly

    func test_iconAnd5hWeekly_showsBothWindows() {
        let windows = [
            SnapshotWindow(windowDurationMins: 300, usedPercent: 22, resetsAt: nil),
            SnapshotWindow(windowDurationMins: 10080, usedPercent: 5, resetsAt: nil)
        ]
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: makeSnapshot(windows: windows)
        )
        let codexWindows = [
            SnapshotWindow(windowDurationMins: 300, usedPercent: 1, resetsAt: nil),
            SnapshotWindow(windowDurationMins: 10080, usedPercent: 18, resetsAt: nil)
        ]
        let codexState = ProviderState(
            descriptor: codexDescriptor,
            snapshot: makeSnapshot(windows: codexWindows)
        )

        let text = MenuBarDisplayMode.iconAnd5hWeekly.menuBarText(states: [claudeState, codexState])
        XCTAssertEqual(text, "C 5h 78% / 95% · X 5h 99% / 82%")
    }

    func test_iconAnd5hWeekly_missingWindows_showsDashes() {
        let windows = [
            SnapshotWindow(windowDurationMins: 10080, usedPercent: 18, resetsAt: nil)
        ]
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: makeSnapshot(windows: windows)
        )

        let text = MenuBarDisplayMode.iconAnd5hWeekly.menuBarText(states: [claudeState])
        XCTAssertEqual(text, "C 5h — / 82%")
    }

    func test_iconAnd5hWeekly_nilSnapshot_showsDashes() {
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: nil
        )
        let text = MenuBarDisplayMode.iconAnd5hWeekly.menuBarText(states: [claudeState])
        XCTAssertEqual(text, "C 5h — / —")
    }

    // MARK: - iconOnly

    func test_iconOnly_returnsNil() {
        let claudeState = ProviderState(
            descriptor: claudeDescriptor,
            snapshot: makeSnapshot()
        )
        let text = MenuBarDisplayMode.iconOnly.menuBarText(states: [claudeState])
        XCTAssertNil(text)
    }
}
