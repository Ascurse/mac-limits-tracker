import SwiftUI
import MacLimitsTrackerCore

/// Корень попапа статус-бара. Публичная точка входа для App.
public struct StatusBarView: View {
    @ObservedObject var viewModel: LimitsViewModel
    @AppStorage("appTheme") private var theme: AppTheme = .system

    public init(viewModel: LimitsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            switch theme {
            case .system:
                SystemStatusView(viewModel: viewModel)
            case .terminal:
                TerminalStatusView(viewModel: viewModel)
            case .phosphor:
                SystemStatusView(viewModel: viewModel) // заменит Task 5
            case .tui:
                SystemStatusView(viewModel: viewModel) // заменит Task 6
            }
        }
        .accessibilityIdentifier("statusBarPopup")
    }
}
