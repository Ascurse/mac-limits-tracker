import XCTest
@testable import MacLimitsTrackerCore

/// Провайдер-заглушка: снапшот и descriptor заданы в конструкторе, fetch() не выполняет I/O.
struct StubProvider: LimitsProvider {
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
    private var historyStore: HistoryStore!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        historyStore = HistoryStore(directory: tempDirectory)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        historyStore = nil
        super.tearDown()
    }

    func test_noSettings_showsAllProvidersInRegistryOrder() {
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            historyStore: historyStore
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
            settingsStore: store,
            historyStore: historyStore
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
            settingsStore: store,
            historyStore: historyStore
        )
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["codex", "claude"])
    }

    func test_setProviderEnabled_false_removesFromStatesImmediately() {
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            historyStore: historyStore
        )
        vm.setProviderEnabled(false, id: "codex")
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude"])
    }

    func test_setProviderEnabled_persistsAcrossViewModelInstances() {
        let store = ProviderSettingsStore(defaults: defaults)
        let vm1 = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: store,
            historyStore: historyStore
        )
        vm1.setProviderEnabled(false, id: "codex")

        let vm2 = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            historyStore: historyStore
        )
        XCTAssertEqual(vm2.states.map(\.descriptor.id), ["claude"])
    }

    func test_moveProviderUp_reordersStatesAndPersists() {
        let store = ProviderSettingsStore(defaults: defaults)
        let vm = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: store,
            historyStore: historyStore
        )
        vm.moveProviderUp(id: "codex")
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["codex", "claude"])

        let vm2 = LimitsViewModel(
            providers: [StubProvider(id: "claude"), StubProvider(id: "codex")],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            historyStore: historyStore
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
            settingsStore: store,
            historyStore: historyStore
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
            settingsStore: store,
            historyStore: historyStore
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
            settingsStore: store,
            historyStore: historyStore
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

/// Изменяемый флаг доступности для `DynamicProviderSpec.isAvailable` (@Sendable-замыкание).
private final class AvailabilityFlag: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

/// gh #27: динамическая регистрация провайдера по внешнему условию доступности
/// (у Kimi — появление/удаление файла credentials) без перезапуска приложения.
@MainActor
final class LimitsViewModelDynamicProvidersTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "LimitsViewModelDynamicProvidersTests"
    private var historyStore: HistoryStore!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        historyStore = HistoryStore(directory: tempDirectory)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        historyStore = nil
        super.tearDown()
    }

    private func kimiSpec(_ flag: AvailabilityFlag) -> DynamicProviderSpec {
        DynamicProviderSpec(
            id: "kimi",
            isAvailable: { flag.value },
            makeProvider: { StubProvider(id: "kimi") }
        )
    }

    private func makeVM(flag: AvailabilityFlag, providers: [any LimitsProvider]? = nil) -> LimitsViewModel {
        LimitsViewModel(
            providers: providers ?? [StubProvider(id: "claude")],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            historyStore: historyStore,
            dynamicProviders: [kimiSpec(flag)]
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2, _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func test_dynamicProvider_appearsAfterRefresh_whenCredentialsAppear() async {
        let flag = AvailabilityFlag(false)
        let vm = makeVM(flag: flag)
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude"])

        flag.value = true
        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude", "kimi"])
        XCTAssertEqual(vm.providerSettings.map(\.id), ["claude", "kimi"])
    }

    func test_dynamicProvider_disappearsAfterRefresh_whenCredentialsRemoved() async {
        let flag = AvailabilityFlag(true)
        let vm = makeVM(flag: flag)
        vm.refresh()
        await waitUntil { !vm.isRefreshing }
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude", "kimi"])

        flag.value = false
        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude"])
        // Запись kimi в настройках СОХРАНЯЕТСЯ при отсутствии провайдера
        // (union с id спек) — иначе чужой save затирал бы её persisted-копию.
        XCTAssertEqual(vm.providerSettings.map(\.id), ["claude", "kimi"])
    }

    /// При появлении динамического провайдера снапшоты остальных не сбрасываются
    /// в nil (тот же контракт, что у applyProviderSettingsChange).
    func test_dynamicProvider_reconcile_preservesExistingSnapshots() async {
        let gate = FetchGate(isOpen: true)
        let flag = AvailabilityFlag(false)
        let vm = makeVM(flag: flag, providers: [GatedProvider(id: "claude", gate: gate)])
        vm.refresh()
        await waitUntil { !vm.isRefreshing }
        XCTAssertNotNil(vm.states.first?.snapshot)

        // claude подвисает на gate, kimi появляется — до завершения fetch у claude
        // должен остаться прежний снапшот, у kimi — nil.
        await gate.close()
        flag.value = true
        vm.refresh()
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude", "kimi"])
        XCTAssertNotNil(vm.states[0].snapshot, "снапшот claude не должен сбрасываться при reconcile")
        XCTAssertNil(vm.states[1].snapshot, "новый провайдер ждёт ближайшего завершённого fetch")

        await gate.open()
        await waitUntil { !vm.isRefreshing }
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude", "kimi"])
    }

    /// Спек не должен дублировать провайдера, уже присутствующего в статическом
    /// списке (приложение получает Kimi и от makeDefault, и от spec).
    func test_dynamicProvider_doesNotDuplicate_staticallyPresentProvider() async {
        let flag = AvailabilityFlag(true)
        let vm = makeVM(flag: flag, providers: [StubProvider(id: "claude"), StubProvider(id: "kimi")])
        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude", "kimi"])
    }

    /// Reconcile не сохраняет настройки: выключенность/позиция, выставленные
    /// пользователем, переживают цикл «пропал → появился».
    func test_dynamicProvider_reappear_keepsUserDisabledSetting() async {
        let flag = AvailabilityFlag(true)
        let vm = makeVM(flag: flag)
        vm.refresh()
        await waitUntil { !vm.isRefreshing }
        vm.setProviderEnabled(false, id: "kimi")
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude"])

        flag.value = false
        vm.refresh()
        await waitUntil { !vm.isRefreshing }
        flag.value = true
        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        let kimi = vm.providerSettings.first { $0.id == "kimi" }
        XCTAssertEqual(kimi?.isEnabled, false, "выключенность kimi должна пережить цикл пропал/появился")
        XCTAssertEqual(vm.states.map(\.descriptor.id), ["claude"],
                       "выключенный пользователем провайдер не возвращается в states сам")
    }

    /// Регрессия (ревью B1): пока провайдер отсутствует, изменение настроек
    /// ДРУГОГО провайдера не должно стирать его persisted-запись — save
    /// пишет порядок/выключенность целиком, и без union-записи kimi при
    /// возвращении появлялся бы в конце включённым.
    func test_dynamicProvider_settingsChangeWhileAbsent_preservesPersistedEntry() async {
        let flag = AvailabilityFlag(true)
        let vm = makeVM(flag: flag, providers: [StubProvider(id: "claude"), StubProvider(id: "codex")])
        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        vm.setProviderEnabled(false, id: "kimi")
        vm.moveProviderUp(id: "kimi")
        vm.moveProviderUp(id: "kimi")
        XCTAssertEqual(vm.providerSettings.map(\.id), ["kimi", "claude", "codex"])

        flag.value = false
        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        vm.setProviderEnabled(false, id: "codex")

        flag.value = true
        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        let kimi = vm.providerSettings.first { $0.id == "kimi" }
        XCTAssertEqual(kimi?.isEnabled, false, "выключенность kimi должна пережить чужой save, пока его не было")
        XCTAssertEqual(vm.providerSettings.map(\.id), ["kimi", "claude", "codex"],
                       "позиция kimi должна пережить чужой save, пока его не было")
    }
}

// MARK: - lastGoodSnapshot

/// Провайдер-заглушка, чей снапшот можно менять между вызовами `refresh()`.
private actor MutableStubProvider: LimitsProvider {
    let descriptor: ProviderDescriptor
    var snapshot: LimitsSnapshot

    init(id: String, snapshot: LimitsSnapshot) {
        descriptor = ProviderDescriptor(id: id, displayName: id, shortName: id,
                                        menuBarSymbol: String(id.prefix(1)).uppercased(),
                                        accentColorHex: 0, loginHelp: nil)
        self.snapshot = snapshot
    }

    func fetch() async -> LimitsSnapshot { snapshot }

    func setSnapshot(_ snapshot: LimitsSnapshot) { self.snapshot = snapshot }
}

@MainActor
final class LimitsViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "LimitsViewModelLastGoodSnapshotTests"
    private let fixedDate = Date(timeIntervalSince1970: 3_000_000)
    private var historyStore: HistoryStore!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        historyStore = HistoryStore(directory: tempDirectory)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        historyStore = nil
        super.tearDown()
    }

    private func waitUntil(
        timeout: TimeInterval = 2, _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func goodSnapshot(plan: String, windows: [SnapshotWindow]) -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: true, plan: plan, windows: windows, creditsBalance: nil,
            rateLimitReachedType: nil, details: [], daysUntilRenewal: nil,
            renewalDate: nil, usageError: nil, providerError: nil, fetchedAt: fixedDate
        )
    }

    private func badSnapshot(providerError: String) -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: true, plan: nil, windows: nil, creditsBalance: nil,
            rateLimitReachedType: nil, details: [], daysUntilRenewal: nil,
            renewalDate: nil, usageError: nil, providerError: providerError,
            fetchedAt: fixedDate.addingTimeInterval(1)
        )
    }

    /// a. успех→ошибка: state.snapshot — failed, lastGoodSnapshot — прежний успешный.
    func test_successThenError_keepsLastGoodSnapshot() async {
        let good = goodSnapshot(
            plan: "max",
            windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: 50, resetsAt: nil)]
        )
        let provider = MutableStubProvider(id: "claude", snapshot: good)
        let vm = LimitsViewModel(
            providers: [provider],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            historyStore: historyStore
        )

        vm.refresh()
        await waitUntil { !vm.isRefreshing }
        XCTAssertEqual(vm.states.first?.snapshot, good)
        XCTAssertEqual(vm.states.first?.lastGoodSnapshot, good)

        let bad = badSnapshot(providerError: "network down")
        await provider.setSnapshot(bad)
        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        XCTAssertEqual(vm.states.first?.snapshot, bad)
        XCTAssertEqual(vm.states.first?.lastGoodSnapshot, good,
                       "lastGoodSnapshot должен сохранить прежний успешный снапшот")
    }

    /// b. первая загрузка сразу с ошибкой: lastGoodSnapshot == nil.
    func test_firstLoadError_hasNoLastGoodSnapshot() async {
        let bad = badSnapshot(providerError: "auth.json missing")
        let provider = MutableStubProvider(id: "claude", snapshot: bad)
        let vm = LimitsViewModel(
            providers: [provider],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            historyStore: historyStore
        )

        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        XCTAssertEqual(vm.states.first?.snapshot, bad)
        XCTAssertNil(vm.states.first?.lastGoodSnapshot,
                     "при первой загрузке с ошибкой lastGoodSnapshot должен быть nil")
    }

    /// c. ошибка→успех: lastGoodSnapshot обновился новым успешным, snapshot свежий.
    func test_errorThenSuccess_updatesLastGoodSnapshot() async {
        let bad = badSnapshot(providerError: "network down")
        let provider = MutableStubProvider(id: "claude", snapshot: bad)
        let vm = LimitsViewModel(
            providers: [provider],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            historyStore: historyStore
        )

        vm.refresh()
        await waitUntil { !vm.isRefreshing }
        XCTAssertNil(vm.states.first?.lastGoodSnapshot)

        let good = goodSnapshot(
            plan: "pro",
            windows: [
                SnapshotWindow(windowDurationMins: 300, usedPercent: 10, resetsAt: nil),
                SnapshotWindow(windowDurationMins: 10080, usedPercent: 20, resetsAt: nil)
            ]
        )
        await provider.setSnapshot(good)
        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        XCTAssertEqual(vm.states.first?.snapshot, good)
        XCTAssertEqual(vm.states.first?.lastGoodSnapshot, good,
                       "lastGoodSnapshot должен обновиться новым успешным снапшотом")
    }

    /// d. disable/enable провайдера (setProviderEnabled): lastGoodSnapshot сохраняется.
    func test_disableEnableProvider_preservesLastGoodSnapshot() async {
        let good = goodSnapshot(
            plan: "max",
            windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: 50, resetsAt: nil)]
        )
        let provider = MutableStubProvider(id: "claude", snapshot: good)
        let vm = LimitsViewModel(
            providers: [provider],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            historyStore: historyStore
        )

        vm.refresh()
        await waitUntil { !vm.isRefreshing }
        XCTAssertEqual(vm.states.first?.lastGoodSnapshot, good)

        await provider.setSnapshot(badSnapshot(providerError: "boom"))

        vm.setProviderEnabled(false, id: "claude")
        XCTAssertTrue(vm.states.isEmpty, "выключенный провайдер должен пропасть из states")

        vm.setProviderEnabled(true, id: "claude")
        XCTAssertEqual(vm.states.first?.lastGoodSnapshot, good,
                       "lastGoodSnapshot должен пережить disable/enable")
    }

    /// e. statusTooltip при stale содержит план/окна из last-good.
    func test_statusTooltip_whenStale_showsLastGoodPlanAndWindows() async {
        let good = goodSnapshot(
            plan: "max",
            windows: [
                SnapshotWindow(windowDurationMins: 300, usedPercent: 50, resetsAt: nil),
                SnapshotWindow(windowDurationMins: 10080, usedPercent: 80, resetsAt: nil)
            ]
        )
        let provider = MutableStubProvider(id: "claude", snapshot: good)
        let vm = LimitsViewModel(
            providers: [provider],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            historyStore: historyStore
        )

        vm.refresh()
        await waitUntil { !vm.isRefreshing }
        let freshTooltip = vm.statusTooltip
        XCTAssertTrue(freshTooltip.contains("Max"), "tooltip должен содержать план из свежего снапшота")

        await provider.setSnapshot(badSnapshot(providerError: "network down"))
        vm.refresh()
        await waitUntil { !vm.isRefreshing }

        let staleTooltip = vm.statusTooltip
        XCTAssertTrue(staleTooltip.contains("Max"),
                       "stale tooltip должен показывать план из lastGoodSnapshot, а не '?'")
        XCTAssertTrue(staleTooltip.contains("5h 50%"),
                       "stale tooltip должен показывать 5h-окно из lastGoodSnapshot")
        XCTAssertTrue(staleTooltip.contains("weekly 20%"),
                       "stale tooltip должен показывать weekly-окно из lastGoodSnapshot")
        XCTAssertFalse(staleTooltip.contains(": ?"),
                       "stale tooltip не должен сваливаться в '?'")
    }
}
