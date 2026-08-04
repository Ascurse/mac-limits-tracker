import SwiftUI
import AppKit
import MacLimitsTrackerCore

@main
struct MacLimitsTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel: LimitsViewModel
    private let desktopWidgetController: DesktopWidgetController
    private let launchAtLoginManager = LaunchAtLoginManager()
    private let notificationManager: NotificationManager
    /// Контроллер активации (bd mac-limits-tracker-3ip.7): `.persistentRegular`
    /// для собранного `.app`-бандла, `.hybrid` для `swift run`.
    private let windowPresentationController: WindowPresentationController

    init() {
        // Kimi — через dynamicProviders (gh #27): появление/удаление credentials
        // подхватывается на refresh, без перезапуска приложения.
        let viewModel = LimitsViewModel(dynamicProviders: [.kimi])
        _viewModel = StateObject(wrappedValue: viewModel)
        desktopWidgetController = DesktopWidgetController(viewModel: viewModel)
        notificationManager = NotificationManager(viewModel: viewModel)
        let launchMode: WindowPresentationController.LaunchMode =
            Bundle.main.bundleIdentifier != nil ? .persistentRegular : .hybrid
        let controller = WindowPresentationController(
            launchMode: launchMode,
            apply: { policy in
                switch policy {
                case .accessory: NSApp.setActivationPolicy(.accessory)
                case .regular: NSApp.setActivationPolicy(.regular)
                }
            }
        )
        // `applyLaunchPolicy()` не зовём здесь: NSApp на этом этапе ещё nil.
        // AppDelegate вызовет её из `applicationDidFinishLaunching`.
        self.windowPresentationController = controller
        appDelegate.windowPresentationController = controller
        appDelegate.viewModel = viewModel
    }

    var body: some Scene {
        MenuBarExtra {
            StatusBarView(viewModel: viewModel, launchAtLogin: launchAtLoginManager)
        } label: {
            Group {
                if viewModel.menuBarDisplayMode == .iconOnly {
                    Image(systemName: viewModel.statusIcon)
                } else if let text = viewModel.menuBarDisplayMode.menuBarText(states: viewModel.states) {
                    HStack {
                        Image(systemName: viewModel.statusIcon)
                        Text(text).font(.caption).monospacedDigit()
                    }
                } else {
                    HStack {
                        Image(systemName: viewModel.statusIcon)
                        Text(viewModel.statusTitle)
                    }
                }
            }
            .foregroundStyle(menuBarTint)
            .help(viewModel.statusTooltip)
            .task {
                viewModel.start()
                desktopWidgetController.setVisible(viewModel.showDesktopWidget)
            }
        }
        .menuBarExtraStyle(.window)

        // Singleton desktop window: SwiftUI `Window("...", id:)` гарантирует
        // единственный экземпляр — повторный openWindow(id:"main") фокусирует
        // уже существующее окно, а не создаёт копию. Закрытие не завершает
        // приложение и не очищает shared state (отдельный источник VM).
        Window("Limits Tracker", id: "main") {
            DesktopWindowView(viewModel: viewModel, launchAtLogin: launchAtLoginManager)
                .onAppear { windowPresentationController.setMainWindowPresented(true) }
                .onDisappear { windowPresentationController.setMainWindowPresented(false) }
        }
        .defaultSize(width: 520, height: 480)
        .windowResizability(.contentMinSize)
        .commands {
            OpenLimitsTrackerCommand()
        }

        // Нативное окно Settings (Cmd-,): композиция тех же 4 общих секций
        // с поверхностью `.desktop` (bd mac-limits-tracker-3ip.5). Окно идёт
        // через тот же WindowPresentationController — политика остаётся
        // .regular, пока открыто хотя бы одно окно.
        Settings {
            SettingsRootView(viewModel: viewModel, launchAtLogin: launchAtLoginManager)
                .onAppear { windowPresentationController.setSettingsWindowPresented(true) }
                .onDisappear { windowPresentationController.setSettingsWindowPresented(false) }
        }
    }

    private var menuBarTint: Color {
        switch viewModel.statusSeverity {
        case .normal: return .primary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

/// Команда "Open Limits Tracker" в App-меню: повторно открывает singleton
/// desktop window (Cmd-0). SwiftUI сводит `openWindow` к фокусу существующего
/// окна, если оно уже на экране.
private struct OpenLimitsTrackerCommand: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            OpenLimitsTrackerButton()
        }
    }
}

private struct OpenLimitsTrackerButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Limits Tracker") {
            openWindow(id: "main")
        }
        .keyboardShortcut("0", modifiers: [.command])
    }
}

extension LimitsViewModel {
    var statusSeverity: Severity {
        Severity.worst(in: states, thresholds: severityThresholds)
    }

    var statusIcon: String {
        if isRefreshing { return "arrow.triangle.2.circlepath" }
        if states.contains(where: { $0.snapshot?.providerError != nil }) {
            return "exclamationmark.triangle"
        }
        return "gauge.with.dots.needle.bottom.50percent"
    }

    var statusTitle: String {
        states.map { state in
            state.snapshot?.menuTitle(shortName: state.descriptor.shortName) ?? state.descriptor.shortName
        }.joined(separator: " · ")
    }
}
