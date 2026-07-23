import XCTest
@testable import MacLimitsTrackerCore

/// Парсинг сырого ответа `GET /coding/v1/usages` (bd mac-limits-tracker-6gk.8).
/// Образец — маскированная, но реальная форма ответа (см. журнал/бид).
final class KimiUsagesParserTests: XCTestCase {
    private func sampleJSON(
        membershipLevel: String? = "LEVEL_INTERMEDIATE",
        limitsJSON: String = """
        [{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},
          "detail":{"limit":"100","remaining":"100","resetTime":"2026-07-23T08:15:06Z"}}]
        """
    ) -> Data {
        let membershipField = membershipLevel.map { #""membership":{"level":"\#($0)"},"# } ?? ""
        return Data("""
        {"user":{\(membershipField)"businessId":""},
         "usage":{"limit":"100","used":"44","remaining":"56","resetTime":"2026-07-27T10:15:06Z"},
         "limits":\(limitsJSON),
         "parallel":{"limit":"20"},"totalQuota":{},"subType":"TYPE_PURCHASE"}
        """.utf8)
    }

    func test_parse_fullSample_decodesWindowQuotaAndMembership() throws {
        let parsed = try XCTUnwrap(KimiUsagesParser.parse(sampleJSON()))
        XCTAssertEqual(parsed.membershipLevel, "LEVEL_INTERMEDIATE")
        XCTAssertEqual(parsed.usage.windows.count, 1)
        let window = try XCTUnwrap(parsed.usage.windows.first)
        XCTAssertEqual(window.windowDurationMins, 300)
        XCTAssertEqual(window.usedPercent, 0) // remaining == limit
        let quota = try XCTUnwrap(parsed.usage.quota)
        XCTAssertEqual(quota.limit, 100)
        XCTAssertEqual(quota.used, 44)
        XCTAssertEqual(quota.remaining, 56)
        XCTAssertNotNil(quota.resetsAt)
    }

    func test_parse_hourTimeUnit_multipliesToMinutes() throws {
        let json = sampleJSON(limitsJSON: """
        [{"window":{"duration":2,"timeUnit":"TIME_UNIT_HOUR"},
          "detail":{"limit":"10","remaining":"4","resetTime":"2026-07-23T08:15:06Z"}}]
        """)
        let parsed = try XCTUnwrap(KimiUsagesParser.parse(json))
        XCTAssertEqual(parsed.usage.windows.first?.windowDurationMins, 120)
    }

    func test_parse_dayTimeUnit_multipliesToMinutes() throws {
        let json = sampleJSON(limitsJSON: """
        [{"window":{"duration":1,"timeUnit":"TIME_UNIT_DAY"},
          "detail":{"limit":"10","remaining":"4","resetTime":"2026-07-23T08:15:06Z"}}]
        """)
        let parsed = try XCTUnwrap(KimiUsagesParser.parse(json))
        XCTAssertEqual(parsed.usage.windows.first?.windowDurationMins, 1440)
    }

    func test_parse_missingOptionalFields_doesNotThrow() throws {
        let json = Data(#"{"usage":{},"limits":[{"window":{},"detail":{}}]}"#.utf8)
        let parsed = try XCTUnwrap(KimiUsagesParser.parse(json))
        XCTAssertNil(parsed.membershipLevel)
        XCTAssertNil(parsed.usage.quota?.limit)
        XCTAssertEqual(parsed.usage.windows.count, 1)
        XCTAssertNil(parsed.usage.windows.first?.windowDurationMins)
        XCTAssertNil(parsed.usage.windows.first?.usedPercent)
    }

    func test_parse_emptyLimitsArray_windowsEmpty() throws {
        let parsed = try XCTUnwrap(KimiUsagesParser.parse(sampleJSON(limitsJSON: "[]")))
        XCTAssertTrue(parsed.usage.windows.isEmpty)
    }

    func test_parse_malformedJSON_returnsNil() {
        XCTAssertNil(KimiUsagesParser.parse(Data("not json".utf8)))
    }

    func test_parse_limitZero_usedPercentNil() throws {
        let json = sampleJSON(limitsJSON: """
        [{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},
          "detail":{"limit":"0","remaining":"0","resetTime":"2026-07-23T08:15:06Z"}}]
        """)
        let parsed = try XCTUnwrap(KimiUsagesParser.parse(json))
        XCTAssertNil(parsed.usage.windows.first?.usedPercent)
    }
}

final class KimiMembershipLevelFormatterTests: XCTestCase {
    func test_prettify_stripsLevelPrefixAndTitleCases() {
        XCTAssertEqual(KimiMembershipLevelFormatter.prettify("LEVEL_INTERMEDIATE"), "Intermediate")
    }

    func test_prettify_multiWordLevel_titleCasesEachWord() {
        XCTAssertEqual(KimiMembershipLevelFormatter.prettify("LEVEL_SUPER_USER"), "Super User")
    }

    func test_prettify_noPrefix_stillTitleCases() {
        XCTAssertEqual(KimiMembershipLevelFormatter.prettify("PRO"), "Pro")
    }

    func test_prettify_empty_returnsNil() {
        XCTAssertNil(KimiMembershipLevelFormatter.prettify(""))
    }
}

/// `KimiStatus.toSnapshot()` с реальными usage-данными (bd mac-limits-tracker-6gk.8).
final class KimiStatusToSnapshotUsageTests: XCTestCase {
    private static let sentinel = Date(timeIntervalSince1970: 1_700_000_000)

    private func status(usage: KimiUsage?, plan: String? = "Intermediate") -> KimiStatus {
        KimiStatus(loggedIn: true, plan: plan, usage: usage,
                  usageError: nil, providerError: nil, fetchedAt: Self.sentinel)
    }

    func test_toSnapshot_windowPresent_mapsUsedPercentAndDuration() {
        let usage = KimiUsage(
            windows: [KimiUsageWindow(windowDurationMins: 300, usedPercent: 0, resetsAt: nil)],
            quota: nil
        )
        let snapshot = status(usage: usage).toSnapshot()
        XCTAssertEqual(snapshot.windows, [
            SnapshotWindow(windowDurationMins: 300, usedPercent: 0, resetsAt: nil)
        ])
    }

    func test_toSnapshot_quota_becomesDetailNotWindow() {
        let resetsAt = ISO8601DateFormatter().date(from: "2026-07-27T10:15:06Z")
        let usage = KimiUsage(
            windows: [],
            quota: KimiQuotaDetail(limit: 100, used: 44, remaining: 56, resetsAt: resetsAt)
        )
        let snapshot = status(usage: usage).toSnapshot()
        XCTAssertTrue(snapshot.details.contains {
            $0.key == "Quota" && $0.value.contains("44 / 100 used")
        })
        XCTAssertNil(snapshot.windows) // пустой limits[] → нет окон
    }

    func test_toSnapshot_plan_prettifiedFromMembershipLevel() {
        let snapshot = status(usage: nil, plan: "Intermediate").toSnapshot()
        XCTAssertEqual(snapshot.plan, "Intermediate")
    }

    func test_toSnapshot_usageNil_windowsNilAndUsageErrorSurfaced() {
        let status = KimiStatus(loggedIn: true, plan: nil, usage: nil,
                                usageError: "Kimi login expired — open Kimi Code to refresh",
                                providerError: nil, fetchedAt: Self.sentinel)
        let snapshot = status.toSnapshot()
        XCTAssertNil(snapshot.windows)
        XCTAssertEqual(snapshot.usageError, "Kimi login expired — open Kimi Code to refresh")
    }
}
