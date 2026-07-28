import SwiftUI
import MacLimitsTrackerCore

/// Секция настроек обновления: интервал, пороги severity (warning/critical),
/// тоггл автообновления. Перенесено из `PopupFooter` без изменений логики:
/// critical всегда держится строго ниже warning (при повышении warning
/// critical прижимается к ближайшей допустимой опции).
/// Состояние — только через `LimitsViewModel`, без прямого доступа к персистентности.
/// Порядок объявления контролов сверху вниз — это и есть порядок фокуса.
struct RefreshSettingsSection: View {
    @ObservedObject var viewModel: LimitsViewModel
    let surface: ProviderOverviewSurface

    /// Опции порогов severity (issue #25), % остатка лимита.
    private static let warningOptions: [Double] = [20, 30, 40, 50, 60]
    private static let criticalOptions: [Double] = [5, 10, 15, 20, 25]

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
            Picker("Refresh every", selection: Binding(
                get: { viewModel.autoRefreshInterval },
                set: { viewModel.setAutoRefreshInterval($0) }
            )) {
                ForEach(RefreshInterval.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .controlSize(controlSize)
            .accessibilityLabel("Refresh every")

            HStack {
                Picker("Warning at", selection: Binding(
                    get: { viewModel.severityThresholds.warningRemaining },
                    set: { warning in
                        viewModel.setWarningThreshold(warning, maxCriticalOptions: Self.criticalOptions)
                    }
                )) {
                    ForEach(Self.warningOptions, id: \.self) { Text("\(Int($0))% left").tag($0) }
                }
                .pickerStyle(.menu)
                .controlSize(controlSize)
                .accessibilityLabel("Warning at")

                Picker("Critical at", selection: Binding(
                    get: { viewModel.severityThresholds.criticalRemaining },
                    set: { critical in
                        viewModel.setSeverityThresholds(SeverityThresholds(
                            warningRemaining: viewModel.severityThresholds.warningRemaining,
                            criticalRemaining: critical))
                    }
                )) {
                    ForEach(Self.criticalOptions.filter {
                        $0 < viewModel.severityThresholds.warningRemaining
                    }, id: \.self) { Text("\(Int($0))% left").tag($0) }
                }
                .pickerStyle(.menu)
                .controlSize(controlSize)
                .accessibilityLabel("Critical at")
            }

            Toggle("Auto-refresh (\(viewModel.autoRefreshInterval.title))", isOn: Binding(
                get: { viewModel.autoRefresh },
                set: { viewModel.setAutoRefresh($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(controlSize)
            .accessibilityLabel("Auto-refresh")
        }
    }
}
