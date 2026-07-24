import Foundation

/// Источник данных о лимитах одного AI-провайдера. Реализации живут в
/// `Providers/`; UI-слой (попап/меню-бар/виджет/темы) работает только через
/// `descriptor` и `LimitsSnapshot` — никогда не видит provider-специфичные типы.
public protocol LimitsProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func fetch() async -> LimitsSnapshot
}

/// Провайдер с внешним условием доступности (gh #27): `LimitsViewModel`
/// перепроверяет `isAvailable` на каждом refresh и добавляет/убирает провайдера
/// без перезапуска приложения. У Kimi условие — наличие credentials-файла
/// с refresh_token (`KimiLimitsProvider.hasUsableCredentials`).
public struct DynamicProviderSpec: Sendable {
    public let id: String
    public let isAvailable: @Sendable () -> Bool
    public let makeProvider: @Sendable () -> any LimitsProvider

    public init(id: String,
                isAvailable: @escaping @Sendable () -> Bool,
                makeProvider: @escaping @Sendable () -> any LimitsProvider) {
        self.id = id
        self.isAvailable = isAvailable
        self.makeProvider = makeProvider
    }

    /// Дефолтная спецификация Kimi: доступен, пока на диске есть рабочие credentials.
    public static let kimi = DynamicProviderSpec(
        id: "kimi",
        isAvailable: { KimiLimitsProvider.hasUsableCredentials(at: KimiLimitsProvider.defaultCredentialsURL) },
        makeProvider: { KimiLimitsProvider() }
    )
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
