import SwiftUI
import MacLimitsTrackerCore

/// Корень нативной сцены Settings (bd mac-limits-tracker-3ip.5): те же 4
/// общие секции, что используют попап и desktop-окно, скомпонованные с
/// поверхностью `.desktop`. Отдельного состояния нет — всё читается/пишется
/// через `LimitsViewModel` и единственный `LaunchAtLoginManager` из App.
struct SettingsRootView: View {
    @ObservedObject var viewModel: LimitsViewModel
    @ObservedObject var launchAtLogin: LaunchAtLoginManager

    var body: some View {
        Form {
            Section {
                DisplaySettingsSection(viewModel: viewModel, surface: .desktop)
            }
            Section {
                RefreshSettingsSection(viewModel: viewModel, surface: .desktop)
            }
            Section {
                ProvidersSettingsSection(viewModel: viewModel, surface: .desktop)
            }
            Section {
                SystemSettingsSection(viewModel: viewModel, launchAtLogin: launchAtLogin, surface: .desktop)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 420)
    }
}
