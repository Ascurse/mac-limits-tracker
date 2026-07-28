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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

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
                Label("Open Limits Tracker", systemImage: "macwindow")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Open Limits Tracker in a regular window (Dock, Cmd-Tab, Window menu)")
            .accessibilityLabel("Open Limits Tracker in Window")
            Button {
                openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Open Settings (Cmd-,)")
            .accessibilityLabel("Open Settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
