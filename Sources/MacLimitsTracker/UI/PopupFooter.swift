import SwiftUI
import MacLimitsTrackerCore

/// Общий футер всех тем: режим меню-бара, автообновление, виджет, выход.
struct PopupFooter: View {
    @ObservedObject var viewModel: LimitsViewModel
    let desktopWidgetController: DesktopWidgetController
    @AppStorage("appTheme") private var theme: AppTheme = .system
    @AppStorage("menuBarDisplayMode") private var displayMode: MenuBarDisplayMode = .iconAndText
    @AppStorage("showDesktopWidget") private var showDesktopWidget = false

    var body: some View {
        VStack(spacing: 8) {
            Picker("Theme", selection: $theme) {
                ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .controlSize(.mini)

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
                Toggle("Desktop widget", isOn: $showDesktopWidget)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: showDesktopWidget) { _, newValue in
                        desktopWidgetController.setVisible(newValue)
                    }
            }

            HStack {
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
