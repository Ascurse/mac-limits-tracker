import SwiftUI
import MacLimitsTrackerCore

@main
struct MacLimitsTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = LimitsViewModel()
    @AppStorage("menuBarDisplayMode") private var displayMode: MenuBarDisplayMode = .iconAndText
    @AppStorage("showDesktopWidget") private var showDesktopWidget = false
    private let desktopWidgetController: DesktopWidgetController
    private let notificationManager: NotificationManager

    init() {
        // Kimi — через dynamicProviders (gh #27): появление/удаление credentials
        // подхватывается на refresh, без перезапуска приложения.
        let viewModel = LimitsViewModel(dynamicProviders: [.kimi])
        _viewModel = StateObject(wrappedValue: viewModel)
        desktopWidgetController = DesktopWidgetController(viewModel: viewModel)
        notificationManager = NotificationManager(viewModel: viewModel)
    }

    var body: some Scene {
        MenuBarExtra {
            StatusBarView(viewModel: viewModel, desktopWidgetController: desktopWidgetController)
        } label: {
            Group {
                if displayMode == .iconOnly {
                    Image(systemName: viewModel.statusIcon)
                } else if let text = displayMode.menuBarText(states: viewModel.states) {
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
                desktopWidgetController.setVisible(showDesktopWidget)
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarTint: Color {
        switch viewModel.statusSeverity {
        case .normal: return .primary
        case .warning: return .orange
        case .critical: return .red
        }
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
