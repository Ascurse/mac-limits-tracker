import AppKit
import SwiftUI
import MacLimitsTrackerCore

/// AppDelegate. Активация применяется из `applicationDidFinishLaunching`,
/// потому что `NSApp` гарантированно не-nil только на этом этапе
/// (bd mac-limits-tracker-3ip.4). Дальнейшие переключения (`.regular`
/// при показе Window сцены) приходят из самого окна.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Контроллер активации, проставляется `MacLimitsTrackerApp.init`.
    var windowPresentationController: WindowPresentationController?
    /// Shared ViewModel, проставляется `MacLimitsTrackerApp.init`.
    var viewModel: LimitsViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowPresentationController?.applyLaunchPolicy()
        // Запускаем polling сразу при старте приложения, а не только при
        // открытии popup'а: `.task` на label MenuBarExtra не гарантирует
        // выполнение без открытия popup, и после чистого relaunch refresh
        // не записывался (bd mac-limits-tracker-4jx).
        viewModel?.start()
    }
}

