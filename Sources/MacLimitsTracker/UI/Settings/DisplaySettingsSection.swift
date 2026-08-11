import SwiftUI
import MacLimitsTrackerCore

/// Секция настроек отображения: тема попапа и режим меню-бара.
/// Используется попапом меню-бара, desktop-окном и (позже) нативной сценой
/// Settings — плотность (control size, отступы) выводится из `surface`.
/// Состояние читается/пишется только через `LimitsViewModel`, без прямого доступа к персистентности.
/// Порядок объявления контролов сверху вниз — это и есть порядок фокуса.
struct DisplaySettingsSection: View {
    @ObservedObject var viewModel: LimitsViewModel
    let surface: ProviderOverviewSurface

    private var controlSize: ControlSize {
        switch surface {
        case .menuBar: return .mini
        case .desktop: return .small
        }
    }

    private var spacing: CGFloat {
        switch surface {
        case .menuBar: return 8
        case .desktop: return 12
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Picker("Popup theme", selection: Binding(
                get: { viewModel.appTheme },
                set: { viewModel.setAppTheme($0) }
            )) {
                ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .controlSize(controlSize)
            .accessibilityLabel("Popup theme")
            .accessibilityHint("Applies to the menu-bar popup. The desktop widget keeps its neutral dark appearance.")
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Menu bar", selection: Binding(
                get: { viewModel.menuBarDisplayMode },
                set: { viewModel.setMenuBarDisplayMode($0) }
            )) {
                ForEach(MenuBarDisplayMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .controlSize(controlSize)
            .accessibilityLabel("Menu bar")
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Show daily budget", isOn: Binding(
                get: { viewModel.showDailyBudget },
                set: { viewModel.setShowDailyBudget($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(controlSize)
            .accessibilityLabel("Show daily budget")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
