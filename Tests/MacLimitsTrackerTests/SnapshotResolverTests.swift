import XCTest
@testable import MacLimitsTrackerCore

private let defaultNow = Date(timeIntervalSince1970: 2_000_000)
private let defaultPast = Date(timeIntervalSince1970: 1_000_000)

final class SnapshotResolverTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 2_000_000)
    private static let past = Date(timeIntervalSince1970: 1_000_000)

    private static let descriptor = ProviderDescriptor(
        id: "test", displayName: "Test", shortName: "T",
        menuBarSymbol: "T", accentColorHex: 0, loginHelp: nil
    )

    private func makeSnapshot(
        loggedIn: Bool = true,
        plan: String? = nil,
        windows: [SnapshotWindow]? = nil,
        creditsBalance: String? = nil,
        rateLimitReachedType: String? = nil,
        daysUntilRenewal: Int? = nil,
        renewalDate: Date? = nil,
        usageError: String? = nil,
        providerError: String? = nil,
        fetchedAt: Date = defaultNow
    ) -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: loggedIn,
            plan: plan,
            windows: windows,
            creditsBalance: creditsBalance,
            rateLimitReachedType: rateLimitReachedType,
            details: [],
            daysUntilRenewal: daysUntilRenewal,
            renewalDate: renewalDate,
            usageError: usageError,
            providerError: providerError,
            fetchedAt: fetchedAt
        )
    }

    private func state(
        snapshot: LimitsSnapshot? = nil,
        lastGoodSnapshot: LimitsSnapshot? = nil
    ) -> ProviderState {
        ProviderState(
            descriptor: Self.descriptor,
            snapshot: snapshot,
            lastGoodSnapshot: lastGoodSnapshot
        )
    }

    // MARK: - isGood

    func test_isGood_noErrors_returnsTrue() {
        let snap = makeSnapshot()
        XCTAssertTrue(SnapshotResolver.isGood(snap))
    }

    func test_isGood_providerError_returnsFalse() {
        let snap = makeSnapshot(providerError: "boom")
        XCTAssertFalse(SnapshotResolver.isGood(snap))
    }

    func test_isGood_usageError_returnsFalse() {
        let snap = makeSnapshot(usageError: "token expired")
        XCTAssertFalse(SnapshotResolver.isGood(snap))
    }

    // MARK: - resolve

    /// a. snapshot == nil → passthrough Loading…
    func test_resolve_nilSnapshot_passthroughLoading() {
        let display = SnapshotResolver.resolve(state(snapshot: nil))
        XCTAssertNil(display.snapshot)
        XCTAssertFalse(display.isStale)
        XCTAssertNil(display.error)
    }

    /// b. providerError + есть lastGood → показываем lastGood, stale, ошибка внизу.
    func test_resolve_providerError_withLastGood_showsLastGoodAsStale() {
        let lastGood = makeSnapshot(plan: "max", windows: [
            SnapshotWindow(windowDurationMins: 300, usedPercent: 50, resetsAt: nil)
        ])
        let fresh = makeSnapshot(providerError: "network down")
        let display = SnapshotResolver.resolve(state(snapshot: fresh, lastGoodSnapshot: lastGood))

        XCTAssertEqual(display.snapshot, lastGood)
        XCTAssertTrue(display.isStale)
        XCTAssertEqual(display.error, "network down")
    }

    /// c. providerError + нет lastGood → свежий снапшот без ошибки (рендерит builder).
    func test_resolve_providerError_withoutLastGood_passthroughFresh() {
        let fresh = makeSnapshot(providerError: "no auth.json")
        let display = SnapshotResolver.resolve(state(snapshot: fresh))

        XCTAssertEqual(display.snapshot, fresh)
        XCTAssertFalse(display.isStale)
        XCTAssertNil(display.error)
    }

    /// d. usageError + свежих окон нет + у lastGood есть окна → мержим окна, stale.
    func test_resolve_usageError_mergesWindowsFromLastGood() {
        let lastGood = makeSnapshot(
            plan: "old-plan",
            windows: [
                SnapshotWindow(windowDurationMins: 300, usedPercent: 30, resetsAt: nil)
            ],
            creditsBalance: "12.50",
            rateLimitReachedType: "primary",
            fetchedAt: Self.past
        )
        let fresh = makeSnapshot(
            plan: "new-plan",
            usageError: "usage endpoint 500",
            fetchedAt: Self.now
        )
        let display = SnapshotResolver.resolve(state(snapshot: fresh, lastGoodSnapshot: lastGood))

        XCTAssertEqual(display.snapshot?.plan, "new-plan")
        XCTAssertEqual(display.snapshot?.windows, lastGood.windows)
        XCTAssertEqual(display.snapshot?.creditsBalance, "12.50")
        // rateLimitReachedType — транзиентное состояние, в stale-мерже зануляем,
        // иначе старый «rate limit reached» рендерится как свежая ошибка (ревью N3).
        XCTAssertNil(display.snapshot?.rateLimitReachedType)
        XCTAssertEqual(display.snapshot?.fetchedAt, Self.past)
        XCTAssertTrue(display.isStale)
        XCTAssertEqual(display.error, "usage endpoint 500")
    }

    /// Edge d: usageError есть, но у lastGood тоже нет окон → passthrough свежего.
    func test_resolve_usageError_lastGoodHasNoWindows_passthroughFresh() {
        let lastGood = makeSnapshot(fetchedAt: Self.past)
        let fresh = makeSnapshot(usageError: "usage unavailable", fetchedAt: Self.now)
        let display = SnapshotResolver.resolve(state(snapshot: fresh, lastGoodSnapshot: lastGood))

        XCTAssertEqual(display.snapshot, fresh)
        XCTAssertFalse(display.isStale)
        XCTAssertNil(display.error)
    }

    /// e. Иначе → passthrough свежего, не stale, без ошибки.
    func test_resolve_goodSnapshot_passthroughFresh() {
        let fresh = makeSnapshot(plan: "pro", windows: [
            SnapshotWindow(windowDurationMins: 300, usedPercent: 10, resetsAt: nil)
        ])
        let display = SnapshotResolver.resolve(state(snapshot: fresh))

        XCTAssertEqual(display.snapshot, fresh)
        XCTAssertFalse(display.isStale)
        XCTAssertNil(display.error)
    }
}
