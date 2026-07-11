import AppKit
import SwiftUI
import MacLimitsTrackerCore

/// Прячет иконку из дока — приложение живёт только в меню-баре.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}