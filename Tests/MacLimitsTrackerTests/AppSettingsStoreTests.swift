import XCTest
@testable import MacLimitsTrackerCore

/// RefreshInterval — enum интервалов автообновления (issue #24).
final class RefreshIntervalTests: XCTestCase {
    func test_timeIntervals_matchTitles() {
        XCTAssertEqual(RefreshInterval.seconds30.timeInterval, 30)
        XCTAssertEqual(RefreshInterval.minute1.timeInterval, 60)
        XCTAssertEqual(RefreshInterval.minute5.timeInterval, 300)
        XCTAssertEqual(RefreshInterval.minute15.timeInterval, 900)
    }

    func test_titles_areHumanReadable() {
        XCTAssertEqual(RefreshInterval.seconds30.title, "30 sec")
        XCTAssertEqual(RefreshInterval.minute1.title, "1 min")
        XCTAssertEqual(RefreshInterval.minute5.title, "5 min")
        XCTAssertEqual(RefreshInterval.minute15.title, "15 min")
    }

    /// rawValue персистится в UserDefaults — значения не менять.
    func test_rawValues_areStable() {
        XCTAssertEqual(RefreshInterval.seconds30.rawValue, "seconds30")
        XCTAssertEqual(RefreshInterval.minute5.rawValue, "minute5")
        XCTAssertEqual(RefreshInterval.default, .minute5)
    }
}

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
}

/// LimitsViewModel + AppSettingsStore: интервал читается из настроек и
/// персистится при изменении (issue #24).
@MainActor
final class LimitsViewModelRefreshIntervalTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "LimitsViewModelRefreshIntervalTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeVM() -> LimitsViewModel {
        LimitsViewModel(
            providers: [StubProvider(id: "claude")],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            appSettingsStore: AppSettingsStore(defaults: defaults)
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

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeVM() -> LimitsViewModel {
        LimitsViewModel(
            providers: [StubProvider(id: "claude")],
            settingsStore: ProviderSettingsStore(defaults: defaults),
            appSettingsStore: AppSettingsStore(defaults: defaults)
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
