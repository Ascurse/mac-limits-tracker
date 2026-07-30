import Foundation

/// Настройка одного провайдера в списке: включён ли он, позиция задаётся
/// местом элемента в массиве (порядок = порядок отображения секций).
public struct ProviderSetting: Equatable, Sendable {
    public let id: String
    public var isEnabled: Bool

    public init(id: String, isEnabled: Bool) {
        self.id = id
        self.isEnabled = isEnabled
    }
}

/// Хранит порядок провайдеров и их включённость в UserDefaults (M2, bd
/// mac-limits-tracker-6gk.2). `defaults` инжектируется для тестируемости.
public final class ProviderSettingsStore {
    private let defaults: UserDefaults
    private static let orderKey = "providerSettings.order"
    private static let disabledIdsKey = "providerSettings.disabledIds"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Порядок + включённость для набора id провайдеров реестра. Провайдеры,
    /// которых нет в сохранённом порядке (новые), добавляются в конец
    /// включёнными по умолчанию. Id из сохранёнки, которых больше нет среди
    /// `allIds` (провайдер удалён), молча отбрасываются.
    public func settings(for allIds: [String]) -> [ProviderSetting] {
        let savedOrder = defaults.stringArray(forKey: Self.orderKey) ?? []
        let disabledIds = Set(defaults.stringArray(forKey: Self.disabledIdsKey) ?? [])
        let knownIds = Set(allIds)

        var ordered = savedOrder.filter { knownIds.contains($0) }
        let placed = Set(ordered)
        ordered.append(contentsOf: allIds.filter { !placed.contains($0) })

        return ordered.map { ProviderSetting(id: $0, isEnabled: !disabledIds.contains($0)) }
    }

    /// Сохраняет порядок и включённость в том виде, в каком передан массив.
    public func save(_ settings: [ProviderSetting]) {
        defaults.set(settings.map(\.id), forKey: Self.orderKey)
        defaults.set(settings.filter { !$0.isEnabled }.map(\.id), forKey: Self.disabledIdsKey)
    }
}

extension [ProviderSetting] {
    /// Примитив перестановки: удаляет `ids` (сохраняя их относительный порядок) и
    /// вставляет блоком перед элементом `targetId`. `targetId == nil` либо id, которого
    /// нет в списке — перестановка в конец. Общая основа для movedUp/movedDown и UI
    /// drag-переупорядочивания (bd mac-limits-tracker-med.1).
    public func reordered(ids: [String], before targetId: String?) -> [ProviderSetting] {
        let movingIds = Set(ids)
        guard !movingIds.isEmpty else { return self }
        let byId = Dictionary(uniqueKeysWithValues: map { ($0.id, $0) })
        let moved = ids.compactMap { byId[$0] }
        guard !moved.isEmpty else { return self }

        var remaining = filter { !movingIds.contains($0.id) }
        guard let targetId, let targetIndex = remaining.firstIndex(where: { $0.id == targetId }) else {
            remaining.append(contentsOf: moved)
            return remaining
        }
        remaining.insert(contentsOf: moved, at: targetIndex)
        return remaining
    }

    /// Переставляет элемент с данным id на одну позицию к началу списка.
    /// Если элемент уже первый или id не найден — массив не меняется.
    public func movedUp(id: String) -> [ProviderSetting] {
        guard let index = firstIndex(where: { $0.id == id }), index > 0 else { return self }
        return reordered(ids: [id], before: self[index - 1].id)
    }

    /// Переставляет элемент с данным id на одну позицию к концу списка.
    /// Если элемент уже последний или id не найден — массив не меняется.
    public func movedDown(id: String) -> [ProviderSetting] {
        guard let index = firstIndex(where: { $0.id == id }), index < count - 1 else { return self }
        let targetId = index + 2 < count ? self[index + 2].id : nil
        return reordered(ids: [id], before: targetId)
    }

    /// Включает/выключает элемент с данным id, остальные не трогает.
    public func settingEnabled(id: String, isEnabled: Bool) -> [ProviderSetting] {
        map { $0.id == id ? ProviderSetting(id: $0.id, isEnabled: isEnabled) : $0 }
    }
}
