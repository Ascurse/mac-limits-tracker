import Foundation

/// Источник данных о лимитах одного AI-провайдера. Реализации живут в
/// `Providers/`; UI-слой (попап/меню-бар/виджет/темы) работает только через
/// `descriptor` и `LimitsSnapshot` — никогда не видит provider-специфичные типы.
public protocol LimitsProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func fetch() async -> LimitsSnapshot
}

/// Список зарегистрированных провайдеров, порядок реестра по умолчанию (Claude → Codex).
/// Фактическую включённость и порядок отображения поверх этого списка задаёт
/// `ProviderSettingsStore` — см. `LimitsViewModel.providerSettings`.
public enum ProviderRegistry {
    public static func makeDefault() -> [any LimitsProvider] {
        [ClaudeLimitsProvider(), CodexLimitsProvider()]
    }
}
