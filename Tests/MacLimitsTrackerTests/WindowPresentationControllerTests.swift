import XCTest
@testable import MacLimitsTrackerCore

/// WindowPresentationController — гибридная активация окна (bd mac-limits-tracker-3ip.4):
/// сцены приложения остаются menu-bar-only, но при показе singleton desktop window
/// процесс продвигается в `.regular` (Dock/Cmd-Tab/Window menu), а при закрытии
/// возвращается в `.accessory` (background-only). Policy применяется через
/// инжектируемое замыкание, чтобы контроллер был пригоден для юнит-тестов
/// без поднятия NSApp.
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

    func test_initialState_isNotPresentedAndPolicyNotApplied() {
        XCTAssertFalse(controller.isMainWindowPresented)
        XCTAssertTrue(
            recordedPolicies.isEmpty,
            "Constructor не должен ничего применять, пока не вызван ensureAccessoryOnLaunch"
        )
    }

    func test_ensureAccessoryOnLaunch_appliesAccessory() {
        controller.ensureAccessoryOnLaunch()
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

    func test_lifecycle_openCloseOpen_appliesRegularAccessoryRegular() {
        controller.ensureAccessoryOnLaunch()
        controller.setMainWindowPresented(true)
        controller.setMainWindowPresented(false)
        controller.setMainWindowPresented(true)
        XCTAssertEqual(recordedPolicies, [.accessory, .regular, .accessory, .regular])
    }

    // MARK: - Settings window (bd mac-limits-tracker-3ip.5)
    // Нативная Settings scene — второе окно, идущее через тот же контроллер:
    // эффективная политика = .regular, пока открыто хотя бы одно окно
    // (main ИЛИ settings), и .accessory только когда закрыты оба.

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
}
