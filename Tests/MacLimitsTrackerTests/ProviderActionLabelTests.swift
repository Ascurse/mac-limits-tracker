import XCTest
@testable import MacLimitsTrackerCore

/// Действие «открыть провайдера» должно объясняться без наведения курсора:
/// у него есть видимая подпись и та же формулировка уходит в VoiceOver
/// (bd mac-limits-tracker-avs).
final class ProviderActionLabelTests: XCTestCase {
    private let help = LoginHelp(helpText: "Open Claude Code to refresh the claude.ai login",
                                 binaryPath: "/usr/local/bin/claude")

    func test_actionTitle_isVisibleVerb() {
        XCTAssertEqual(LoginHelp.actionTitle, "Open")
    }

    func test_accessibilityLabel_namesActionAndProvider() {
        let label = help.accessibilityLabel(providerTitle: "Claude Code")

        XCTAssertTrue(label.contains(LoginHelp.actionTitle),
                      "VoiceOver должен произносить то же действие, что видно глазом: \(label)")
        XCTAssertTrue(label.contains("Claude Code"),
                      "без имени провайдера кнопка неотличима от соседних: \(label)")
    }

    func test_accessibilityLabel_differsPerProvider() {
        XCTAssertNotEqual(help.accessibilityLabel(providerTitle: "Claude Code"),
                          help.accessibilityLabel(providerTitle: "Codex"))
    }

    /// Подпись рядом с иконкой конкурирует за ширину, поэтому она должна быть
    /// короткой — иначе компактный попап всегда сваливается в icon-only.
    func test_actionTitle_staysShortEnoughForCompactHeader() {
        XCTAssertLessThanOrEqual(LoginHelp.actionTitle.count, 8)
    }
}
