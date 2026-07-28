import SwiftUI
import MacLimitsTrackerCore

/// Корень попапа статус-бара. Публичная точка входа для App.
/// Верхняя строка — действие "Open in Window" (bd mac-limits-tracker-3ip.4):
/// из menu bar можно открыть singleton desktop window; закрытие окна
/// не закрывает приложение, активация процесса управляется контроллером.
public struct StatusBarView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let launchAtLogin: LaunchAtLoginManager
    @Environment(\.openWindow) private var openWindow

    init(viewModel: LimitsViewModel, launchAtLogin: LaunchAtLoginManager) {
        self.viewModel = viewModel
        self.launchAtLogin = launchAtLogin
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            Group {
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
        }
        .accessibilityIdentifier("statusBarPopup")
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                openWindow(id: "main")
            } label: {
                Label("Open in Window", systemImage: "macwindow")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Open Limits Tracker in a regular window (Dock, Cmd-Tab, Window menu)")
            .accessibilityLabel("Open Limits Tracker in Window")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
