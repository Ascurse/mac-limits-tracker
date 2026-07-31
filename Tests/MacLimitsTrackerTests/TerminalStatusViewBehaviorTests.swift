import SwiftUI
import ViewInspector
import XCTest
@testable import MacLimitsTrackerCore

/// PoC поведенческого теста через ViewInspector (bd mac-limits-tracker-t9e.2).
///
/// CLAUDE.md: «`SnapshotWindow.usedPercent == nil` — слот заявлен, данных нет
/// („… usage unavailable"); билдер и виджет различают „слота нет" и „слот пуст"».
/// Темы (`UI/*StatusView.swift`) рендерят `PopupContentBuilder.section(state:)`;
/// Terminal-тема рендерит `.note(let text)` как `Text(text)`
/// (TerminalOverviewBody.rowView).
///
/// UI-слой лежит в executable target `MacLimitsTracker` и недоступен test target'у,
/// поэтому ViewInspector инспектирует минимальный рендер note-строки, а её контент
/// целиком производственный — из `PopupContentBuilder.section(state:)`.
final class TerminalStatusViewBehaviorTests: XCTestCase {
    private let descriptor = ProviderDescriptor(
        id: "claude", displayName: "Claude Code", shortName: "Claude",
        menuBarSymbol: "C", accentColorHex: 0xFF9E64, loginHelp: nil
    )
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func state(usedPercent: Double?) -> ProviderState {
        let snapshot = LimitsSnapshot(
            loggedIn: true, plan: "max",
            windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: usedPercent, resetsAt: nil)],
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: nil, fetchedAt: now
        )
        return ProviderState(descriptor: descriptor, snapshot: snapshot)
    }

    /// Слот заявлен (окно есть в снапшоте), но данных нет (`usedPercent == nil`)
    /// → рендерится «5h usage unavailable», а не пустой слот и не пропущенная строка.
    func test_nilUsedPercent_rendersUsageUnavailable_notEmptySlot() throws {
        let section = PopupContentBuilder.section(state(usedPercent: nil), now: now)

        // «Слот пуст» ≠ «слота нет»: window-строки (пустого бара) быть не должно,
        // но строка-заглушка обязана присутствовать.
        for row in section.rows {
            if case .window = row {
                XCTFail("пустой слот не должен рендерить window-строку: \(section.rows)")
            }
        }
        guard let noteText = section.rows.compactMap({ row -> String? in
            if case .note(let text) = row { return text }
            return nil
        }).first(where: { $0.contains("usage unavailable") }) else {
            return XCTFail("ожидалась .note-строка с \"usage unavailable\", rows: \(section.rows)")
        }
        XCTAssertEqual(noteText, "5h usage unavailable")

        // ViewInspector: в рендере Terminal-темы note-строка — это Text(text);
        // проверяем, что в дереве находится именно этот непустой текст.
        let sut = TerminalNoteRow(text: noteText)
        let inspected = try sut.inspect().find(text: "5h usage unavailable")
        XCTAssertFalse(try inspected.string().isEmpty)
    }

    /// Контраст: с данными окно рендерится window-строкой с процентами и без
    /// «usage unavailable» — тест выше не «всегда зелёный».
    func test_presentUsedPercent_rendersWindowRow_withoutUnavailableNote() {
        let section = PopupContentBuilder.section(state(usedPercent: 42), now: now)

        let windowTexts = section.rows.compactMap { row -> String? in
            if case .window(let w) = row { return w.remainingText }
            return nil
        }
        XCTAssertEqual(windowTexts, ["58%"])
        XCTAssertFalse(section.rows.contains { row in
            if case .note(let text) = row { return text.contains("usage unavailable") }
            return false
        })
    }
}

/// Минимальный рендер note-строки Terminal-темы: `TerminalOverviewBody.rowView`
/// рендерит `.note(let text)` как `Text(text)` (с dim-стилем).
private struct TerminalNoteRow: View {
    let text: String
    var body: some View { Text(text) }
}

extension TerminalNoteRow: Inspectable {}
