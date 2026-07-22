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
}
