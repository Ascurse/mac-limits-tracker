import XCTest
@testable import MacLimitsTrackerCore

/// WindowPresentationController — активация процесса для двух режимов запуска:
/// `.hybrid` (menu-bar-first, dev/`swift run`) и `.persistentRegular`
/// (полноценное desktop-приложение в `.app`). Policy применяется через
/// инжектируемое замыкание, чтобы контроллер был пригоден для юнит-тестов
/// без поднятия NSApp.
///
/// Нативная Settings scene (bd mac-limits-tracker-3ip.5) — второе окно,
/// идущее через тот же контроллер: эффективная политика = .regular, пока
/// открыто хотя бы одно окно (main ИЛИ settings), и .accessory только
/// когда закрыты оба.
final class WindowPresentationControllerTests: XCTestCase {
    private var recordedPolicies: [WindowPresentationController.ActivationPolicy]!
    private var controller: WindowPresentationController!

    override func setUp() {
        super.setUp()
        recordedPolicies = []
        controller = WindowPresentationController { [weak self] policy in
            self?.recordedPolicies.append(policy)
        }
    }

    override func tearDown() {
        recordedPolicies = nil
        controller = nil
        super.tearDown()
    }

    // MARK: - Hybrid (default)

    func test_initialState_isNotPresentedAndPolicyNotApplied() {
        XCTAssertFalse(controller.isMainWindowPresented)
        XCTAssertFalse(controller.isSettingsWindowPresented)
        XCTAssertTrue(
            recordedPolicies.isEmpty,
            "Constructor не должен ничего применять, пока не вызван applyLaunchPolicy"
        )
    }

    func test_hybrid_applyLaunchPolicy_appliesAccessory() {
        controller.applyLaunchPolicy()
        XCTAssertEqual(recordedPolicies, [.accessory])
    }

    func test_setMainWindowPresentedTrueFromDefault_appliesRegular() {
        controller.setMainWindowPresented(true)
        XCTAssertTrue(controller.isMainWindowPresented)
        XCTAssertEqual(recordedPolicies, [.regular])
    }

    func test_setMainWindowPresentedTrueTwice_appliesOnlyOnce_idempotent() {
        controller.setMainWindowPresented(true)
        controller.setMainWindowPresented(true)
        XCTAssertEqual(recordedPolicies, [.regular])
    }

    func test_setMainWindowPresentedFalseAfterTrue_appliesAccessory() {
        controller.setMainWindowPresented(true)
        controller.setMainWindowPresented(false)
        XCTAssertFalse(controller.isMainWindowPresented)
        XCTAssertEqual(recordedPolicies, [.regular, .accessory])
    }

    func test_setMainWindowPresentedFalseFromDefault_isNoOp() {
        controller.setMainWindowPresented(false)
        XCTAssertTrue(
            recordedPolicies.isEmpty,
            "Default state is already not-presented; no state change — no apply"
        )
    }

    func test_setMainWindowPresentedFalseTwiceAfterOpen_appliesAccessoryOnce() {
        controller.setMainWindowPresented(true)
        controller.setMainWindowPresented(false)
        controller.setMainWindowPresented(false)
        XCTAssertEqual(recordedPolicies, [.regular, .accessory])
    }

    func test_hybrid_lifecycle_openCloseOpen_appliesRegularAccessoryRegular() {
        controller.applyLaunchPolicy()
        controller.setMainWindowPresented(true)
        controller.setMainWindowPresented(false)
        controller.setMainWindowPresented(true)
        XCTAssertEqual(recordedPolicies, [.accessory, .regular, .accessory, .regular])
    }

    // MARK: - Persistent regular

    func test_persistentRegular_applyLaunchPolicy_appliesRegular() {
        controller = WindowPresentationController(
            launchMode: .persistentRegular,
            apply: { [weak self] policy in self?.recordedPolicies.append(policy) }
        )
        controller.applyLaunchPolicy()
        XCTAssertEqual(recordedPolicies, [.regular])
    }

    func test_persistentRegular_windowOpenClose_staysRegular() {
        controller = WindowPresentationController(
            launchMode: .persistentRegular,
            apply: { [weak self] policy in self?.recordedPolicies.append(policy) }
        )
        controller.applyLaunchPolicy()
        controller.setMainWindowPresented(true)
        controller.setMainWindowPresented(false)
        XCTAssertEqual(
            recordedPolicies,
            [.regular],
            "persistentRegular never demotes to accessory; apply deduplicates unchanged policy"
        )
    }

    func test_persistentRegular_settingsOpenClose_staysRegularAndDeduped() {
        controller = WindowPresentationController(
            launchMode: .persistentRegular,
            apply: { [weak self] policy in self?.recordedPolicies.append(policy) }
        )
        controller.applyLaunchPolicy()
        controller.setSettingsWindowPresented(true)
        controller.setSettingsWindowPresented(false)
        XCTAssertEqual(
            recordedPolicies,
            [.regular],
            "persistentRegular never demotes to accessory; settings open/close do not change effective policy"
        )
    }

    // MARK: - Settings window (bd mac-limits-tracker-3ip.5)

    func test_initialState_settingsNotPresented() {
        XCTAssertFalse(controller.isSettingsWindowPresented)
    }

    func test_setSettingsWindowPresentedTrue_appliesRegular() {
        controller.setSettingsWindowPresented(true)
        XCTAssertTrue(controller.isSettingsWindowPresented)
        XCTAssertEqual(recordedPolicies, [.regular])
    }

    func test_setSettingsWindowPresentedTrueTwice_idempotent() {
        controller.setSettingsWindowPresented(true)
        controller.setSettingsWindowPresented(true)
        XCTAssertEqual(recordedPolicies, [.regular])
    }

    func test_settingsOpenThenMainOpenThenSettingsClose_staysRegular() {
        controller.setSettingsWindowPresented(true)
        controller.setMainWindowPresented(true)
        controller.setSettingsWindowPresented(false)
        XCTAssertEqual(
            recordedPolicies, [.regular],
            "Main window всё ещё открыт — понижать политику нельзя"
        )
    }

    func test_bothWindowsCloseInEitherOrder_demotesOnlyAfterLast() {
        controller.setMainWindowPresented(true)
        controller.setSettingsWindowPresented(true)
        controller.setMainWindowPresented(false)
        controller.setSettingsWindowPresented(false)
        XCTAssertEqual(
            recordedPolicies, [.regular, .accessory],
            "Демоут только после закрытия последнего окна"
        )
    }

    func test_setSettingsWindowPresentedFalseFromDefault_isNoOp() {
        controller.setSettingsWindowPresented(false)
        XCTAssertTrue(
            recordedPolicies.isEmpty,
            "Default state is already not-presented; no state change — no apply"
        )
    }

    func test_hybrid_settingsOnlyLifecycle_promotesThenDemotes() {
        controller.applyLaunchPolicy()
        controller.setSettingsWindowPresented(true)
        controller.setSettingsWindowPresented(false)
        XCTAssertEqual(
            recordedPolicies, [.accessory, .regular, .accessory],
            "Открытие settings в hybrid режиме поднимает до regular; закрытие возвращает в accessory"
        )
    }
}
