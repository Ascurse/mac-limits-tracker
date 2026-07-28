import Foundation

/// Контроллер активации процесса для гибридной сцены (bd
/// mac-limits-tracker-3ip.4): в фоне приложение живёт как menu-bar
/// (`.accessory`), при показе singleton desktop window процесс
/// продвигается в `.regular` (Dock/Cmd-Tab/Window menu), при закрытии
/// окна возвращается в `.accessory`.
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

    public private(set) var isMainWindowPresented: Bool = false
    public private(set) var isSettingsWindowPresented: Bool = false

    private let apply: (ActivationPolicy) -> Void
    private var appliedPolicy: ActivationPolicy = .accessory

    /// - Parameter apply: вызывается при смене эффективной политики; по
    ///   умолчанию — no-op, чтобы unit-тесты могли создавать контроллер
    ///   без сайд-эффектов.
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
        applyEffectivePolicy()
    }

    /// Сообщает о показе/скрытии нативного окна Settings. Идемпотентно.
    public func setSettingsWindowPresented(_ presented: Bool) {
        guard isSettingsWindowPresented != presented else { return }
        isSettingsWindowPresented = presented
        applyEffectivePolicy()
    }

    private func applyEffectivePolicy() {
        let policy: ActivationPolicy =
            (isMainWindowPresented || isSettingsWindowPresented) ? .regular : .accessory
        guard policy != appliedPolicy else { return }
        appliedPolicy = policy
        apply(policy)
    }
}
