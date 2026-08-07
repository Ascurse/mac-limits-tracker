import Foundation
import SwiftUI

/// Источник оценки стоимости — протокол для подмены в тестах: реальный
/// сервис (`LocalCostEstimateService`) читает локальные логи CLI, в тестах
/// домашняя директория не трогается.
public protocol CostEstimating: Sendable {
    func estimate(period: CostPeriod, now: Date, calendar: Calendar) -> CostEstimateResult
}

extension LocalCostEstimateService: CostEstimating {}

/// Состояние статус-бара: агрегирует состояния зарегистрированных провайдеров, таймер автообновления.
@MainActor
public final class LimitsViewModel: ObservableObject {
    @Published public private(set) var states: [ProviderState]
    /// Настройки провайдеров реестра (включая выключенные) и id dynamic-спек —
    /// даже отсутствующих, чтобы `save` не затирал их persisted-запись (gh #27).
    /// UI настроек читает отфильтрованную проекцию `providerSettingsWithDescriptors`.
    @Published public private(set) var providerSettings: [ProviderSetting]
    @Published public var isRefreshing = false
    /// Автообновление — персистится в AppSettingsStore.
    @Published public private(set) var autoRefresh: Bool
    /// Интервал автообновления — персистится в AppSettingsStore (issue #24).
    @Published public private(set) var autoRefreshInterval: RefreshInterval
    /// Пороги severity — персистятся в AppSettingsStore (issue #25).
    @Published public private(set) var severityThresholds: SeverityThresholds
    /// Уведомления о порогах и ресетах окон — персистятся в AppSettingsStore (issue #29).
    @Published public private(set) var notificationsEnabled: Bool
    /// Тема оформления — персистится в AppSettingsStore.
    @Published public private(set) var appTheme: AppTheme
    /// Режим отображения в меню-баре — персистится в AppSettingsStore.
    @Published public private(set) var menuBarDisplayMode: MenuBarDisplayMode
    /// Показывать десктопный виджет — персистится в AppSettingsStore.
    @Published public private(set) var showDesktopWidget: Bool
    /// Показывать 7-дневные графики тренда — персистится в AppSettingsStore
    /// (bd mac-limits-tracker-gld.4). Один флаг на все темы и обе поверхности.
    @Published public private(set) var showUsageTrends: Bool
    /// Последняя оценка стоимости из локальных логов (агрегат по CLI).
    /// nil до первого refreshCostEstimate(). Обновляется НЕЗАВИСИМО от
    /// refresh() квот — отдельный путь и отдельный Task (bd 725.2).
    @Published public private(set) var costEstimate: CostEstimateResult?

    private var allProviders: [any LimitsProvider]
    private let dynamicProviders: [DynamicProviderSpec]
    private let settingsStore: ProviderSettingsStore
    private let appSettingsStore: AppSettingsStore
    private let historyStore: HistoryStore
    private let costService: any CostEstimating
    private var refreshTask: Task<Void, Never>?
    private var costRefreshTask: Task<Void, Never>?
    private var timer: Timer?
    /// Идемпотентность start(): повторные вызовы от ре-активации поверхностей — no-op.
    private var hasStarted = false
    /// Последний успешный снапшот по id провайдера. Переживает disable/enable и
    /// исчезновение/появление dynamic-провайдера, чтобы stale-отображение не
    /// сбрасывалось при смене состава реестра.
    private var lastGoodSnapshots: [String: LimitsSnapshot] = [:]

    public init(
        providers: [any LimitsProvider] = ProviderRegistry.makeDefault(),
        settingsStore: ProviderSettingsStore = ProviderSettingsStore(),
        appSettingsStore: AppSettingsStore = AppSettingsStore(),
        historyStore: HistoryStore = HistoryStore(),
        dynamicProviders: [DynamicProviderSpec] = [],
        costService: any CostEstimating = LocalCostEstimateService()
    ) {
        self.allProviders = providers
        self.dynamicProviders = dynamicProviders
        self.settingsStore = settingsStore
        self.appSettingsStore = appSettingsStore
        self.historyStore = historyStore
        self.costService = costService
        let settings = settingsStore.settings(for: Self.settingsIds(providers: providers, specs: dynamicProviders))
        self.providerSettings = settings
        self.states = Self.enabledProviders(providers, settings: settings)
            .map { ProviderState(descriptor: $0.descriptor, snapshot: nil) }
        self.autoRefresh = appSettingsStore.autoRefreshEnabled
        self.autoRefreshInterval = appSettingsStore.refreshInterval
        self.severityThresholds = appSettingsStore.severityThresholds
        self.notificationsEnabled = appSettingsStore.notificationsEnabled
        self.appTheme = appSettingsStore.appTheme
        self.menuBarDisplayMode = appSettingsStore.menuBarDisplayMode
        self.showDesktopWidget = appSettingsStore.showDesktopWidget
        self.showUsageTrends = appSettingsStore.showUsageTrends
    }

    /// Id, по которым ведутся настройки: реестр + id dynamic-спек, включая
    /// отсутствующие — `save` пишет порядок/выключенность целиком, и без
    /// записи отсутствующего провайдера его persisted-настройки стирались бы
    /// до возвращения (gh #27, ревью B1).
    private static func settingsIds(
        providers: [any LimitsProvider], specs: [DynamicProviderSpec]
    ) -> [String] {
        var ids = providers.map { $0.descriptor.id }
        var idSet = Set(ids)
        for spec in specs where !idSet.contains(spec.id) {
            ids.append(spec.id)
            idSet.insert(spec.id)
        }
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
        costRefreshTask?.cancel()
    }

    public func start(_ initial: Bool = true) {
        guard !hasStarted else { return }
        hasStarted = true
        if initial {
            refresh()
            refreshCostEstimate()
        }
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
                let existingById = Dictionary(uniqueKeysWithValues: self.states.map { ($0.descriptor.id, $0) })
                self.states = zip(providers, snapshots).map { provider, snapshot in
                    let existing = existingById[provider.descriptor.id]
                    let previousGood = existing?.lastGoodSnapshot ?? self.lastGoodSnapshots[provider.descriptor.id]
                    let lastGood = SnapshotResolver.isGood(snapshot) ? snapshot : previousGood
                    if let lastGood { self.lastGoodSnapshots[provider.descriptor.id] = lastGood }
                    return ProviderState(descriptor: provider.descriptor, snapshot: snapshot, lastGoodSnapshot: lastGood)
                }
                self.recordHistory(providers: providers, snapshots: snapshots)
                self.isRefreshing = false
            }
        }
    }

    /// Период агрегации оценки стоимости, показываемой в попапе.
    private static let costEstimatePeriod: CostPeriod = .last7Days

    /// Обновление оценки стоимости — собственный путь, НЕЗАВИСИМЫЙ от
    /// refresh() квот: свой Task со своей дисциплиной отмены (как у
    /// refreshTask), не отменяется refresh() и не блокируется ошибками
    /// провайдеров. Чтение локальных логов — потенциально медленный
    /// СИНХРОННЫЙ I/O, поэтому Task.detached: обычный Task унаследовал бы
    /// MainActor и заблокировал бы главный поток на всё время сканирования
    /// (в отличие от refresh(), где fetchAll сразу уходит в await).
    public func refreshCostEstimate() {
        costRefreshTask?.cancel()
        let service = costService
        costRefreshTask = Task.detached { [weak self] in
            let result = service.estimate(period: Self.costEstimatePeriod, now: Date(), calendar: .current)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.costEstimate = result }
        }
    }

    private func recordHistory(providers: [any LimitsProvider], snapshots: [LimitsSnapshot]) {
        for (provider, snapshot) in zip(providers, snapshots) {
            guard snapshot.providerError == nil,
                  snapshot.usageError == nil,
                  let windows = snapshot.windows else { continue }
            for window in windows {
                guard let windowMins = window.windowDurationMins,
                      let usedPercent = window.usedPercent else { continue }
                self.historyStore.append(
                    providerId: provider.descriptor.id,
                    windowMins: windowMins,
                    fetchedAt: snapshot.fetchedAt,
                    usedPercent: usedPercent,
                    resetsAt: window.resetsAt
                )
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
                ?? ProviderState(descriptor: provider.descriptor, snapshot: nil,
                                 lastGoodSnapshot: lastGoodSnapshots[provider.descriptor.id])
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

    public func historySamples(providerId: String) -> [UsageSample] {
        historyStore.samples(providerId: providerId, since: .distantPast)
    }

    func startTimer() {
        timer?.invalidate()
        guard autoRefresh else { return }
        timer = Timer.scheduledTimer(withTimeInterval: autoRefreshInterval.timeInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
                self?.refreshCostEstimate()
            }
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
        appSettingsStore.autoRefreshEnabled = value
        if value { startTimer() } else { timer?.invalidate(); timer = nil }
    }

    /// Меняет тему оформления: персистит в AppSettingsStore.
    public func setAppTheme(_ theme: AppTheme) {
        appTheme = theme
        appSettingsStore.appTheme = theme
    }

    /// Меняет режим отображения в меню-баре: персистит в AppSettingsStore.
    public func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
        menuBarDisplayMode = mode
        appSettingsStore.menuBarDisplayMode = mode
    }

    /// Включает/выключает десктопный виджет: персистит в AppSettingsStore.
    public func setShowDesktopWidget(_ show: Bool) {
        showDesktopWidget = show
        appSettingsStore.showDesktopWidget = show
    }

    /// Включает/выключает показ 7-дневных графиков тренда: персистит в
    /// AppSettingsStore. Чисто presentation-переключатель — не трогает
    /// снапшоты/историю и не вызывает refresh/сетевые запросы.
    public func setShowUsageTrends(_ show: Bool) {
        showUsageTrends = show
        appSettingsStore.showUsageTrends = show
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

    public func setWarningThreshold(_ warning: Double, maxCriticalOptions: [Double]) {
        let maxCritical = maxCriticalOptions.filter { $0 < warning }.max() ?? warning - 1
        let critical = min(severityThresholds.criticalRemaining, maxCritical)
        setSeverityThresholds(SeverityThresholds(
            warningRemaining: warning, criticalRemaining: critical))
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

    /// Применяет результат drag-переупорядочивания (список видимых id) к полному
    /// `providerSettings`: перемещает `ids` блоком перед `targetId` (в конец при
    /// `nil`/неизвестном id), не трогая позицию и выключенность скрытых
    /// dynamic-провайдеров, отсутствующих среди `ids` (bd mac-limits-tracker-med.1).
    public func reorderProviders(_ ids: [String], before targetId: String?) {
        providerSettings = providerSettings.reordered(ids: ids, before: targetId)
        applyProviderSettingsChange()
    }

    /// Сбрасывает порядок к каноническому (реестр + id dynamic-спек, тот же union,
    /// что и в settingsIds), сохраняя выключенность каждого провайдера как есть.
    public func resetProviderOrder() {
        let canonicalIds = Self.settingsIds(providers: allProviders, specs: dynamicProviders)
        let enabledById = Dictionary(uniqueKeysWithValues: providerSettings.map { ($0.id, $0.isEnabled) })
        providerSettings = canonicalIds.map { ProviderSetting(id: $0, isEnabled: enabledById[$0] ?? true) }
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
                ?? ProviderState(descriptor: provider.descriptor, snapshot: nil,
                                 lastGoodSnapshot: lastGoodSnapshots[provider.descriptor.id])
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
            let resolved = SnapshotResolver.resolve(state)
            parts.append(resolved.snapshot?.menuTitle(shortName: state.descriptor.shortName)
                          ?? state.descriptor.shortName)
            for w in resolved.snapshot?.windows ?? [] {
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
