import Foundation

/// Кнопка «открыть CLI, чтобы обновить логин» — сейчас есть только у Claude.
public struct LoginHelp: Equatable, Sendable {
    public let helpText: String
    public let binaryPath: String

    public init(helpText: String, binaryPath: String) {
        self.helpText = helpText
        self.binaryPath = binaryPath
    }

    /// Видимая подпись действия. Иконка без подписи читается как украшение —
    /// смысл появлялся только при наведении курсора (bd mac-limits-tracker-avs).
    /// Короткая: рядом с ней в шапке секции стоят имя провайдера и план.
    public static let actionTitle = "Open"

    /// Метка для VoiceOver: та же формулировка, что и у видимой подписи, плюс имя
    /// провайдера — в попапе несколько секций, и просто «Open» их не различает.
    public func accessibilityLabel(providerTitle: String) -> String {
        "\(Self.actionTitle) \(providerTitle)"
    }
}

/// Статичное самоописание провайдера: всё, что UI-слою нужно знать заранее,
/// не дожидаясь `fetch()`. Заменяет захардкоженные `.orange`/`.green`,
/// `"Claude"`/`"Codex"`, `"C"`/`"X"` по всему UI-стеку.
public struct ProviderDescriptor: Equatable, Sendable {
    /// Ключ провайдера — идентификатор для настроек (M2) и accessibility.
    public let id: String
    /// Заголовок секции попапа, напр. "Claude Code".
    public let displayName: String
    /// Короткое имя — меню-бар, тултип, `menuTitle`.
    public let shortName: String
    /// Буква в компактных режимах меню-бара, напр. "C".
    public let menuBarSymbol: String
    public let accentColorHex: UInt32
    public let loginHelp: LoginHelp?

    public init(
        id: String,
        displayName: String,
        shortName: String,
        menuBarSymbol: String,
        accentColorHex: UInt32,
        loginHelp: LoginHelp?
    ) {
        self.id = id
        self.displayName = displayName
        self.shortName = shortName
        self.menuBarSymbol = menuBarSymbol
        self.accentColorHex = accentColorHex
        self.loginHelp = loginHelp
    }
}
