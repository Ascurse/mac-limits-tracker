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
        VStack(spacing: spacing) {
            Picker("Theme", selection: Binding(
                get: { viewModel.appTheme },
                set: { viewModel.setAppTheme($0) }
            )) {
                ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .controlSize(controlSize)
            .accessibilityLabel("Theme")

            Picker("Menu bar", selection: Binding(
                get: { viewModel.menuBarDisplayMode },
                set: { viewModel.setMenuBarDisplayMode($0) }
            )) {
                ForEach(MenuBarDisplayMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .controlSize(controlSize)
            .accessibilityLabel("Menu bar")
        }
    }
}
