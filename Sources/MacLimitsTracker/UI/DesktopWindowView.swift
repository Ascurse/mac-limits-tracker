import SwiftUI
import MacLimitsTrackerCore

/// Корневое представление singleton desktop window (bd mac-limits-tracker-3ip.4).
/// Использует тот же `ProviderOverview` (3ip.2) с поверхностью `.desktop`,
/// поэтому правила форматирования и источник секций идентичны menu bar popup
/// — отличается только плотность (spacing/sparkline height внутри обзора).
/// В desktop-сценарии вызываем `viewModel.start()` (идемпотентно по 3ip.1)
/// на появление, чтобы при первом открытии окна данные подтянулись, даже
/// если menu bar popup ещё не показывался.
///
/// Геометрия (bd mac-limits-tracker-gld.3): контент живёт в одной читабельной
/// колонке `DesktopDashboardLayout` (header, сводка провайдеров, Settings —
/// общие leading/trailing), центрированной в вертикальном ScrollView. На
/// широком окне по бокам остаются спокойные поля, а не растянутые графики;
/// ограничение только maxWidth, поэтому ресайз и узкие окна не ломаются.
struct DesktopWindowView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let launchAtLogin: LaunchAtLoginManager
    @State private var settingsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ProviderOverview(
                    sections: PopupContentBuilder.sections(
                        viewModel.states,
                        history: viewModel.historySamples(providerId:),
                        thresholds: viewModel.severityThresholds,
                        costResult: viewModel.costEstimate,
                        showTrends: viewModel.showUsageTrends),
                    theme: viewModel.appTheme,
                    surface: .desktop)
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
            .padding(DesktopDashboardLayout.horizontalPadding)
            .frame(minWidth: DesktopDashboardLayout.minContentWidth,
                   maxWidth: DesktopDashboardLayout.maxContentWidth,
                   alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: DesktopDashboardLayout.minWindowWidth, idealWidth: 520,
               minHeight: 320, idealHeight: 480)
        .task { viewModel.start() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.title2)
                .accessibilityHidden(true)
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
