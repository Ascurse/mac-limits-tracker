import XCTest
@testable import MacLimitsTrackerCore

/// AppSettingsStore — персистентность настроек приложения (интервал, пороги,
/// уведомления) рядом с ключами @AppStorage (issue #24/#25/#29).
final class AppSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "AppSettingsStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_noSavedValue_refreshIntervalDefaultsTo5min() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.refreshInterval, .minute5)
    }

    func test_refreshInterval_roundTripsAcrossStoreInstances() {
        AppSettingsStore(defaults: defaults).refreshInterval = .seconds30
        XCTAssertEqual(AppSettingsStore(defaults: defaults).refreshInterval, .seconds30)
    }

    func test_unknownSavedRawValue_fallsBackToDefault() {
        defaults.set("fortnightly", forKey: "autoRefreshInterval")
        XCTAssertEqual(AppSettingsStore(defaults: defaults).refreshInterval, .minute5)
    }

    func test_noSavedValue_severityThresholdsDefaultToStandard() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.severityThresholds, .standard)
    }

    func test_severityThresholds_roundTripAcrossStoreInstances() {
        let custom = SeverityThresholds(warningRemaining: 50, criticalRemaining: 10)
        AppSettingsStore(defaults: defaults).severityThresholds = custom
        XCTAssertEqual(AppSettingsStore(defaults: defaults).severityThresholds, custom)
    }

    func test_noSavedValue_notificationsDefaultToDisabled() {
        XCTAssertFalse(AppSettingsStore(defaults: defaults).notificationsEnabled)
    }

    func test_notificationsEnabled_roundTrips() {
        AppSettingsStore(defaults: defaults).notificationsEnabled = true
        XCTAssertTrue(AppSettingsStore(defaults: defaults).notificationsEnabled)
    }

    // MARK: - AppTheme

    func test_noSavedValue_appThemeDefaultsToSystem() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.appTheme, .system)
    }

    func test_appTheme_roundTripsAcrossStoreInstances() {
        AppSettingsStore(defaults: defaults).appTheme = .terminal
        XCTAssertEqual(AppSettingsStore(defaults: defaults).appTheme, .terminal)
    }

    func test_unknownSavedRawValue_appThemeFallsBackToSystem() {
        defaults.set("quantum", forKey: "appTheme")
        XCTAssertEqual(AppSettingsStore(defaults: defaults).appTheme, .system)
    }

    // MARK: - MenuBarDisplayMode

    func test_noSavedValue_menuBarDisplayModeDefaultsToIconAndText() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.menuBarDisplayMode, .iconAndText)
    }

    func test_menuBarDisplayMode_roundTripsAcrossStoreInstances() {
        AppSettingsStore(defaults: defaults).menuBarDisplayMode = .iconOnly
        XCTAssertEqual(AppSettingsStore(defaults: defaults).menuBarDisplayMode, .iconOnly)
    }

    func test_unknownSavedRawValue_menuBarDisplayModeFallsBackToDefault() {
        defaults.set("holographic", forKey: "menuBarDisplayMode")
        XCTAssertEqual(AppSettingsStore(defaults: defaults).menuBarDisplayMode, .iconAndText)
    }

    // MARK: - ShowDesktopWidget

    func test_noSavedValue_showDesktopWidgetDefaultsToFalse() {
        XCTAssertFalse(AppSettingsStore(defaults: defaults).showDesktopWidget)
    }

    func test_showDesktopWidget_roundTrips() {
        AppSettingsStore(defaults: defaults).showDesktopWidget = true
        XCTAssertTrue(AppSettingsStore(defaults: defaults).showDesktopWidget)
    }

    // MARK: - AutoRefreshEnabled

    func test_noSavedValue_autoRefreshEnabledDefaultsToTrue() {
        XCTAssertTrue(AppSettingsStore(defaults: defaults).autoRefreshEnabled)
    }

    func test_autoRefreshEnabled_roundTrips() {
        AppSettingsStore(defaults: defaults).autoRefreshEnabled = false
        XCTAssertFalse(AppSettingsStore(defaults: defaults).autoRefreshEnabled)
    }

    func test_storedFalseAutoRefreshEnabled_doesNotFallBackToTrue() {
        defaults.set(false, forKey: "autoRefreshEnabled")
        XCTAssertFalse(AppSettingsStore(defaults: defaults).autoRefreshEnabled)
    }

    // MARK: - ShowUsageTrends (bd mac-limits-tracker-gld.4)

    func test_noSavedValue_showUsageTrendsDefaultsToTrue() {
        XCTAssertTrue(AppSettingsStore(defaults: defaults).showUsageTrends)
    }

    func test_showUsageTrends_roundTripsAcrossStoreInstances() {
        AppSettingsStore(defaults: defaults).showUsageTrends = false
        XCTAssertFalse(AppSettingsStore(defaults: defaults).showUsageTrends)
    }

    func test_storedFalseShowUsageTrends_doesNotFallBackToTrue() {
        defaults.set(false, forKey: "showUsageTrends")
        XCTAssertFalse(AppSettingsStore(defaults: defaults).showUsageTrends)
    }

    func test_noSavedValue_showDailyBudgetDefaultsToTrue() {
        XCTAssertTrue(AppSettingsStore(defaults: defaults).showDailyBudget)
    }

    func test_showDailyBudget_roundTripsAcrossStoreInstances() {
        AppSettingsStore(defaults: defaults).showDailyBudget = false
        XCTAssertFalse(AppSettingsStore(defaults: defaults).showDailyBudget)

        AppSettingsStore(defaults: defaults).showDailyBudget = true
        XCTAssertTrue(AppSettingsStore(defaults: defaults).showDailyBudget)
    }

    func test_storedFalseShowDailyBudget_doesNotFallBackToTrue() {
        defaults.set(false, forKey: "showDailyBudget")
        XCTAssertFalse(AppSettingsStore(defaults: defaults).showDailyBudget)
    }
}

/// LimitsViewModel + AppSettingsStore: интервал читается из настроек и
/// персистится при изменении (issue #24).
@MainActor
final class LimitsViewModelRefreshIntervalTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "LimitsViewModelRefreshIntervalTests"
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

    private func makeVM() -> LimitsViewModel {
        LimitsViewModel(
            providers: [StubProvider(id: "claude")],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            appSettingsStore: AppSettingsStore(defaults: defaults),
            historyStore: historyStore
        )
    }

    func test_noSavedInterval_defaultsTo5min() {
        XCTAssertEqual(makeVM().autoRefreshInterval, .minute5)
    }

    func test_savedInterval_isLoadedOnInit() {
        AppSettingsStore(defaults: defaults).refreshInterval = .minute15
        XCTAssertEqual(makeVM().autoRefreshInterval, .minute15)
    }

    func test_setAutoRefreshInterval_updatesPublishedValue() {
        let vm = makeVM()
        vm.setAutoRefreshInterval(.seconds30)
        XCTAssertEqual(vm.autoRefreshInterval, .seconds30)
    }

    func test_setAutoRefreshInterval_persistsAcrossViewModelInstances() {
        makeVM().setAutoRefreshInterval(.minute1)
        XCTAssertEqual(makeVM().autoRefreshInterval, .minute1)
    }
}

/// LimitsViewModel + пороги severity: читаются из настроек и персистятся (issue #25).
@MainActor
final class LimitsViewModelSeverityThresholdsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "LimitsViewModelSeverityThresholdsTests"
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

    private func makeVM() -> LimitsViewModel {
        LimitsViewModel(
            providers: [StubProvider(id: "claude")],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            appSettingsStore: AppSettingsStore(defaults: defaults),
            historyStore: historyStore
        )
    }

    func test_noSavedThresholds_defaultToStandard() {
        XCTAssertEqual(makeVM().severityThresholds, .standard)
    }

    func test_savedThresholds_areLoadedOnInit() {
        AppSettingsStore(defaults: defaults).severityThresholds =
            SeverityThresholds(warningRemaining: 60, criticalRemaining: 30)
        XCTAssertEqual(makeVM().severityThresholds,
                       SeverityThresholds(warningRemaining: 60, criticalRemaining: 30))
    }

    func test_setSeverityThresholds_persistsAcrossViewModelInstances() {
        makeVM().setSeverityThresholds(SeverityThresholds(warningRemaining: 50, criticalRemaining: 10))
        XCTAssertEqual(makeVM().severityThresholds,
                       SeverityThresholds(warningRemaining: 50, criticalRemaining: 10))
    }
}

/// Счётчик количества вызовов fetch(). NSLock — читается синхронно из
/// MainActor-замыканий waitUntil, пишется из fetch-задач на global executor.
private final class _FetchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
    func increment() { lock.lock(); defer { lock.unlock() }; _value += 1 }
}

/// Провайдер, чей fetch() инкрементирует счётчик.
private struct _CountingProvider: LimitsProvider {
    let descriptor: ProviderDescriptor
    let counter: _FetchCounter
    let snapshot: LimitsSnapshot = StubProvider.emptySnapshot

    init(id: String, counter: _FetchCounter) {
        descriptor = ProviderDescriptor(id: id, displayName: id, shortName: id,
                                        menuBarSymbol: String(id.prefix(1)).uppercased(),
                                        accentColorHex: 0, loginHelp: nil)
        self.counter = counter
    }

    func fetch() async -> LimitsSnapshot {
        counter.increment()
        return snapshot
    }
}

/// LimitsViewModel + display-сеттинги: appTheme, menuBarDisplayMode,
/// showDesktopWidget проекции на AppSettingsStore; autoRefresh мигрирован
/// на store-бэкенд.
@MainActor
final class LimitsViewModelDisplaySettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "LimitsViewModelDisplaySettingsTests"
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

    private func makeVM() -> LimitsViewModel {
        LimitsViewModel(
            providers: [StubProvider(id: "claude")],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            appSettingsStore: AppSettingsStore(defaults: defaults),
            historyStore: historyStore
        )
    }

    // MARK: - appTheme

    func test_noSavedTheme_viewModelDefaultsToSystem() {
        XCTAssertEqual(makeVM().appTheme, .system)
    }

    func test_savedTheme_isLoadedOnInit() {
        AppSettingsStore(defaults: defaults).appTheme = .terminal
        XCTAssertEqual(makeVM().appTheme, .terminal)
    }

    func test_setAppTheme_updatesPublishedValue() {
        let vm = makeVM()
        vm.setAppTheme(.phosphor)
        XCTAssertEqual(vm.appTheme, .phosphor)
    }

    func test_setAppTheme_persistsAcrossViewModelInstances() {
        makeVM().setAppTheme(.tui)
        XCTAssertEqual(makeVM().appTheme, .tui)
    }

    // MARK: - menuBarDisplayMode

    func test_savedMenuBarDisplayMode_isLoadedOnInit() {
        AppSettingsStore(defaults: defaults).menuBarDisplayMode = .iconOnly
        XCTAssertEqual(makeVM().menuBarDisplayMode, .iconOnly)
    }

    func test_setMenuBarDisplayMode_persistsAcrossViewModelInstances() {
        makeVM().setMenuBarDisplayMode(.iconOnly)
        XCTAssertEqual(makeVM().menuBarDisplayMode, .iconOnly)
    }

    // MARK: - showDesktopWidget

    func test_savedShowDesktopWidget_isLoadedOnInit() {
        AppSettingsStore(defaults: defaults).showDesktopWidget = true
        XCTAssertTrue(makeVM().showDesktopWidget)
    }

    func test_setShowDesktopWidget_persistsAcrossViewModelInstances() {
        makeVM().setShowDesktopWidget(true)
        XCTAssertTrue(makeVM().showDesktopWidget)
    }

    // MARK: - showUsageTrends

    func test_noSavedShowUsageTrends_viewModelDefaultsToTrue() {
        XCTAssertTrue(makeVM().showUsageTrends)
    }

    func test_savedShowUsageTrends_isLoadedOnInit() {
        AppSettingsStore(defaults: defaults).showUsageTrends = false
        XCTAssertFalse(makeVM().showUsageTrends)
    }

    func test_setShowUsageTrends_updatesPublishedValue() {
        let vm = makeVM()
        vm.setShowUsageTrends(false)
        XCTAssertFalse(vm.showUsageTrends)
    }

    func test_setShowUsageTrends_persistsAcrossViewModelInstances() {
        makeVM().setShowUsageTrends(false)
        XCTAssertFalse(makeVM().showUsageTrends)
        XCTAssertFalse(AppSettingsStore(defaults: defaults).showUsageTrends)
    }

    /// Чисто presentation-переключатель: смена настройки не должна дёргать
    /// сеть (refresh) — states и счётчик fetch() остаются нетронутыми.
    func test_setShowUsageTrends_doesNotTriggerRefresh() {
        let counter = _FetchCounter()
        let vm = LimitsViewModel(
            providers: [_CountingProvider(id: "test", counter: counter)],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            appSettingsStore: AppSettingsStore(defaults: defaults),
            historyStore: historyStore
        )
        vm.setShowUsageTrends(false)
        XCTAssertEqual(counter.value, 0)
    }

    func test_noSavedShowDailyBudget_viewModelDefaultsToTrue() {
        XCTAssertTrue(makeVM().showDailyBudget)
    }

    func test_savedShowDailyBudget_isLoadedOnInit() {
        AppSettingsStore(defaults: defaults).showDailyBudget = false
        XCTAssertFalse(makeVM().showDailyBudget)
    }

    func test_setShowDailyBudget_updatesPublishedValueAndPersists() {
        let vm = makeVM()

        vm.setShowDailyBudget(false)
        XCTAssertFalse(vm.showDailyBudget)
        XCTAssertFalse(AppSettingsStore(defaults: defaults).showDailyBudget)

        vm.setShowDailyBudget(true)
        XCTAssertTrue(vm.showDailyBudget)
        XCTAssertTrue(AppSettingsStore(defaults: defaults).showDailyBudget)
    }

    func test_setShowDailyBudget_doesNotTriggerRefresh() {
        let counter = _FetchCounter()
        let vm = LimitsViewModel(
            providers: [_CountingProvider(id: "test", counter: counter)],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            appSettingsStore: AppSettingsStore(defaults: defaults),
            historyStore: historyStore
        )

        vm.setShowDailyBudget(false)
        XCTAssertEqual(counter.value, 0)
    }

    // MARK: - autoRefresh

    func test_noSavedAutoRefresh_defaultsToTrue() {
        XCTAssertTrue(makeVM().autoRefresh)
    }

    func test_savedAutoRefreshDisabled_isLoadedOnInit() {
        AppSettingsStore(defaults: defaults).autoRefreshEnabled = false
        XCTAssertFalse(makeVM().autoRefresh)
    }

    func test_setAutoRefresh_persistsAcrossViewModelInstances() {
        makeVM().setAutoRefresh(false)
        XCTAssertFalse(makeVM().autoRefresh)
        XCTAssertFalse(AppSettingsStore(defaults: defaults).autoRefreshEnabled)
    }

    /// PIN: persistence в setAutoRefresh не должен ломать остановку таймера.
    func test_setAutoRefreshFalse_stillStopsTimer() {
        let counter = _FetchCounter()
        let vm = LimitsViewModel(
            providers: [_CountingProvider(id: "test", counter: counter)],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            appSettingsStore: AppSettingsStore(defaults: defaults),
            historyStore: historyStore
        )
        vm.start()
        vm.setAutoRefresh(false)
        XCTAssertFalse(vm.autoRefresh)
        XCTAssertFalse(AppSettingsStore(defaults: defaults).autoRefreshEnabled)
        vm.startTimer()
        let exp = XCTestExpectation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(counter.value, 1,
                       "setAutoRefresh(false) должен остановить таймер; дополнительный refresh не ожидается")
    }
}
