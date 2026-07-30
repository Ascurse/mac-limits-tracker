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

    func test_reorderedResult_savedAndReloaded_preservesOrderAndDisabledIds() {
        let store = ProviderSettingsStore(defaults: defaults)
        let initial = store.settings(for: ["claude", "codex", "kimi"])
            .settingEnabled(id: "codex", isEnabled: false)
        let reordered = initial.reordered(ids: ["kimi"], before: "claude")
        store.save(reordered)

        let reloaded = ProviderSettingsStore(defaults: defaults).settings(for: ["claude", "codex", "kimi"])
        XCTAssertEqual(reloaded.map(\.id), ["kimi", "claude", "codex"])
        XCTAssertEqual(reloaded.first { $0.id == "codex" }?.isEnabled, false)
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

/// ID-based примитив перестановки — общая основа для movedUp/movedDown и
/// UI drag-переупорядочивания (bd mac-limits-tracker-med.1).
final class ProviderSettingReorderedTests: XCTestCase {
    private let claude = ProviderSetting(id: "claude", isEnabled: true)
    private let codex = ProviderSetting(id: "codex", isEnabled: false)
    private let kimi = ProviderSetting(id: "kimi", isEnabled: true)
    private let grok = ProviderSetting(id: "grok", isEnabled: true)

    func test_reordered_movesFirstElement_toMiddle() {
        let settings = [claude, codex, kimi]
        let result = settings.reordered(ids: ["claude"], before: "kimi")
        XCTAssertEqual(result.map(\.id), ["codex", "claude", "kimi"])
    }

    func test_reordered_movesMiddleElement_beforeEarlierTarget() {
        let settings = [claude, codex, kimi, grok]
        let result = settings.reordered(ids: ["grok"], before: "codex")
        XCTAssertEqual(result.map(\.id), ["claude", "grok", "codex", "kimi"])
    }

    func test_reordered_movesLastElement_toBeginning() {
        let settings = [claude, codex, kimi]
        let result = settings.reordered(ids: ["kimi"], before: "claude")
        XCTAssertEqual(result.map(\.id), ["kimi", "claude", "codex"])
    }

    func test_reordered_nilTarget_movesToEnd() {
        let settings = [claude, codex, kimi]
        let result = settings.reordered(ids: ["claude"], before: nil)
        XCTAssertEqual(result.map(\.id), ["codex", "kimi", "claude"])
    }

    func test_reordered_unknownTarget_movesToEnd() {
        let settings = [claude, codex, kimi]
        let result = settings.reordered(ids: ["claude"], before: "missing")
        XCTAssertEqual(result.map(\.id), ["codex", "kimi", "claude"])
    }

    func test_reordered_unknownMovingId_isNoOp() {
        let settings = [claude, codex]
        XCTAssertEqual(settings.reordered(ids: ["missing"], before: "codex"), settings)
    }

    func test_reordered_multipleIds_preservesGivenOrder() {
        let settings = [claude, codex, kimi, grok]
        let result = settings.reordered(ids: ["kimi", "claude"], before: "grok")
        XCTAssertEqual(result.map(\.id), ["codex", "kimi", "claude", "grok"])
    }

    func test_reordered_preservesIsEnabled_forMovedAndUntouchedItems() {
        let settings = [claude, codex, kimi]
        let result = settings.reordered(ids: ["codex"], before: "kimi")
        XCTAssertEqual(result.first { $0.id == "codex" }?.isEnabled, false,
                       "выключенность перемещаемого элемента не должна меняться")
        XCTAssertEqual(result.first { $0.id == "claude" }?.isEnabled, true,
                       "выключенность нетронутого элемента не должна меняться")
    }
}
