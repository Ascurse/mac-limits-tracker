import Foundation

/// Настройки приложения в UserDefaults: интервал автообновления (issue #24),
/// пороги severity (#25), уведомления (#29). Ключи живут рядом с ключами
/// @AppStorage (`appTheme`, `menuBarDisplayMode`) в .standard.
/// `defaults` инжектируется для тестируемости — как в ProviderSettingsStore.
public final class AppSettingsStore {
    private let defaults: UserDefaults
    private static let refreshIntervalKey = "autoRefreshInterval"
    private static let warningRemainingKey = "severityThresholds.warningRemaining"
    private static let criticalRemainingKey = "severityThresholds.criticalRemaining"
    private static let notificationsEnabledKey = "notificationsEnabled"

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
}
