import SwiftUI
import AppKit
import MacLimitsTrackerCore

extension Color {
    /// Цвет из hex-константы палитры темы: Color(hex: 0x1A1B26).
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Открывает Claude Code в Terminal: CLI при запуске сам обновляет OAuth-токен в Keychain.
func openClaudeCode() {
    let binary = ProcessRunner.defaultClaudeBinary()
    let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    let config = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.open([URL(fileURLWithPath: binary)],
                            withApplicationAt: terminal,
                            configuration: config)
}
