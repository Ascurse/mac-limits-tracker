import Foundation
import XCTest
@testable import MacLimitsTrackerCore

/// Сервис-заглушка: отдаёт заранее заданные результаты, не читая диск
/// (реальный `LocalCostEstimateService` сканирует локальные логи CLI —
/// в тестах домашняя директория не трогается).
private final class StubCostEstimator: CostEstimating, @unchecked Sendable {
    private var results: [CostEstimateResult]
    private(set) var periods: [CostPeriod] = []

    init(results: [CostEstimateResult]) {
        self.results = results
    }

    func estimate(period: CostPeriod, now: Date, calendar: Calendar) -> CostEstimateResult {
        periods.append(period)
        return results[min(periods.count - 1, results.count - 1)]
    }
}

@MainActor
final class LimitsViewModelCostTests: XCTestCase {
    private let pricingVersion = "2026-07-static-v1"

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func estimate(total: String = "12.34") -> CostEstimate {
        CostEstimate(total: Decimal(string: total)!, breakdown: [], pricingTableVersion: pricingVersion)
    }

    private func availableResult(total: String = "12.34") -> CostEstimateResult {
        .available(estimate(total: total), diagnostics: CostDiagnostics())
    }

    private func makeViewModel(
        costResults: [CostEstimateResult],
        providers: [any LimitsProvider] = [StubProvider(id: "claude")]
    ) -> (LimitsViewModel, StubCostEstimator) {
        let stub = StubCostEstimator(results: costResults)
        let vm = LimitsViewModel(providers: providers, costService: stub)
        return (vm, stub)
    }

    func test_refreshCostEstimate_publishesInjectedResult() async {
        let result = availableResult()
        let (vm, stub) = makeViewModel(costResults: [result])

        vm.refreshCostEstimate()
        await waitUntil { vm.costEstimate != nil }

        XCTAssertEqual(vm.costEstimate, result)
        XCTAssertEqual(stub.periods, [.last7Days])
    }

    func test_start_triggersCostRefreshAlongsideQuotaRefresh() async {
        let (vm, _) = makeViewModel(costResults: [availableResult()])

        vm.start()
        await waitUntil { vm.costEstimate != nil && !vm.isRefreshing }

        XCTAssertNotNil(vm.costEstimate, "start() должен запускать и обновление оценки стоимости")
        XCTAssertNotNil(vm.states.first?.snapshot, "start() по-прежнему обновляет квоты")
    }

    func test_quotaRefresh_doesNotTriggerCostRefresh_pathsAreIndependent() async {
        let (vm, stub) = makeViewModel(costResults: [availableResult()])

        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        XCTAssertTrue(stub.periods.isEmpty,
                      "refresh() квот не должен запускать обновление стоимости")
        XCTAssertNil(vm.costEstimate)
    }

    func test_quotaRefreshFailure_doesNotClearCostEstimate() async {
        let errorSnapshot = LimitsSnapshot(
            loggedIn: true, plan: nil, windows: nil, creditsBalance: nil,
            rateLimitReachedType: nil, details: [], daysUntilRenewal: nil,
            renewalDate: nil, usageError: nil, providerError: "network unreachable",
            fetchedAt: Date()
        )
        let result = availableResult()
        let (vm, _) = makeViewModel(
            costResults: [result],
            providers: [StubProvider(id: "claude", snapshot: errorSnapshot)]
        )

        vm.refreshCostEstimate()
        await waitUntil { vm.costEstimate != nil }
        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        XCTAssertEqual(vm.costEstimate, result,
                       "ошибка квоты не должна сбрасывать опубликованную оценку стоимости")
    }

    func test_refreshCostEstimate_repeatedCalls_publishLatestResult() async {
        let first = availableResult(total: "1.00")
        let second = availableResult(total: "2.00")
        let (vm, stub) = makeViewModel(costResults: [first, second])

        vm.refreshCostEstimate()
        await waitUntil { vm.costEstimate != nil }
        vm.refreshCostEstimate()
        await waitUntil { stub.periods.count >= 2 }
        await waitUntil { vm.costEstimate == second }

        XCTAssertEqual(vm.costEstimate, second)
        XCTAssertEqual(stub.periods, [.last7Days, .last7Days])
    }
}
