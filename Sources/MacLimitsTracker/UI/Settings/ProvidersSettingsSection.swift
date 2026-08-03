import SwiftUI
import MacLimitsTrackerCore

/// Секция настроек провайдеров: чекбокс включения, drag-переупорядочивание
/// (List + onMove), кнопки вверх/вниз и сброс порядка к каноническому
/// (bd mac-limits-tracker-med.2). Состояние — только через `LimitsViewModel`,
/// без прямого доступа к персистентности.
///
/// Перестановка идёт через ID-команду `reorderProviders(_:before:)`, а НЕ
/// через индексы видимых строк: проекция `providerSettingsWithDescriptors`
/// отфильтровывает недоступные dynamic-провайдеры (Kimi без credentials),
/// поэтому индексы строк не совпадают с индексами `providerSettings`.
struct ProvidersSettingsSection: View {
    @ObservedObject var viewModel: LimitsViewModel
    let surface: ProviderOverviewSurface

    private var controlSize: ControlSize {
        switch surface {
        case .menuBar: return .mini
        case .desktop: return .small
        }
    }

    /// Высота строки списка — фиксированная оценка компактной строки, чтобы
    /// List (жадно растущий по высоте) занял ровно столько места, сколько занимал
    /// прежний VStack: попап имеет свободную высоту и иначе растянулся бы.
    private var rowHeight: CGFloat {
        switch surface {
        case .menuBar: return 20
        case .desktop: return 24
        }
    }

    var body: some View {
        let entries = viewModel.providerSettingsWithDescriptors
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Providers")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset order") {
                    viewModel.resetProviderOrder()
                }
                .buttonStyle(.borderless)
                .controlSize(controlSize)
                .disabled(isCanonicalOrder(entries))
                .help("Restore the default provider order")
                .accessibilityLabel("Reset provider order")
                .accessibilityHint("Restores the default provider order")
            }
            List {
                ForEach(Array(entries.enumerated()), id: \.element.setting.id) { index, entry in
                    providerRow(entry, isFirst: index == 0, isLast: index == entries.count - 1)
                        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                        .listRowSeparator(.hidden)
                }
                .onMove { source, destination in
                    moveProviders(source: source, destination: destination, entries: entries)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: CGFloat(entries.count) * rowHeight + 4)
        }
    }

    /// Переводит List.onMove offsets в ID-команду Core: какие id двигаем
    /// (в исходном относительном порядке) и перед каким видимым id вставить
    /// блок (`nil` — в конец). Скрытые dynamic-провайдеры не участвуют:
    /// `reordered(ids:before:)` в Core сохраняет их позиции как есть.
    private func moveProviders(
        source: IndexSet, destination: Int,
        entries: [(setting: ProviderSetting, descriptor: ProviderDescriptor)]
    ) {
        let visibleIds = entries.map { $0.setting.id }
        let movingIds = source.sorted().map { visibleIds[$0] }
        var reorderedVisible = visibleIds
        reorderedVisible.move(fromOffsets: source, toOffset: destination)
        let moving = Set(movingIds)
        guard let lastMovedIndex = reorderedVisible.lastIndex(where: { moving.contains($0) }) else { return }
        let targetId = lastMovedIndex + 1 < reorderedVisible.count
            ? reorderedVisible[lastMovedIndex + 1]
            : nil
        viewModel.reorderProviders(movingIds, before: targetId)
    }

    /// Текущий видимый порядок совпадает с каноническим (порядок
    /// ProviderRegistry, отфильтрованный по видимым)? Тогда Reset — no-op и
    /// кнопка выключена. `makeDefault()` — дешёвый: подстановка путей +
    /// проверка файлов, провайдеры только конструируются, не опрашиваются.
    private func isCanonicalOrder(
        _ entries: [(setting: ProviderSetting, descriptor: ProviderDescriptor)]
    ) -> Bool {
        let visibleIds = entries.map { $0.setting.id }
        let visible = Set(visibleIds)
        let canonicalVisibleIds = ProviderRegistry.makeDefault()
            .map { $0.descriptor.id }
            .filter { visible.contains($0) }
        return visibleIds == canonicalVisibleIds
    }

    private func providerRow(
        _ entry: (setting: ProviderSetting, descriptor: ProviderDescriptor),
        isFirst: Bool, isLast: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Toggle(entry.descriptor.displayName, isOn: Binding(
                get: { entry.setting.isEnabled },
                set: { viewModel.setProviderEnabled($0, id: entry.setting.id) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(controlSize)
            .accessibilityIdentifier("provider-toggle-\(entry.setting.id)")
            .accessibilityLabel("\(entry.descriptor.displayName) provider")
            .accessibilityValue(entry.setting.isEnabled ? "Enabled" : "Disabled")
            .accessibilityHint("Toggle provider availability")
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
