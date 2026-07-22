import Foundation

/// Источник данных о лимитах одного AI-провайдера. Реализации живут в
/// `Providers/`; UI-слой (попап/меню-бар/виджет/темы) работает только через
/// `descriptor` и `LimitsSnapshot` — никогда не видит provider-специфичные типы.
public protocol LimitsProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func fetch() async -> LimitsSnapshot
}

/// Список зарегистрированных провайдеров, порядок реестра по умолчанию
/// (Claude → Codex → Kimi). Kimi регистрируется только при наличии рабочих
/// credentials (файл + непустой refresh_token), иначе скрыт (bd mac-limits-tracker-6gk.3).
/// Фактическую включённость и порядок отображения поверх этого списка задаёт
/// `ProviderSettingsStore` — см. `LimitsViewModel.providerSettings`.
public enum ProviderRegistry {
    public static func makeDefault(
        kimiCredentialsURL: URL = KimiLimitsProvider.defaultCredentialsURL
    ) -> [any LimitsProvider] {
        var providers: [any LimitsProvider] = [ClaudeLimitsProvider(), CodexLimitsProvider()]
        if KimiLimitsProvider.hasUsableCredentials(at: kimiCredentialsURL) {
            providers.append(KimiLimitsProvider(credentialsURL: kimiCredentialsURL))
        }
        return providers
    }
}
