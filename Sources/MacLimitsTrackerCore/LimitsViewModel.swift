import Foundation
import SwiftUI

/// Состояние статус-бара: агрегирует данные по обоим провайдерам, таймер автообновления.
@MainActor
public final class LimitsViewModel: ObservableObject {
    @Published public var claude: ClaudeStatus?
    @Published public var codex: CodexStatus?
    @Published public var isRefreshing = false
    @Published public var autoRefresh = true

    private let claudeProvider: ClaudeLimitsProvider
    private let codexProvider: CodexLimitsProvider
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?

    public init(
        claudeProvider: ClaudeLimitsProvider = ClaudeLimitsProvider(),
        codexProvider: CodexLimitsProvider = CodexLimitsProvider(),
        autoRefreshInterval: TimeInterval = 300
    ) {
        self.claudeProvider = claudeProvider
        self.codexProvider = codexProvider
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
        let claude = claudeProvider
        let codex = codexProvider
        isRefreshing = true
        refreshTask = Task { [weak self] in
            async let c = claude.fetch()
            async let x = codex.fetch()
            let (claudeStatus, codexStatus) = await (c, x)
            if Task.isCancelled { return }
            await MainActor.run {
                self?.claude = claudeStatus
                self?.codex = codexStatus
                self?.isRefreshing = false
            }
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