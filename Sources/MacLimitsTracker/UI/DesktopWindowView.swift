import SwiftUI
import MacLimitsTrackerCore

/// Корневое представление singleton desktop window (bd mac-limits-tracker-3ip.4).
/// Использует тот же `ProviderOverview` (3ip.2) с поверхностью `.desktop`,
/// поэтому правила форматирования и источник секций идентичны menu bar popup
/// — отличается только плотность (spacing/sparkline height внутри обзора).
/// В desktop-сценарии вызываем `viewModel.start()` (идемпотентно по 3ip.1)
/// на появление, чтобы при первом открытии окна данные подтянулись, даже
/// если menu bar popup ещё не показывался.
struct DesktopWindowView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let launchAtLogin: LaunchAtLoginManager
    @State private var settingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ProviderOverview(
                sections: PopupContentBuilder.sections(
                    viewModel.states,
                    history: viewModel.historySamples(providerId:),
                    thresholds: viewModel.severityThresholds),
                theme: viewModel.appTheme,
                surface: .desktop)
            Spacer(minLength: 0)
            Divider()
            DisclosureGroup("Settings", isExpanded: $settingsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    DisplaySettingsSection(viewModel: viewModel, surface: .desktop)
                    RefreshSettingsSection(viewModel: viewModel, surface: .desktop)
                    ProvidersSettingsSection(viewModel: viewModel, surface: .desktop)
                    SystemSettingsSection(viewModel: viewModel, launchAtLogin: launchAtLogin, surface: .desktop)
                }
                .padding(.top, 4)
            }
            .accessibilityHint("Expand to edit shared settings")
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 320, idealHeight: 480)
        .task { viewModel.start() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text("Limits Tracker")
                    .font(.headline)
                Text(PopupContentBuilder.updatedText(states: viewModel.states))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.refresh()
            } label: {
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
    }
}
