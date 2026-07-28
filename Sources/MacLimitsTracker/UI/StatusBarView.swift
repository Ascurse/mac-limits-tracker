import SwiftUI
import MacLimitsTrackerCore

/// Корень попапа статус-бара. Публичная точка входа для App.
/// Верхняя строка — действие "Open in Window" (bd mac-limits-tracker-3ip.4):
/// из menu bar можно открыть singleton desktop window; закрытие окна
/// не закрывает приложение, активация процесса управляется контроллером.
public struct StatusBarView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let desktopWidgetController: DesktopWidgetController
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appTheme") private var theme: AppTheme = .system

    init(viewModel: LimitsViewModel, desktopWidgetController: DesktopWidgetController) {
        self.viewModel = viewModel
        self.desktopWidgetController = desktopWidgetController
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
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
