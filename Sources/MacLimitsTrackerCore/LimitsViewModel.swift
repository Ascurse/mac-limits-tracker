import Foundation
import SwiftUI

/// Состояние статус-бара: агрегирует состояния зарегистрированных провайдеров, таймер автообновления.
@MainActor
public final class LimitsViewModel: ObservableObject {
    @Published public private(set) var states: [ProviderState]
    /// Настройки провайдеров реестра (включая выключенные) и id dynamic-спек —
    /// даже отсутствующих, чтобы `save` не затирал их persisted-запись (gh #27).
    /// UI настроек читает отфильтрованную проекцию `providerSettingsWithDescriptors`.
    @Published public private(set) var providerSettings: [ProviderSetting]
    @Published public var isRefreshing = false
    @Published public var autoRefresh = true
    /// Интервал автообновления — персистится в AppSettingsStore (issue #24).
    @Published public private(set) var autoRefreshInterval: RefreshInterval
    /// Пороги severity — персистятся в AppSettingsStore (issue #25).
    @Published public private(set) var severityThresholds: SeverityThresholds
    /// Уведомления о порогах и ресетах окон — персистятся в AppSettingsStore (issue #29).
    @Published public private(set) var notificationsEnabled: Bool

    private var allProviders: [any LimitsProvider]
    private let dynamicProviders: [DynamicProviderSpec]
    private let settingsStore: ProviderSettingsStore
    private let appSettingsStore: AppSettingsStore
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?

    public init(
        providers: [any LimitsProvider] = ProviderRegistry.makeDefault(),
        settingsStore: ProviderSettingsStore = ProviderSettingsStore(),
        appSettingsStore: AppSettingsStore = AppSettingsStore(),
        dynamicProviders: [DynamicProviderSpec] = []
    ) {
        self.allProviders = providers
        self.dynamicProviders = dynamicProviders
        self.settingsStore = settingsStore
        self.appSettingsStore = appSettingsStore
        let settings = settingsStore.settings(for: Self.settingsIds(providers: providers, specs: dynamicProviders))
        self.providerSettings = settings
        self.states = Self.enabledProviders(providers, settings: settings)
            .map { ProviderState(descriptor: $0.descriptor, snapshot: nil) }
        self.autoRefreshInterval = appSettingsStore.refreshInterval
        self.severityThresholds = appSettingsStore.severityThresholds
        self.notificationsEnabled = appSettingsStore.notificationsEnabled
    }

    /// Id, по которым ведутся настройки: реестр + id dynamic-спек, включая
    /// отсутствующие — `save` пишет порядок/выключенность целиком, и без
    /// записи отсутствующего провайдера его persisted-настройки стирались бы
    /// до возвращения (gh #27, ревью B1).
    private static func settingsIds(
        providers: [any LimitsProvider], specs: [DynamicProviderSpec]
    ) -> [String] {
        var ids = providers.map { $0.descriptor.id }
        for spec in specs where !ids.contains(spec.id) { ids.append(spec.id) }
        return ids
    }

    /// Включённые провайдеры в порядке настроек — то, что реально опрашивается и отображается.
    private static func enabledProviders(
        _ providers: [any LimitsProvider], settings: [ProviderSetting]
    ) -> [any LimitsProvider] {
        let byId = Dictionary(uniqueKeysWithValues: providers.map { ($0.descriptor.id, $0) })
        return settings.filter(\.isEnabled).compactMap { byId[$0.id] }
    }

    deinit {
        timer?.invalidate()
        refreshTask?.cancel()
    }

    public func start(_ initial: Bool = true) {
        if initial { refresh() }
        startTimer()
    }

    public func refresh() {
        reconcileDynamicProviders()
        refreshTask?.cancel()
        let providers = Self.enabledProviders(allProviders, settings: providerSettings)
        isRefreshing = true
        refreshTask = Task { [weak self] in
            let snapshots = await Self.fetchAll(providers)
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                self.states = zip(providers, snapshots).map { provider, snapshot in
                    ProviderState(descriptor: provider.descriptor, snapshot: snapshot)
                }
                self.isRefreshing = false
            }
        }
    }

    /// Динамическая регистрация (gh #27): провайдеры со spec перепроверяются на
    /// каждом refresh и добавляются/убираются без перезапуска приложения.
    /// Вызывается синхронно на MainActor до порождения fetch-Task, а refresh()
    /// отменяет предыдущий Task — устаревшая задача не запишет states после
    /// изменения состава (та же дисциплина, что у applyProviderSettingsChange).
    /// Настройки перечитываются через settingsStore.settings(for:), но НЕ
    /// сохраняются: persisted-запись (порядок, выключенность) переживает
    /// исчезновение и возвращение провайдера. Единственная точка вызова —
    /// refresh(): вынос наружу потребовал бы той же отмены in-flight задачи.
    private func reconcileDynamicProviders() {
        var changed = false
        for spec in dynamicProviders {
            let present = allProviders.contains { $0.descriptor.id == spec.id }
            if spec.isAvailable(), !present {
                allProviders.append(spec.makeProvider())
                changed = true
            } else if !spec.isAvailable(), present {
                allProviders.removeAll { $0.descriptor.id == spec.id }
                changed = true
            }
        }
        guard changed else { return }
        providerSettings = settingsStore.settings(for: Self.settingsIds(providers: allProviders, specs: dynamicProviders))
        let existingById = Dictionary(uniqueKeysWithValues: states.map { ($0.descriptor.id, $0) })
        states = Self.enabledProviders(allProviders, settings: providerSettings).map { provider in
            existingById[provider.descriptor.id]
                ?? ProviderState(descriptor: provider.descriptor, snapshot: nil)
        }
    }

    /// Параллельный fetch всех провайдеров реестра, результат — в порядке `providers`.
    private static func fetchAll(_ providers: [any LimitsProvider]) async -> [LimitsSnapshot] {
        await withTaskGroup(of: (Int, LimitsSnapshot).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask { (index, await provider.fetch()) }
            }
            var results = [LimitsSnapshot?](repeating: nil, count: providers.count)
            for await (index, snapshot) in group {
                results[index] = snapshot
            }
            return results.compactMap { $0 }
        }
    }

    func startTimer() {
        timer?.invalidate()
        guard autoRefresh else { return }
        timer = Timer.scheduledTimer(withTimeInterval: autoRefreshInterval.timeInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    /// Настройки провайдеров вместе с дескрипторами (включая выключенных) — для
    /// UI настроек: чекбокс включения + порядок отображения.
    public var providerSettingsWithDescriptors: [(setting: ProviderSetting, descriptor: ProviderDescriptor)] {
        let byId = Dictionary(uniqueKeysWithValues: allProviders.map { ($0.descriptor.id, $0.descriptor) })
        return providerSettings.compactMap { setting in
            byId[setting.id].map { (setting, $0) }
        }
    }

    public func setAutoRefresh(_ value: Bool) {
        autoRefresh = value
        if value { startTimer() } else { timer?.invalidate(); timer = nil }
    }

    /// Меняет интервал автообновления: персистит и перезапускает таймер,
    /// если автообновление включено (startTimer сам инвалидирует старый).
    public func setAutoRefreshInterval(_ interval: RefreshInterval) {
        autoRefreshInterval = interval
        appSettingsStore.refreshInterval = interval
        if autoRefresh { startTimer() }
    }

    public func setSeverityThresholds(_ thresholds: SeverityThresholds) {
        severityThresholds = thresholds
        appSettingsStore.severityThresholds = thresholds
    }

    public func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        appSettingsStore.notificationsEnabled = enabled
    }

    /// Включает/выключает провайдера в настройках; выключенный сразу пропадает
    /// из `states` (без ожидания следующего refresh), включённый — подхватывается
    /// ближайшим refresh().
    public func setProviderEnabled(_ isEnabled: Bool, id: String) {
        providerSettings = providerSettings.settingEnabled(id: id, isEnabled: isEnabled)
        applyProviderSettingsChange()
    }

    public func moveProviderUp(id: String) {
        providerSettings = providerSettings.movedUp(id: id)
        applyProviderSettingsChange()
    }

    public func moveProviderDown(id: String) {
        providerSettings = providerSettings.movedDown(id: id)
        applyProviderSettingsChange()
    }

    /// Персистит новые настройки и пересобирает `states`: существующие снапшоты
    /// сохраняются (не нужно ждать refresh ради переупорядочивания/выключения),
    /// вновь включённый провайдер получает `snapshot: nil` до ближайшего refresh().
    ///
    /// Если сейчас уже идёт refresh (isRefreshing), его обязательно нужно
    /// перезапустить — иначе устаревшая задача захватила старый (до изменения
    /// настроек) список провайдеров и по завершении перепишет states, вернув
    /// уже выключенного/переставленного провайдера обратно (см. bd
    /// mac-limits-tracker-6gk.2, ревью гонки). refresh() сам отменяет старый
    /// Task, поэтому проверка `Task.isCancelled` в нём не даст устаревшим
    /// данным просочиться в states.
    private func applyProviderSettingsChange() {
        settingsStore.save(providerSettings)
        let existingById = Dictionary(uniqueKeysWithValues: states.map { ($0.descriptor.id, $0) })
        let enabled = Self.enabledProviders(allProviders, settings: providerSettings)
        states = enabled.map { provider in
            existingById[provider.descriptor.id]
                ?? ProviderState(descriptor: provider.descriptor, snapshot: nil)
        }
        if isRefreshing || states.contains(where: { $0.snapshot == nil }) { refresh() }
    }
}

extension LimitsViewModel {
    /// "Claude: Max · 5h 78% · weekly 95% · Codex: Plus · 5h 99% · weekly 82%"
    /// (Д1: окна теперь показываются у всех провайдеров, не только у Claude).
    public var statusTooltip: String {
        var parts: [String] = []
        for state in states {
            parts.append(state.snapshot?.menuTitle(shortName: state.descriptor.shortName)
                          ?? state.descriptor.shortName)
            for w in state.snapshot?.windows ?? [] {
                guard let used = w.usedPercent else { continue }
                let label = RateLimitWindowLabel.labels(forDurationMins: w.windowDurationMins).long.lowercased()
                parts.append("\(label) \(Self.tooltipRemaining(used))%")
            }
        }
        return parts.joined(separator: " · ")
    }

    private static func tooltipRemaining(_ usedPercent: Double) -> String {
        String(format: "%.0f", max(0, 100 - usedPercent))
    }
}
