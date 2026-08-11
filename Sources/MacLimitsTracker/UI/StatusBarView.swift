import SwiftUI
import MacLimitsTrackerCore

/// Корень попапа статус-бара. Публичная точка входа для App.
/// Верхняя строка — bridge к desktop-поверхностям (bd mac-limits-tracker-3ip.6):
/// "Open Limits Tracker" открывает singleton desktop window (3ip.4),
/// "Settings…" открывает нативную Settings scene (3ip.5) через `openSettings`.
/// Закрытие окон не закрывает приложение, активация процесса управляется
/// WindowPresentationController; состояние остаётся в общей LimitsViewModel.
public struct StatusBarView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let launchAtLogin: LaunchAtLoginManager
    init(viewModel: LimitsViewModel, launchAtLogin: LaunchAtLoginManager) {
        self.viewModel = viewModel
        self.launchAtLogin = launchAtLogin
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            ScrollView {
                switch viewModel.appTheme {
                case .system:
                    SystemStatusView(viewModel: viewModel, launchAtLogin: launchAtLogin)
                case .terminal:
                    TerminalStatusView(viewModel: viewModel, launchAtLogin: launchAtLogin)
                case .phosphor:
                    PhosphorStatusView(viewModel: viewModel, launchAtLogin: launchAtLogin)
                case .tui:
                    TUIStatusView(viewModel: viewModel, launchAtLogin: launchAtLogin)
                }
            }
            .frame(maxHeight: .infinity)
            PopupFooter(viewModel: viewModel, launchAtLogin: launchAtLogin)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(minWidth: MenuBarPopupLayout.minWidth,
               idealWidth: MenuBarPopupLayout.idealWidth,
               maxHeight: MenuBarPopupLayout.maxHeight)
        .accessibilityIdentifier("statusBarPopup")
    }

    private var topBar: some View {
        HStack {
            Text("Limits Tracker").font(.headline)
            Spacer()
            Text(PopupContentBuilder.updatedText(states: viewModel.states))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button { viewModel.refresh() } label: {
                Image(systemName: viewModel.isRefreshing
                      ? "arrow.triangle.2.circlepath.circle"
                      : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshing)
            .help(viewModel.isRefreshing ? "Refreshing…" : "Refresh (⌘R)")
            .accessibilityLabel("Refresh")
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

}
