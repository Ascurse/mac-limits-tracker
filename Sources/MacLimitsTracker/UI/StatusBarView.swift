import SwiftUI
import MacLimitsTrackerCore

/// Корень попапа статус-бара. Публичная точка входа для App.
public struct StatusBarView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let desktopWidgetController: DesktopWidgetController
    @AppStorage("appTheme") private var theme: AppTheme = .system

    init(viewModel: LimitsViewModel, desktopWidgetController: DesktopWidgetController) {
        self.viewModel = viewModel
        self.desktopWidgetController = desktopWidgetController
    }

    public var body: some View {
        Group {
            switch theme {
            case .system:
                SystemStatusView(viewModel: viewModel, desktopWidgetController: desktopWidgetController)
            case .terminal:
                TerminalStatusView(viewModel: viewModel, desktopWidgetController: desktopWidgetController)
            case .phosphor:
                PhosphorStatusView(viewModel: viewModel, desktopWidgetController: desktopWidgetController)
            case .tui:
                TUIStatusView(viewModel: viewModel, desktopWidgetController: desktopWidgetController)
            }
        }
        .accessibilityIdentifier("statusBarPopup")
    }
}
