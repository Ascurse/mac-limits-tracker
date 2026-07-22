import XCTest
@testable import MacLimitsTrackerCore

final class ClaudeStatusSnapshotMappingTests: XCTestCase {
    private static let sentinel = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStatus(
        subscriptionType: String? = "max",
        usage: ClaudeUsage? = nil,
        usageError: String? = nil,
        providerError: String? = nil
    ) -> ClaudeStatus {
        ClaudeStatus(
            loggedIn: true, authMethod: nil, apiProvider: nil, email: nil,
            subscriptionType: subscriptionType, orgName: nil,
            today: nil, latestDay: nil, lastComputedDate: nil,
            totalSessions: nil, totalMessages: nil,
            usage: usage, usageError: usageError,
            fetchedAt: Self.sentinel, providerError: providerError
        )
    }

    private func window(_ utilization: Double, resetsAt: Date? = nil) -> ClaudeUsageWindow {
        ClaudeUsageWindow(utilizationPercent: utilization, resetsAt: resetsAt,
                          limitDollars: nil, usedDollars: nil, remainingDollars: nil)
    }

    func test_noUsage_windowsIsNil() {
        let s = makeStatus(usage: nil)
        XCTAssertNil(s.toSnapshot().windows)
    }

    func test_usagePresent_alwaysProducesTwoSlots_5hAnd7d() {
        let usage = ClaudeUsage(fiveHour: window(22), sevenDay: window(5))
        let snap = makeStatus(usage: usage).toSnapshot()
        XCTAssertEqual(snap.windows?.count, 2)
        XCTAssertEqual(snap.windows?[0].windowDurationMins, 300)
        XCTAssertEqual(snap.windows?[0].usedPercent, 22)
        XCTAssertEqual(snap.windows?[1].windowDurationMins, 10080)
        XCTAssertEqual(snap.windows?[1].usedPercent, 5)
    }

    func test_fiveHourMissing_producesPlaceholderSlotWithNilUsedPercent() {
        let usage = ClaudeUsage(fiveHour: nil, sevenDay: window(5))
        let snap = makeStatus(usage: usage).toSnapshot()
        XCTAssertEqual(snap.windows?.count, 2)
        XCTAssertEqual(snap.windows?[0].windowDurationMins, 300)
        XCTAssertNil(snap.windows?[0].usedPercent)
    }

    func test_plan_passesThroughSubscriptionType() {
        XCTAssertEqual(makeStatus(subscriptionType: "pro").toSnapshot().plan, "pro")
    }

    func test_detailsAlwaysEmpty() {
        XCTAssertEqual(makeStatus().toSnapshot().details, [])
    }

    func test_creditsAndRateLimitAlwaysNil() {
        let snap = makeStatus().toSnapshot()
        XCTAssertNil(snap.creditsBalance)
        XCTAssertNil(snap.rateLimitReachedType)
    }

    func test_renewalFieldsAlwaysNil() {
        let snap = makeStatus().toSnapshot()
        XCTAssertNil(snap.daysUntilRenewal)
        XCTAssertNil(snap.renewalDate)
    }

    func test_errorsAndFetchedAt_passThrough() {
        let snap = makeStatus(usageError: "expired", providerError: "boom").toSnapshot()
        XCTAssertEqual(snap.usageError, "expired")
        XCTAssertEqual(snap.providerError, "boom")
        XCTAssertEqual(snap.fetchedAt, Self.sentinel)
    }
}

final class CodexStatusSnapshotMappingTests: XCTestCase {
    private static let sentinel = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStatus(
        planType: String? = "plus",
        usage: CodexUsage? = nil,
        usageError: String? = nil,
        authMode: String? = nil,
        email: String? = nil,
        accountOwner: String? = nil,
        daysUntilRenewal: Int? = nil,
        subscriptionActiveUntil: Date? = nil,
        providerError: String? = nil
    ) -> CodexStatus {
        CodexStatus(
            loggedIn: true, authMode: authMode, email: email, planType: planType,
            subscriptionActiveUntil: subscriptionActiveUntil,
            daysUntilRenewal: daysUntilRenewal, accountOwner: accountOwner,
            usage: usage, usageError: usageError,
            fetchedAt: Self.sentinel, providerError: providerError
        )
    }

    private func window(_ used: Double, duration: Int?, resetsAt: Date? = nil) -> CodexUsageWindow {
        CodexUsageWindow(usedPercent: used, windowDurationMins: duration, resetsAt: resetsAt)
    }

    func test_noSnapshot_windowsCreditsRateLimitAreNil() {
        let snap = makeStatus(usage: CodexUsage(snapshot: nil, error: "x")).toSnapshot()
        XCTAssertNil(snap.windows)
        XCTAssertNil(snap.creditsBalance)
        XCTAssertNil(snap.rateLimitReachedType)
    }

    func test_noUsageAtAll_windowsIsNil() {
        XCTAssertNil(makeStatus(usage: nil).toSnapshot().windows)
    }

    func test_snapshotWindows_onlyRealWindowsIncluded_noPlaceholders() {
        let snap = CodexUsageSnapshot(primary: window(70, duration: 300), secondary: nil,
                                      planType: nil, creditsBalance: nil, rateLimitReachedType: nil)
        let result = makeStatus(usage: CodexUsage(snapshot: snap)).toSnapshot()
        XCTAssertEqual(result.windows?.count, 1)
        XCTAssertEqual(result.windows?[0].windowDurationMins, 300)
        XCTAssertEqual(result.windows?[0].usedPercent, 70)
    }

    func test_windows_sortedFiveHourFirstRegardlessOfApiPosition() {
        // weekly пришёл в primary — сортировка по длительности, не по позиции (см. bd mac-limits-tracker-w4a).
        let snap = CodexUsageSnapshot(primary: window(10, duration: 10080),
                                      secondary: window(70, duration: 300),
                                      planType: nil, creditsBalance: nil, rateLimitReachedType: nil)
        let result = makeStatus(usage: CodexUsage(snapshot: snap)).toSnapshot()
        XCTAssertEqual(result.windows?.map(\.windowDurationMins), [300, 10080])
    }

    func test_nonStandardDurationWindow_sortedAfterWeekly() {
        let snap = CodexUsageSnapshot(primary: window(70, duration: 300),
                                      secondary: window(40, duration: 60),
                                      planType: nil, creditsBalance: nil, rateLimitReachedType: nil)
        let result = makeStatus(usage: CodexUsage(snapshot: snap)).toSnapshot()
        XCTAssertEqual(result.windows?.map(\.windowDurationMins), [300, 60])
    }

    func test_nilDurationWindow_sortedLast() {
        let snap = CodexUsageSnapshot(primary: window(70, duration: nil),
                                      secondary: window(40, duration: 300),
                                      planType: nil, creditsBalance: nil, rateLimitReachedType: nil)
        let result = makeStatus(usage: CodexUsage(snapshot: snap)).toSnapshot()
        XCTAssertEqual(result.windows?.map(\.windowDurationMins), [300, nil])
    }

    func test_plan_livePlanTypeWinsOverJwtClaim() {
        let snap = CodexUsageSnapshot(primary: nil, secondary: nil, planType: "pro",
                                      creditsBalance: nil, rateLimitReachedType: nil)
        let result = makeStatus(planType: "plus", usage: CodexUsage(snapshot: snap)).toSnapshot()
        XCTAssertEqual(result.plan, "pro")
    }

    func test_plan_fallsBackToJwtClaimWhenNoSnapshot() {
        XCTAssertEqual(makeStatus(planType: "plus", usage: nil).toSnapshot().plan, "plus")
    }

    func test_emptyCreditsBalance_becomesNil() {
        let snap = CodexUsageSnapshot(primary: nil, secondary: nil, planType: nil,
                                      creditsBalance: "", rateLimitReachedType: nil)
        let result = makeStatus(usage: CodexUsage(snapshot: snap)).toSnapshot()
        XCTAssertNil(result.creditsBalance)
    }

    func test_nonEmptyCreditsBalance_passesThrough() {
        let snap = CodexUsageSnapshot(primary: nil, secondary: nil, planType: nil,
                                      creditsBalance: "$5.00", rateLimitReachedType: nil)
        let result = makeStatus(usage: CodexUsage(snapshot: snap)).toSnapshot()
        XCTAssertEqual(result.creditsBalance, "$5.00")
    }

    func test_rateLimitReachedType_passesThrough() {
        let snap = CodexUsageSnapshot(primary: nil, secondary: nil, planType: nil,
                                      creditsBalance: nil, rateLimitReachedType: "secondary")
        let result = makeStatus(usage: CodexUsage(snapshot: snap)).toSnapshot()
        XCTAssertEqual(result.rateLimitReachedType, "secondary")
    }

    func test_details_includesOnlyPresentFieldsInOrder() {
        let result = makeStatus(authMode: "chatgpt", email: "x@y.z", accountOwner: "Acme").toSnapshot()
        XCTAssertEqual(result.details, [
            SnapshotDetail(key: "Auth", value: "chatgpt"),
            SnapshotDetail(key: "Account", value: "x@y.z"),
            SnapshotDetail(key: "Org", value: "Acme")
        ])
    }

    func test_details_omitsMissingFields() {
        let result = makeStatus(authMode: "chatgpt", email: nil, accountOwner: nil).toSnapshot()
        XCTAssertEqual(result.details, [SnapshotDetail(key: "Auth", value: "chatgpt")])
    }

    func test_renewalFields_passThrough() {
        let until = Date(timeIntervalSince1970: 1_800_000_000)
        let result = makeStatus(daysUntilRenewal: 12, subscriptionActiveUntil: until).toSnapshot()
        XCTAssertEqual(result.daysUntilRenewal, 12)
        XCTAssertEqual(result.renewalDate, until)
    }

    func test_errorsAndFetchedAt_passThrough() {
        let result = makeStatus(usageError: "unreadable", providerError: "no auth.json").toSnapshot()
        XCTAssertEqual(result.usageError, "unreadable")
        XCTAssertEqual(result.providerError, "no auth.json")
        XCTAssertEqual(result.fetchedAt, Self.sentinel)
    }
}
