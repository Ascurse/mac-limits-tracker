import SwiftUI
import MacLimitsTrackerCore

@main
struct MacLimitsTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = LimitsViewModel()

    var body: some Scene {
        MenuBarExtra {
            StatusBarView(viewModel: viewModel)
        } label: {
            HStack {
                Image(systemName: viewModel.statusIcon)
                Text(viewModel.statusTitle)
            }
            // MenuBarExtra.content (попап) собирается лениво только при открытии — label рендерится
            // сразу при запуске, поэтому именно здесь запускаем обновление данных.
            .task { viewModel.start() }
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