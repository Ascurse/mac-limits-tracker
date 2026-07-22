import Foundation
import SwiftUI

/// Состояние статус-бара: агрегирует состояния зарегистрированных провайдеров, таймер автообновления.
@MainActor
public final class LimitsViewModel: ObservableObject {
    @Published public private(set) var states: [ProviderState]
    @Published public var isRefreshing = false
    @Published public var autoRefresh = true

    private let providers: [any LimitsProvider]
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?

    public init(
        providers: [any LimitsProvider] = ProviderRegistry.makeDefault(),
        autoRefreshInterval: TimeInterval = 300
    ) {
        self.providers = providers
        self.states = providers.map { ProviderState(descriptor: $0.descriptor, snapshot: nil) }
        self.autoRefreshInterval = autoRefreshInterval
    }

    deinit {
        timer?.invalidate()
        refreshTask?.cancel()
    }

    let autoRefreshInterval: TimeInterval

    public func start(_ initial: Bool = true) {
        if initial { refresh() }
        startTimer()
    }

    public func refresh() {
        refreshTask?.cancel()
        let providers = self.providers
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
        timer = Timer.scheduledTimer(withTimeInterval: autoRefreshInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    public func setAutoRefresh(_ value: Bool) {
        autoRefresh = value
        if value { startTimer() } else { timer?.invalidate(); timer = nil }
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
