import Foundation

/// Режим отображения статус-бара: пользователь выбирает, что видно в menu-bar.
public enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconAndText
    case iconOnly
    case iconAnd5h
    case iconAnd5hWeekly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .iconAndText:      return "Icon + Plan"
        case .iconOnly:         return "Icon Only"
        case .iconAnd5h:        return "Icon + 5h %"
        case .iconAnd5hWeekly:  return "Icon + 5h / Weekly %"
        }
    }

    public var showsText: Bool { self != .iconOnly }

    public func menuBarText(states: [ProviderState]) -> String? {
        guard showsText else { return nil }

        switch self {
        case .iconAndText:
            return states.map { "\($0.descriptor.shortName): \(Self.planText(for: $0))" }
                .joined(separator: " · ")

        case .iconAnd5h:
            return states.map { state in
                let w = state.snapshot?.windows?.first { $0.windowDurationMins == 300 }
                return "\(state.descriptor.menuBarSymbol) \(Self.formatRemaining(w?.usedPercent))"
            }.joined(separator: " · ")

        case .iconAnd5hWeekly:
            return states.map { state in
                let w5 = state.snapshot?.windows?.first { $0.windowDurationMins == 300 }
                let wWk = state.snapshot?.windows?.first { $0.windowDurationMins == 10080 }
                let symbol = state.descriptor.menuBarSymbol
                return "\(symbol) 5h \(Self.formatRemaining(w5?.usedPercent)) / \(Self.formatRemaining(wWk?.usedPercent))"
            }.joined(separator: " · ")

        case .iconOnly:
            return nil
        }
    }

    /// Сырой план приоритетнее `menuTitle` (уже live-first для Codex — см. `toSnapshot()`);
    /// при его отсутствии — `menuTitle` без префикса `"{shortName}: "` (учитывает
    /// providerError/loggedIn), иначе просто `shortName`.
    private static func planText(for state: ProviderState) -> String {
        guard let snap = state.snapshot else { return state.descriptor.shortName }
        if let plan = snap.plan, !plan.isEmpty { return plan.capitalized }
        let prefix = "\(state.descriptor.shortName): "
        return snap.menuTitle(shortName: state.descriptor.shortName)
            .replacingOccurrences(of: prefix, with: "")
    }

    private static func formatRemaining(_ usedPercent: Double?) -> String {
        guard let p = usedPercent else { return "—" }
        return String(format: "%.0f%%", max(0, 100 - p))
    }
}
