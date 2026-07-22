import XCTest
@testable import MacLimitsTrackerCore

final class LimitsSnapshotMenuTitleTests: XCTestCase {
    private func makeSnapshot(
        loggedIn: Bool = true,
        plan: String? = nil,
        providerError: String? = nil
    ) -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: loggedIn,
            plan: plan,
            windows: nil,
            creditsBalance: nil,
            rateLimitReachedType: nil,
            details: [],
            daysUntilRenewal: nil,
            renewalDate: nil,
            usageError: nil,
            providerError: providerError,
            fetchedAt: Date()
        )
    }

    func test_providerError_showsQuestionMark() {
        let s = makeSnapshot(providerError: "boom")
        XCTAssertEqual(s.menuTitle(shortName: "Claude"), "Claude: ?")
    }

    func test_notLoggedIn_showsDash() {
        let s = makeSnapshot(loggedIn: false)
        XCTAssertEqual(s.menuTitle(shortName: "Claude"), "Claude: —")
    }

    func test_loggedInWithPlan_showsCapitalizedPlan() {
        let s = makeSnapshot(plan: "max")
        XCTAssertEqual(s.menuTitle(shortName: "Claude"), "Claude: Max")
    }

    func test_loggedInNoPlan_showsShortNameOnly() {
        let s = makeSnapshot(plan: nil)
        XCTAssertEqual(s.menuTitle(shortName: "Claude"), "Claude")
    }

    func test_loggedInEmptyPlan_showsShortNameOnly() {
        let s = makeSnapshot(plan: "")
        XCTAssertEqual(s.menuTitle(shortName: "Codex"), "Codex")
    }
}
