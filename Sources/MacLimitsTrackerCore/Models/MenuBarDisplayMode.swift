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

    public func menuBarText(claude: ClaudeStatus?, codex: CodexStatus?) -> String? {
        guard showsText else { return nil }

        let claudePlan = claude?.subscriptionType?.capitalized ?? claude?.menuTitle.replacingOccurrences(of: "Claude: ", with: "") ?? "Claude"
        let codexPlan = codex?.planType?.capitalized ?? codex?.menuTitle.replacingOccurrences(of: "Codex: ", with: "") ?? "Codex"

        switch self {
        case .iconAndText:
            return "Claude: \(claudePlan) · Codex: \(codexPlan)"

        case .iconAnd5h:
            let c = Self.formatRemaining(claude?.usage?.fiveHour?.utilizationPercent)
            let x = Self.formatRemaining(nil)
            return "C \(c) · X \(x)"

        case .iconAnd5hWeekly:
            let c5 = Self.formatRemaining(claude?.usage?.fiveHour?.utilizationPercent)
            let cW = Self.formatRemaining(claude?.usage?.sevenDay?.utilizationPercent)
            let x5 = Self.formatRemaining(nil)
            let xW = Self.formatRemaining(nil)
            return "C 5h \(c5) / \(cW) · X 5h \(x5) / \(xW)"

        case .iconOnly:
            return nil
        }
    }

    private static func formatRemaining(_ utilizationPercent: Double?) -> String {
        guard let p = utilizationPercent else { return "—" }
        return String(format: "%.0f%%", max(0, 100 - p))
    }
}
