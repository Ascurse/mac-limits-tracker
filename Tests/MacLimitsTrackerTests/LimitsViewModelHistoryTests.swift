import Foundation
import XCTest
@testable import MacLimitsTrackerCore

@MainActor
final class LimitsViewModelHistoryTests: XCTestCase {
    private var tempDirectory: URL!
    private var historyStore: HistoryStore!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        historyStore = HistoryStore(directory: tempDirectory)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        historyStore = nil
        super.tearDown()
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func snapshot(
        windows: [SnapshotWindow],
        usageError: String? = nil,
        providerError: String? = nil,
        fetchedAt: Date = Date()
    ) -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: true,
            plan: nil,
            windows: windows,
            creditsBalance: nil,
            rateLimitReachedType: nil,
            details: [],
            daysUntilRenewal: nil,
            renewalDate: nil,
            usageError: usageError,
            providerError: providerError,
            fetchedAt: fetchedAt
        )
    }

    func test_refresh_withUsageWindows_recordsSamplesPerWindow() async {
        let fetchedAt = Date()
        let windows = [
            SnapshotWindow(windowDurationMins: 300, usedPercent: 60, resetsAt: nil),
            SnapshotWindow(windowDurationMins: 10080, usedPercent: 85, resetsAt: nil)
        ]
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude", snapshot: snapshot(windows: windows, fetchedAt: fetchedAt))],
            historyStore: historyStore
        )

        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        let samples = vm.historySamples(providerId: "claude")
        XCTAssertEqual(samples.count, 2)
        XCTAssertTrue(samples.contains(where: {
            $0.providerId == "claude" && $0.windowMins == 300 && $0.usedPercent == 60 && $0.fetchedAt == fetchedAt
        }))
        XCTAssertTrue(samples.contains(where: {
            $0.providerId == "claude" && $0.windowMins == 10080 && $0.usedPercent == 85 && $0.fetchedAt == fetchedAt
        }))
    }

    func test_refresh_windowWithNilUsedPercent_recordsNothing() async {
        let windows = [SnapshotWindow(windowDurationMins: 300, usedPercent: nil, resetsAt: nil)]
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude", snapshot: snapshot(windows: windows))],
            historyStore: historyStore
        )

        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        XCTAssertTrue(vm.historySamples(providerId: "claude").isEmpty)
    }

    func test_refresh_snapshotWithUsageError_recordsNothing() async {
        let windows = [
            SnapshotWindow(windowDurationMins: 300, usedPercent: 50, resetsAt: nil),
            SnapshotWindow(windowDurationMins: 10080, usedPercent: 70, resetsAt: nil)
        ]
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude", snapshot: snapshot(windows: windows, usageError: "boom"))],
            historyStore: historyStore
        )

        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        XCTAssertTrue(vm.historySamples(providerId: "claude").isEmpty)
    }

    func test_refresh_twiceWithUnchangedData_dedupesToOneSample() async {
        let fetchedAt = Date()
        let windows = [
            SnapshotWindow(windowDurationMins: 300, usedPercent: 50, resetsAt: nil),
            SnapshotWindow(windowDurationMins: 10080, usedPercent: 70, resetsAt: nil)
        ]
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude", snapshot: snapshot(windows: windows, fetchedAt: fetchedAt))],
            historyStore: historyStore
        )

        vm.refresh()
        await waitUntil { !vm.isRefreshing }
        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        let samples = vm.historySamples(providerId: "claude")
        XCTAssertEqual(samples.count, 2)
    }

    func test_historySamples_returnsRecordedForProvider() async {
        let fetchedAt = Date()
        let claudeWindows = [SnapshotWindow(windowDurationMins: 300, usedPercent: 40, resetsAt: nil)]
        let codexWindows = [SnapshotWindow(windowDurationMins: 300, usedPercent: 55, resetsAt: nil)]
        let vm = LimitsViewModel(
            providers: [
                StubProvider(id: "claude", snapshot: snapshot(windows: claudeWindows, fetchedAt: fetchedAt)),
                StubProvider(id: "codex", snapshot: snapshot(windows: codexWindows, fetchedAt: fetchedAt))
            ],
            historyStore: historyStore
        )

        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        let claude = vm.historySamples(providerId: "claude")
        XCTAssertEqual(claude.count, 1)
        XCTAssertEqual(claude.first?.usedPercent, 40)

        let codex = vm.historySamples(providerId: "codex")
        XCTAssertEqual(codex.count, 1)
        XCTAssertEqual(codex.first?.usedPercent, 55)
    }
}
