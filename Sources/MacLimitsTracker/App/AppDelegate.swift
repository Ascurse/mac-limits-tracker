import AppKit
import SwiftUI
import MacLimitsTrackerCore

/// AppDelegate. Гибридная активация (bd mac-limits-tracker-3ip.4): NSApp
/// гарантированно не-nil только в `applicationDidFinishLaunching`, поэтому
/// стартовая `.accessory`-политика применяется отсюда через
/// `WindowPresentationController`. Дальнейшие переключения (`.regular`
/// при показе Window сцены) приходят из самого окна.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Контроллер активации, проставляется `MacLimitsTrackerApp.init`.
    var windowPresentationController: WindowPresentationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowPresentationController?.ensureAccessoryOnLaunch()
    }
}

