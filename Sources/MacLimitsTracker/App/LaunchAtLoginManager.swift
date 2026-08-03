import Foundation
import ServiceManagement
import AppKit

/// «Запускать при входе» через `SMAppService.mainApp` (gh #33).
/// Источник истины — система: статус перечитывается при каждом открытии попапа,
/// т.к. пользователь может менять login item в System Settings параллельно.
/// Без бандла (`swift run`) — no-op, как и `NotificationManager`.
final class LaunchAtLoginManager: ObservableObject {
    enum Status: Equatable {
        case unavailable
        case disabled
        case enabled
        case requiresApproval
    }

    @Published private(set) var status: Status = .unavailable

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    /// Тоггл доступен только в собранном .app: у unbundled-запуска register() не сработает.
    let isAvailable: Bool

    init() {
        isAvailable = Bundle.main.bundleIdentifier != nil
        syncStatus()
    }

    func syncStatus() {
        guard isAvailable else {
            status = .unavailable
            return
        }
        let systemStatus = SMAppService.mainApp.status
        switch systemStatus {
        case .enabled:
            status = .enabled
        case .requiresApproval:
            status = .requiresApproval
        default:
            status = .disabled
        }
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

    func openLoginItems() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
