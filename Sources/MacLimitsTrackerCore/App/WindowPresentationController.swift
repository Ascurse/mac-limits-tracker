import Foundation

/// Контроллер активации процесса: в `.hybrid` режиме приложение
/// запускается как menu-bar (`.accessory`), при показе singleton desktop window
/// продвигается в `.regular` (Dock/Cmd-Tab/Window menu) и возвращается в
/// `.accessory` при закрытии; в `.persistentRegular` режиме остаётся `.regular`
/// на протяжении всей жизни приложения.
///
/// Нативная Settings scene (bd mac-limits-tracker-3ip.5) — второе окно
/// через тот же контроллер: эффективная политика — `.regular`, пока
/// открыто хотя бы одно окно (main ИЛИ settings), и `.accessory`,
/// только когда закрыты оба. `apply` дёргается лишь при смене
/// эффективной политики, а не каждого флага.
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
    public private(set) var isSettingsWindowPresented: Bool = false

    public let launchMode: LaunchMode

    private let apply: (ActivationPolicy) -> Void
    private var appliedPolicy: ActivationPolicy = .accessory

    /// - Parameters:
    ///   - launchMode: режим запуска; `.hybrid` — dev/`swift run`,
    ///     `.persistentRegular` — bundled `.app`.
    ///   - apply: вызывается при смене эффективной политики; по умолчанию —
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
        let policy: ActivationPolicy = launchMode == .hybrid ? .accessory : .regular
        appliedPolicy = policy
        apply(policy)
    }

    /// Сообщает о показе/скрытии singleton desktop window. Идемпотентно:
    /// повторный вызов с тем же значением не дёргает `apply`.
    public func setMainWindowPresented(_ presented: Bool) {
        guard isMainWindowPresented != presented else { return }
        isMainWindowPresented = presented
        applyEffectivePolicy()
    }

    /// Сообщает о показе/скрытии нативного окна Settings. Идемпотентно.
    public func setSettingsWindowPresented(_ presented: Bool) {
        guard isSettingsWindowPresented != presented else { return }
        isSettingsWindowPresented = presented
        applyEffectivePolicy()
    }

    private func applyEffectivePolicy() {
        let policy: ActivationPolicy
        switch launchMode {
        case .persistentRegular:
            policy = .regular
        case .hybrid:
            policy = (isMainWindowPresented || isSettingsWindowPresented) ? .regular : .accessory
        }
        guard policy != appliedPolicy else { return }
        appliedPolicy = policy
        apply(policy)
    }
}
