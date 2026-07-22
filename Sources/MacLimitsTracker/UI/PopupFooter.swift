import SwiftUI
import MacLimitsTrackerCore

/// Общий футер всех тем: режим меню-бара, автообновление, выход.
struct PopupFooter: View {
    @ObservedObject var viewModel: LimitsViewModel
    @AppStorage("menuBarDisplayMode") private var displayMode: MenuBarDisplayMode = .iconAndText

    var body: some View {
        VStack(spacing: 8) {
            Picker("Menu bar", selection: $displayMode) {
                ForEach(MenuBarDisplayMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .controlSize(.mini)

            HStack {
                Toggle("Auto-refresh (5 min)", isOn: Binding(
                    get: { viewModel.autoRefresh },
                    set: { viewModel.setAutoRefresh($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
