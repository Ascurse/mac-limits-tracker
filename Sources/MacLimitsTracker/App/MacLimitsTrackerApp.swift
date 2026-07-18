import SwiftUI
import MacLimitsTrackerCore

@main
struct MacLimitsTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = LimitsViewModel()
    @AppStorage("menuBarDisplayMode") private var displayMode: MenuBarDisplayMode = .iconAndText
    @AppStorage("showDesktopWidget") private var showDesktopWidget = false
    private let desktopWidgetController: DesktopWidgetController

    init() {
        let viewModel = LimitsViewModel()
        _viewModel = StateObject(wrappedValue: viewModel)
        desktopWidgetController = DesktopWidgetController(viewModel: viewModel)
    }

    var body: some Scene {
        MenuBarExtra {
            StatusBarView(viewModel: viewModel, desktopWidgetController: desktopWidgetController)
        } label: {
            Group {
                if displayMode == .iconOnly {
                    Image(systemName: viewModel.statusIcon)
                } else if let text = displayMode.menuBarText(claude: viewModel.claude, codex: viewModel.codex) {
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
            .help(viewModel.statusTooltip)
            .task {
                viewModel.start()
                desktopWidgetController.setVisible(showDesktopWidget)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

extension LimitsViewModel {
    var statusIcon: String {
        if isRefreshing { return "arrow.triangle.2.circlepath" }
        if claude?.providerError != nil || codex?.providerError != nil {
            return "exclamationmark.triangle"
        }
        return "gauge.with.dots.needle.bottom.50percent"
    }

    var statusTitle: String {
        let c = claude?.menuTitle ?? "Claude"
        let x = codex?.menuTitle ?? "Codex"
        return "\(c) · \(x)"
    }
}