import SwiftUI
import MacLimitsTrackerCore

/// Секция настроек провайдеров: чекбокс включения + кнопки вверх/вниз
/// для смены порядка секций. Перенесено из `PopupFooter` без изменений.
/// Состояние — только через `LimitsViewModel`, без прямого доступа к персистентности.
/// Порядок объявления контролов сверху вниз — это и есть порядок фокуса.
struct ProvidersSettingsSection: View {
    @ObservedObject var viewModel: LimitsViewModel
    let surface: ProviderOverviewSurface

    private var controlSize: ControlSize {
        switch surface {
        case .menuBar: return .mini
        case .desktop: return .small
        }
    }

    var body: some View {
        let entries = viewModel.providerSettingsWithDescriptors
        VStack(alignment: .leading, spacing: 4) {
            Text("Providers")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(entries.enumerated()), id: \.element.setting.id) { index, entry in
                providerRow(entry, isFirst: index == 0, isLast: index == entries.count - 1)
            }
        }
    }

    private func providerRow(
        _ entry: (setting: ProviderSetting, descriptor: ProviderDescriptor),
        isFirst: Bool, isLast: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Toggle(entry.descriptor.displayName, isOn: Binding(
                get: { entry.setting.isEnabled },
                set: { viewModel.setProviderEnabled($0, id: entry.setting.id) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(controlSize)
            Spacer()
            Button {
                viewModel.moveProviderUp(id: entry.setting.id)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .controlSize(controlSize)
            .disabled(isFirst)
            .help("Move \(entry.descriptor.displayName) up")
            .accessibilityLabel("Move \(entry.descriptor.displayName) up")

            Button {
                viewModel.moveProviderDown(id: entry.setting.id)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .controlSize(controlSize)
            .disabled(isLast)
            .help("Move \(entry.descriptor.displayName) down")
            .accessibilityLabel("Move \(entry.descriptor.displayName) down")
        }
    }
}
