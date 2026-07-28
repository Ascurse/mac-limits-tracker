import Foundation

/// Контроллер активации процесса: в `.hybrid` режиме приложение
/// запускается как menu-bar (`.accessory`), при показе singleton desktop window
/// продвигается в `.regular` (Dock/Cmd-Tab/Window menu) и возвращается в
/// `.accessory` при закрытии; в `.persistentRegular` режиме остаётся `.regular`
/// на протяжении всей жизни приложения.
///
/// Политика применяется через инжектируемое замыкание, чтобы контроллер
/// оставался пригодным для юнит-тестов без поднятия NSApp — маппинг на
/// `NSApplication.ActivationPolicy` делается в app-таргете при инициализации.
public final class WindowPresentationController {
    public enum ActivationPolicy: Equatable, Sendable {
        case accessory
        case regular
    }

    public enum LaunchMode: Equatable, Sendable {
        case hybrid
        case persistentRegular
    }

    public private(set) var isMainWindowPresented: Bool = false

    public let launchMode: LaunchMode

    private let apply: (ActivationPolicy) -> Void

    /// - Parameters:
    ///   - launchMode: режим запуска; `.hybrid` — dev/`swift run`,
    ///     `.persistentRegular` — bundled `.app`.
    ///   - apply: вызывается при смене состояния; по умолчанию —
    ///     no-op, чтобы unit-тесты могли создавать контроллер без сайд-эффектов.
    public init(
        launchMode: LaunchMode = .hybrid,
        apply: @escaping (ActivationPolicy) -> Void = { _ in }
    ) {
        self.launchMode = launchMode
        self.apply = apply
    }

    /// Применяет начальную политику в зависимости от режима запуска.
    /// Должно вызываться один раз при старте — из `AppDelegate.applicationDidFinishLaunching`,
    /// где `NSApp` уже не nil.
    public func applyLaunchPolicy() {
        switch launchMode {
        case .hybrid:
            apply(.accessory)
        case .persistentRegular:
            apply(.regular)
        }
    }

    /// Сообщает о показе/скрытии singleton desktop window. Идемпотентно:
    /// повторный вызов с тем же значением не дёргает `apply`.
    /// В `.persistentRegular` режиме процесс никогда не возвращается в `.accessory`.
    public func setMainWindowPresented(_ presented: Bool) {
        guard isMainWindowPresented != presented else { return }
        isMainWindowPresented = presented
        if presented {
            apply(.regular)
        } else if launchMode == .hybrid {
            apply(.accessory)
        }
    }
}
