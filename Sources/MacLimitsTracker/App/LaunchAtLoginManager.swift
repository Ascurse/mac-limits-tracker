import Foundation
import ServiceManagement

/// «Запускать при входе» через `SMAppService.mainApp` (gh #33).
/// Источник истины — система: статус перечитывается при каждом открытии попапа,
/// т.к. пользователь может менять login item в System Settings параллельно.
/// Без бандла (`swift run`) — no-op, как и `NotificationManager`.
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false

    /// Тоггл доступен только в собранном .app: у unbundled-запуска register() не сработает.
    let isAvailable: Bool

    init() {
        isAvailable = Bundle.main.bundleIdentifier != nil
        syncStatus()
    }

    func syncStatus() {
        guard isAvailable else { return }
        let status = SMAppService.mainApp.status
        // .requiresApproval — зарегистрирован, но система ждёт подтверждения: считаем включённым.
        isEnabled = status == .enabled || status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Ошибку не прячем в UI: syncStatus ниже вернёт тоггл в фактическое состояние.
        }
        syncStatus()
    }
}
