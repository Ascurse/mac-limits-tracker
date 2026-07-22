import Foundation

/// Тема попапа. rawValue персистится в @AppStorage("appTheme") — значения не менять.
public enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case terminal
    case phosphor
    case tui

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system:   return "System"
        case .terminal: return "Terminal"
        case .phosphor: return "Phosphor"
        case .tui:      return "TUI"
        }
    }
}
