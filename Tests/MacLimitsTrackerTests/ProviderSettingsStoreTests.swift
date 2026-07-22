import XCTest
@testable import MacLimitsTrackerCore

final class ProviderSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "ProviderSettingsStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_noSavedSettings_defaultsToAllEnabledInGivenOrder() {
        let store = ProviderSettingsStore(defaults: defaults)
        let settings = store.settings(for: ["claude", "codex"])
        XCTAssertEqual(settings, [
            ProviderSetting(id: "claude", isEnabled: true),
            ProviderSetting(id: "codex", isEnabled: true)
        ])
    }

    func test_savedSettings_surviveRestart_asNewStoreInstance() {
        let first = ProviderSettingsStore(defaults: defaults)
        first.save([
            ProviderSetting(id: "codex", isEnabled: true),
            ProviderSetting(id: "claude", isEnabled: false)
        ])

        let second = ProviderSettingsStore(defaults: defaults)
        let settings = second.settings(for: ["claude", "codex"])
        XCTAssertEqual(settings, [
            ProviderSetting(id: "codex", isEnabled: true),
            ProviderSetting(id: "claude", isEnabled: false)
        ])
    }

    func test_newProviderNotInSavedOrder_isAppendedAtEndEnabled() {
        let store = ProviderSettingsStore(defaults: defaults)
        store.save([ProviderSetting(id: "claude", isEnabled: true)])

        let settings = store.settings(for: ["claude", "codex", "kimi"])
        XCTAssertEqual(settings, [
            ProviderSetting(id: "claude", isEnabled: true),
            ProviderSetting(id: "codex", isEnabled: true),
            ProviderSetting(id: "kimi", isEnabled: true)
        ])
    }

    func test_unknownSavedId_isSilentlyIgnored() {
        let store = ProviderSettingsStore(defaults: defaults)
        store.save([
            ProviderSetting(id: "claude", isEnabled: true),
            ProviderSetting(id: "removedProvider", isEnabled: false)
        ])

        let settings = store.settings(for: ["claude"])
        XCTAssertEqual(settings, [ProviderSetting(id: "claude", isEnabled: true)])
    }
}

/// Чистые функции переупорядочивания/переключения — без UserDefaults.
final class ProviderSettingReorderingTests: XCTestCase {
    private let claude = ProviderSetting(id: "claude", isEnabled: true)
    private let codex = ProviderSetting(id: "codex", isEnabled: true)
    private let kimi = ProviderSetting(id: "kimi", isEnabled: true)

    func test_movedUp_swapsWithPrevious() {
        let settings = [claude, codex, kimi]
        XCTAssertEqual(settings.movedUp(id: "codex"), [codex, claude, kimi])
    }

    func test_movedUp_firstElement_isNoOp() {
        let settings = [claude, codex]
        XCTAssertEqual(settings.movedUp(id: "claude"), settings)
    }

    func test_movedDown_swapsWithNext() {
        let settings = [claude, codex, kimi]
        XCTAssertEqual(settings.movedDown(id: "codex"), [claude, kimi, codex])
    }

    func test_movedDown_lastElement_isNoOp() {
        let settings = [claude, codex]
        XCTAssertEqual(settings.movedDown(id: "codex"), settings)
    }

    func test_movedUp_unknownId_isNoOp() {
        let settings = [claude, codex]
        XCTAssertEqual(settings.movedUp(id: "missing"), settings)
    }

    func test_settingEnabled_togglesOnlyMatchingId() {
        let settings = [claude, codex]
        let updated = settings.settingEnabled(id: "codex", isEnabled: false)
        XCTAssertEqual(updated, [claude, ProviderSetting(id: "codex", isEnabled: false)])
    }
}
