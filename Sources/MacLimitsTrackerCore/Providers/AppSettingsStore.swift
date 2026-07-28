import Foundation

/// Настройки приложения в UserDefaults: интервал автообновления (issue #24),
/// пороги severity (#25), уведомления (#29), тема и режим меню-бара.
/// @AppStorage убран; store владеет и этими ключами
/// (`appTheme`, `menuBarDisplayMode`, `showDesktopWidget`).
/// `defaults` инжектируется для тестируемости — как в ProviderSettingsStore.
public final class AppSettingsStore {
    private let defaults: UserDefaults
    private static let refreshIntervalKey = "autoRefreshInterval"
    private static let warningRemainingKey = "severityThresholds.warningRemaining"
    private static let criticalRemainingKey = "severityThresholds.criticalRemaining"
    private static let notificationsEnabledKey = "notificationsEnabled"
    private static let appThemeKey = "appTheme"
    private static let menuBarDisplayModeKey = "menuBarDisplayMode"
    private static let showDesktopWidgetKey = "showDesktopWidget"
    private static let autoRefreshEnabledKey = "autoRefreshEnabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Неизвестное/отсутствующее значение → дефолт (5 минут).
    public var refreshInterval: RefreshInterval {
        get {
            guard let raw = defaults.string(forKey: Self.refreshIntervalKey),
                  let value = RefreshInterval(rawValue: raw) else { return .default }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Self.refreshIntervalKey) }
    }

    public var severityThresholds: SeverityThresholds {
        get {
            // object(forKey:) вместо double(forKey:): отсутствующий ключ
            // отличим от сохранённого нуля.
            guard let warning = defaults.object(forKey: Self.warningRemainingKey) as? Double,
                  let critical = defaults.object(forKey: Self.criticalRemainingKey) as? Double
            else { return .standard }
            return SeverityThresholds(warningRemaining: warning, criticalRemaining: critical)
        }
        set {
            defaults.set(newValue.warningRemaining, forKey: Self.warningRemainingKey)
            defaults.set(newValue.criticalRemaining, forKey: Self.criticalRemainingKey)
        }
    }

    public var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Self.notificationsEnabledKey) }
        set { defaults.set(newValue, forKey: Self.notificationsEnabledKey) }
    }

    public var appTheme: AppTheme {
        get {
            guard let raw = defaults.string(forKey: Self.appThemeKey),
                  let value = AppTheme(rawValue: raw) else { return .system }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Self.appThemeKey) }
    }

    public var menuBarDisplayMode: MenuBarDisplayMode {
        get {
            guard let raw = defaults.string(forKey: Self.menuBarDisplayModeKey),
                  let value = MenuBarDisplayMode(rawValue: raw) else { return .iconAndText }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Self.menuBarDisplayModeKey) }
    }

    public var showDesktopWidget: Bool {
        get { defaults.bool(forKey: Self.showDesktopWidgetKey) }
        set { defaults.set(newValue, forKey: Self.showDesktopWidgetKey) }
    }

    /// object(forKey:) вместо bool(forKey:): отсутствующий ключ
    /// отличим от сохранённого false.
    public var autoRefreshEnabled: Bool {
        get { defaults.object(forKey: Self.autoRefreshEnabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.autoRefreshEnabledKey) }
    }
}
