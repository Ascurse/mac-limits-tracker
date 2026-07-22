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
    /// Переставляет элемент с данным id на одну позицию к началу списка.
    /// Если элемент уже первый или id не найден — массив не меняется.
    public func movedUp(id: String) -> [ProviderSetting] {
        moved(id: id, by: -1)
    }

    /// Переставляет элемент с данным id на одну позицию к концу списка.
    /// Если элемент уже последний или id не найден — массив не меняется.
    public func movedDown(id: String) -> [ProviderSetting] {
        moved(id: id, by: 1)
    }

    private func moved(id: String, by offset: Int) -> [ProviderSetting] {
        guard let index = firstIndex(where: { $0.id == id }) else { return self }
        let newIndex = index + offset
        guard indices.contains(newIndex) else { return self }
        var copy = self
        copy.swapAt(index, newIndex)
        return copy
    }

    /// Включает/выключает элемент с данным id, остальные не трогает.
    public func settingEnabled(id: String, isEnabled: Bool) -> [ProviderSetting] {
        map { $0.id == id ? ProviderSetting(id: $0.id, isEnabled: isEnabled) : $0 }
    }
}
