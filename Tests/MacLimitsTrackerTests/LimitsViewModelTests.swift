import XCTest
@testable import MacLimitsTrackerCore

/// Провайдер-заглушка: снапшот и descriptor заданы в конструкторе, fetch() не выполняет I/O.
private struct StubProvider: LimitsProvider {
    let descriptor: ProviderDescriptor
    let snapshot: LimitsSnapshot

    init(id: String, snapshot: LimitsSnapshot = StubProvider.emptySnapshot) {
        descriptor = ProviderDescriptor(id: id, displayName: id, shortName: id,
                                        menuBarSymbol: String(id.prefix(1)).uppercased(),
                                        accentColorHex: 0, loginHelp: nil)
        self.snapshot = snapshot
    }

    func fetch() async -> LimitsSnapshot { snapshot }

    static let emptySnapshot = LimitsSnapshot(
        loggedIn: true, plan: nil, windows: nil, creditsBalance: nil,
        rateLimitReachedType: nil, details: [], daysUntilRenewal: nil,
        renewalDate: nil, usageError: nil, providerError: nil, fetchedAt: Date()
    )
}

/// Управляемая точка приостановки для `fetch()`: тест сам решает, когда
/// подвешенный запрос провайдера должен вернуть результат — так
/// воспроизводится гонка refresh()-в-полёте против смены настроек.
private actor FetchGate {
    private var isOpen: Bool
    private var continuation: CheckedContinuation<Void, Never>?

    init(isOpen: Bool) { self.isOpen = isOpen }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }

    func close() {
        isOpen = false
    }
}

/// Провайдер, чей fetch() не завершается, пока тест не откроет `gate`.
private struct GatedProvider: LimitsProvider {
    let descriptor: ProviderDescriptor
    let gate: FetchGate
    let snapshot: LimitsSnapshot

    init(id: String, gate: FetchGate, snapshot: LimitsSnapshot = StubProvider.emptySnapshot) {
        descriptor = ProviderDescriptor(id: id, displayName: id, shortName: id,
                                        menuBarSymbol: String(id.prefix(1)).uppercased(),
                                        accentColorHex: 0, loginHelp: nil)
        self.gate = gate
        self.snapshot = snapshot
    }

    func fetch() async -> LimitsSnapshot {
        await gate.wait()
        return snapshot
    }
}

@MainActor
final class LimitsViewModelProviderSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "LimitsViewModelProviderSettingsTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_noSettings_showsAllProvidersInRegistryOrder() {
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: ProviderSettingsStore(defaults: defaults)
        )
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude", "codex"])
    }

    func test_disabledProvider_isExcludedFromStates() {
        let store = ProviderSettingsStore(defaults: defaults)
        store.save([
            ProviderSetting(id: "claude", isEnabled: true),
            ProviderSetting(id: "codex", isEnabled: false)
        ])
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: store
        )
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude"])
    }

    func test_savedOrder_isAppliedToStates() {
        let store = ProviderSettingsStore(defaults: defaults)
        store.save([
            ProviderSetting(id: "codex", isEnabled: true),
            ProviderSetting(id: "claude", isEnabled: true)
        ])
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: store
        )
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["codex", "claude"])
    }

    func test_setProviderEnabled_false_removesFromStatesImmediately() {
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: ProviderSettingsStore(defaults: defaults)
        )
        vm.setProviderEnabled(false, id: "codex")
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude"])
    }

    func test_setProviderEnabled_persistsAcrossViewModelInstances() {
        let store = ProviderSettingsStore(defaults: defaults)
        let vm1 = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: store
        )
        vm1.setProviderEnabled(false, id: "codex")

        let vm2 = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: ProviderSettingsStore(defaults: defaults)
        )
        XCTAssertEqual(vm2.states.map(\.descriptor.id), ["claude"])
    }

    func test_moveProviderUp_reordersStatesAndPersists() {
        let store = ProviderSettingsStore(defaults: defaults)
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: store
        )
        vm.moveProviderUp(id: "codex")
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["codex", "claude"])

        let vm2 = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: ProviderSettingsStore(defaults: defaults)
        )
        XCTAssertEqual(vm2.states.map(\.descriptor.id), ["codex", "claude"])
    }

    func test_providerSettingsWithDescriptors_includesDisabledProvidersInOrder() {
        let store = ProviderSettingsStore(defaults: defaults)
        store.save([
            ProviderSetting(id: "codex", isEnabled: false),
            ProviderSetting(id: "claude", isEnabled: true)
        ])
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: store
        )
        let entries = vm.providerSettingsWithDescriptors
        XCTAssertEqual(entries.map(\.setting.id), ["codex", "claude"])
        XCTAssertEqual(entries.map(\.setting.isEnabled), [false, true])
        XCTAssertEqual(entries.map(\.descriptor.displayName), ["codex", "claude"])
    }

    func test_reenablingProvider_appearsAtItsSavedPosition() {
        let store = ProviderSettingsStore(defaults: defaults)
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: store
        )
        vm.setProviderEnabled(false, id: "claude")
        vm.setProviderEnabled(true, id: "claude")
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude", "codex"])
    }

    /// Гонка: refresh() захватывает состав провайдеров на момент старта. Если
    /// пользователь выключает провайдера, пока старый fetch ещё в полёте, а
    /// оставшиеся провайдеры уже имеют не-nil снапшот (из предыдущего
    /// завершённого refresh), applyProviderSettingsChange не должен пропускать
    /// повторный refresh() — иначе завершение устаревшей задачи перезапишет
    /// states и «воскресит» выключенного провайдера.
    func test_disablingProviderWhileStaleRefreshInFlight_doesNotResurrectIt() async {
        let gate = FetchGate(isOpen: true)
        let store = ProviderSettingsStore(defaults: defaults)
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude"), GatedProvider(id: "codex", gate: gate)],
            settingsStore: store
        )

        // Первый refresh: gate открыт, оба провайдера сразу отдают снапшот —
        // states получают реальные (не-nil) снапшоты.
        vm.refresh()
        await waitUntil { !vm.isRefreshing }
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude", "codex"])
        XCTAssertNotNil(vm.states.last?.snapshot)

        // Второй refresh: codex подвисает на gate, claude отвечает мгновенно —
        // states при этом ещё старые (не-nil у обоих), т.к. TaskGroup ждёт всех.
        await gate.close()
        vm.refresh()
        await waitUntil { vm.isRefreshing }

        // Пользователь выключает codex, пока старый refresh всё ещё в полёте.
        vm.setProviderEnabled(false, id: "codex")
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude"],
                       "codex должен пропасть немедленно, до завершения устаревшего refresh")

        // Отпускаем устаревший (уже отменённый) fetch codex.
        await gate.open()
        await waitUntil { !vm.isRefreshing }

        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude"],
                       "codex не должен воскреснуть после завершения устаревшей задачи")
    }

    /// Опрашивает `condition` до истинного значения либо до таймаута —
    /// без этого тест гонки не дождался бы завершения фонового Task.
    private func waitUntil(
        timeout: TimeInterval = 2, _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
