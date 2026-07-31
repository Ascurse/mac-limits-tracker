import SnapshotTesting
import XCTest
@testable import MacLimitsTrackerCore

/// PoC текстового snapshot-теста через swift-snapshot-testing (.dump стратегия,
/// bd mac-limits-tracker-t9e.3): дерево контента секции сравнивается как текстовый
/// diff, без пиксельного сравнения.
///
/// Снапшотим 100% производственные данные — `ProviderSectionContent` из
/// `PopupContentBuilder.section(state:)` (именно его рендерит TerminalStatusView
/// через ProviderOverview). Сами view Terminal-темы лежат в executable target
/// `MacLimitsTracker` и недоступны test target'у, поэтому .dump идёт по модели
/// контента: любое изменение структуры/текстов строк в билдере даёт текстовый diff.
///
/// Детерминизм: фиксированный `now`; `resetsAt` везде nil — reset-текст форматируется
/// RelativeDateTimeFormatter'ом и зависел бы от локали тест-раннера.
final class TerminalStatusViewSnapshotTests: XCTestCase {
    private let descriptor = ProviderDescriptor(
        id: "claude", displayName: "Claude Code", shortName: "Claude",
        menuBarSymbol: "C", accentColorHex: 0xFF9E64, loginHelp: nil
    )
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func state(windows: [SnapshotWindow]) -> ProviderState {
        let snapshot = LimitsSnapshot(
            loggedIn: true, plan: "max", windows: windows,
            creditsBalance: nil, rateLimitReachedType: nil,
            details: [SnapshotDetail(key: "Email", value: "a@b.co")],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: nil, fetchedAt: now
        )
        return ProviderState(descriptor: descriptor, snapshot: snapshot)
    }

    private func sample(windowMins: Int, hoursAgo: Double, used: Double) -> UsageSample {
        UsageSample(providerId: "claude", windowMins: windowMins,
                    fetchedAt: now.addingTimeInterval(-hoursAgo * 3600),
                    usedPercent: used, resetsAt: nil)
    }

    /// «Слот пуст»: окно заявлено, `usedPercent == nil` → .note «5h usage unavailable».
    func test_dump_nilUsedPercent_usageUnavailableNote() {
        let section = PopupContentBuilder.section(
            state(windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: nil, resetsAt: nil)]),
            now: now
        )
        assertSnapshot(of: section, as: .dump)
    }

    /// Наполненное состояние: два окна, спарклайн по истории 5h-окна, detail-строка.
    func test_dump_populatedState_windowsSparklineDetails() {
        let section = PopupContentBuilder.section(
            state(windows: [
                SnapshotWindow(windowDurationMins: 300, usedPercent: 42, resetsAt: nil),
                SnapshotWindow(windowDurationMins: 10080, usedPercent: 69, resetsAt: nil),
            ]),
            now: now,
            history: [
                sample(windowMins: 300, hoursAgo: 10, used: 20),
                sample(windowMins: 300, hoursAgo: 5, used: 30),
                sample(windowMins: 300, hoursAgo: 2, used: 40),
            ]
        )
        assertSnapshot(of: section, as: .dump)
    }
}
