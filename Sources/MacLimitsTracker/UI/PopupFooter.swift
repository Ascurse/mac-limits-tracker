import SwiftUI
import AppKit
import MacLimitsTrackerCore

/// Футер попапа: композиция общих секций настроек с поверхностью `.menuBar`
/// и специфичная для попапа кнопка Quit. Состояние — только через ViewModel
/// и инжектированный `LaunchAtLoginManager`; прямых чтений персистентности нет.
struct PopupFooter: View {
    @ObservedObject var viewModel: LimitsViewModel
    let launchAtLogin: LaunchAtLoginManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismissEnvironment

    var body: some View {
        HStack(spacing: 8) {
            Button {
                dismissPopup()
                DispatchQueue.main.async { openWindow(id: "main") }
            } label: {
                Label("Open Limits Tracker", systemImage: "macwindow")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .help("Open Limits Tracker in a regular window (⌘0)")
            .keyboardShortcut("0", modifiers: .command)

            Button {
                dismissPopup()
                DispatchQueue.main.async { openSettings() }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .help("Open Settings (⌘,)")
            .accessibilityLabel("Open Settings")
            .keyboardShortcut(",", modifiers: .command)

            Menu {
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .controlSize(.mini)
            .help("More actions")
            .accessibilityLabel("More actions")
        }
    }

    private func dismissPopup() {
        NSApp.sendAction(#selector(NSPopover.performClose(_:)), to: nil, from: nil)
        dismissEnvironment()
        NSApp.keyWindow?.close()
    }
}
