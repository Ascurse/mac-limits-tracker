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

            providerSettingsSection

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

    /// Список провайдеров реестра (включая выключенных): чекбокс включения +
    /// кнопки вверх/вниз для смены порядка секций попапа. bd mac-limits-tracker-6gk.2.
    private var providerSettingsSection: some View {
        let entries = viewModel.providerSettingsWithDescriptors
        return VStack(alignment: .leading, spacing: 4) {
            Text("Providers")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(entries.enumerated()), id: \.element.setting.id) { index, entry in
                providerRow(entry, isFirst: index == 0, isLast: index == entries.count - 1)
            }
        }
    }

    private func providerRow(
        _ entry: (setting: ProviderSetting, descriptor: ProviderDescriptor),
        isFirst: Bool, isLast: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Toggle(entry.descriptor.displayName, isOn: Binding(
                get: { entry.setting.isEnabled },
                set: { viewModel.setProviderEnabled($0, id: entry.setting.id) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.mini)
            Spacer()
            Button {
                viewModel.moveProviderUp(id: entry.setting.id)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .disabled(isFirst)
            .accessibilityLabel("Move \(entry.descriptor.displayName) up")

            Button {
                viewModel.moveProviderDown(id: entry.setting.id)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .disabled(isLast)
            .accessibilityLabel("Move \(entry.descriptor.displayName) down")
        }
    }
}
