import XCTest
@testable import MacLimitsTrackerCore

/// WindowPresentationController — активация процесса для двух режимов запуска:
/// `.hybrid` (menu-bar-first, dev/`swift run`) и `.persistentRegular`
/// (полноценное desktop-приложение в `.app`). Policy применяется через
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

    // MARK: - Hybrid (default)

    func test_initialState_isNotPresentedAndPolicyNotApplied() {
        XCTAssertFalse(controller.isMainWindowPresented)
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
            [.regular, .regular],
            "persistentRegular never demotes to accessory"
        )
    }
}
