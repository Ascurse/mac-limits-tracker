import Foundation

/// Контроллер активации процесса для гибридной сцены (bd
/// mac-limits-tracker-3ip.4): в фоне приложение живёт как menu-bar
/// (`.accessory`), при показе singleton desktop window процесс
/// продвигается в `.regular` (Dock/Cmd-Tab/Window menu), при закрытии
/// окна возвращается в `.accessory`.
///
/// Политика применяется через инжектируемое замыкание, чтобы контроллер
/// оставался пригодным для юнит-тестов без поднятия NSApp — маппинг на
/// `NSApplication.ActivationPolicy` делается в app-таргете при инициализации.
public final class WindowPresentationController {
    public enum ActivationPolicy: Equatable, Sendable {
        case accessory
        case regular
    }

    public private(set) var isMainWindowPresented: Bool = false

    private let apply: (ActivationPolicy) -> Void

    /// - Parameter apply: вызывается при смене состояния; по умолчанию —
    ///   no-op, чтобы unit-тесты могли создавать контроллер без сайд-эффектов.
    public init(apply: @escaping (ActivationPolicy) -> Void = { _ in }) {
        self.apply = apply
    }

    /// Применяет `.accessory` — должно вызываться один раз при старте,
    /// до первой возможности открыть desktop window.
    public func ensureAccessoryOnLaunch() {
        apply(.accessory)
    }

    /// Сообщает о показе/скрытии singleton desktop window. Идемпотентно:
    /// повторный вызов с тем же значением не дёргает `apply`.
    public func setMainWindowPresented(_ presented: Bool) {
        guard isMainWindowPresented != presented else { return }
        isMainWindowPresented = presented
        apply(presented ? .regular : .accessory)
    }
}
