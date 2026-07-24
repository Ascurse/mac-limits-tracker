import Combine
import Foundation
import UserNotifications
import MacLimitsTrackerCore

/// Доставка событий NotificationEvaluator через UNUserNotificationCenter (issue #29).
/// Вся логика переходов/дедупликации — в Core (NotificationEvaluator), здесь только
/// подписка на состояния, запрос разрешения и отправка UN-запросов.
@MainActor
final class NotificationManager: NSObject {
    private let viewModel: LimitsViewModel
    private let evaluator = NotificationEvaluator()
    private var cancellables: Set<AnyCancellable> = []

    /// В dev-режиме (`swift run`, исполняемый файл без Info.plist) UN-вызовы
    /// падают/молчат — менеджер превращается в no-op.
    private let isBundled = Bundle.main.bundleIdentifier != nil

    init(viewModel: LimitsViewModel) {
        self.viewModel = viewModel
        super.init()

        guard isBundled else { return }
        UNUserNotificationCenter.current().delegate = self

        viewModel.$states
            .sink { [weak self] states in
                self?.deliverEvents(for: states)
            }
            .store(in: &cancellables)

        viewModel.$notificationsEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled { self?.requestAuthorization() }
            }
            .store(in: &cancellables)
    }

    private func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func deliverEvents(for states: [ProviderState]) {
        guard viewModel.notificationsEnabled else { return }
        let events = evaluator.evaluate(states: states, thresholds: viewModel.severityThresholds)
        for event in events {
            let content = UNMutableNotificationContent()
            content.sound = .default
            switch event.kind {
            case .thresholdCrossed(let severity, let remaining):
                content.title = "\(event.providerName): \(event.windowLabel) window \(severity == .critical ? "critical" : "low")"
                content.body = "\(Int(remaining))% remaining"
            case .windowReset:
                content.title = "\(event.providerName): \(event.windowLabel) window reset"
                content.body = "Limit window has reset"
            }
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { _ in }
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Показывать баннер, даже когда приложение активно (menu-bar приложение
    /// почти всегда «активно» с точки зрения UN).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
