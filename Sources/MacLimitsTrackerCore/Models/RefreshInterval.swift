import Foundation

/// Интервал автообновления лимитов (issue #24). rawValue персистится в
/// UserDefaults ("autoRefreshInterval") — значения не менять.
public enum RefreshInterval: String, CaseIterable, Identifiable, Sendable {
    case seconds30
    case minute1
    case minute5
    case minute15

    public static let `default`: RefreshInterval = .minute5

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .seconds30: return "30 sec"
        case .minute1:  return "1 min"
        case .minute5:  return "5 min"
        case .minute15: return "15 min"
        }
    }

    public var timeInterval: TimeInterval {
        switch self {
        case .seconds30: return 30
        case .minute1:  return 60
        case .minute5:  return 300
        case .minute15: return 900
        }
    }
}
