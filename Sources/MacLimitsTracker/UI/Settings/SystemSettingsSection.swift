import SwiftUI
import MacLimitsTrackerCore

/// Секция системных настроек: desktop-виджет, уведомления, запуск при входе.
/// `LaunchAtLoginManager` инжектируется снаружи — прямых вызовов SMAppService
/// здесь нет; система — источник истины по login item, статус перечитываем
/// при каждом появлении поверхности (`onAppear`).
/// Контроллер desktop-виджета сам подписан на `showDesktopWidget`, поэтому
/// здесь никакого onChange-клея нет.
/// Порядок объявления контролов сверху вниз — это и есть порядок фокуса.
struct SystemSettingsSection: View {
    @ObservedObject var viewModel: LimitsViewModel
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    let surface: ProviderOverviewSurface

    private var controlSize: ControlSize {
        switch surface {
        case .menuBar: return .mini
        case .desktop: return .small
        }
    }

    private var spacing: CGFloat {
        switch surface {
        case .menuBar: return 8
        case .desktop: return 12
        }
    }

    var body: some View {
        VStack(spacing: spacing) {
            Toggle("Desktop widget", isOn: Binding(
                get: { viewModel.showDesktopWidget },
                set: { viewModel.setShowDesktopWidget($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(controlSize)
            .accessibilityLabel("Desktop widget")

            Toggle("Notifications", isOn: Binding(
                get: { viewModel.notificationsEnabled },
                set: { viewModel.setNotificationsEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(controlSize)
            .accessibilityLabel("Notifications")

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(controlSize)
            .disabled(!launchAtLogin.isAvailable)
            .accessibilityLabel("Launch at login")
        }
        // Система — источник истины по login item: перечитываем при каждом открытии поверхности.
        .onAppear { launchAtLogin.syncStatus() }
    }
}
