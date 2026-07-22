import SwiftUI
import MacLimitsTrackerCore

/// Корень попапа статус-бара. Публичная точка входа для App.
public struct StatusBarView: View {
    @ObservedObject var viewModel: LimitsViewModel

    public init(viewModel: LimitsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SystemStatusView(viewModel: viewModel)
            .accessibilityIdentifier("statusBarPopup")
    }
}
