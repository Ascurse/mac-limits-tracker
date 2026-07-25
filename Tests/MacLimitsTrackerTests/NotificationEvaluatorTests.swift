import XCTest
@testable import MacLimitsTrackerCore

/// NotificationEvaluator — чистая логика событий уведомлений (issue #29):
/// переход окна через порог warning/critical (один раз, с ре-армом после
/// восстановления) и ресет окна по смене resetsAt. Без UNUserNotificationCenter.
final class NotificationEvaluatorTests: XCTestCase {
    private let descriptor = ProviderDescriptor(
        id: "claude", displayName: "Claude Code", shortName: "Claude",
        menuBarSymbol: "C", accentColorHex: 0xFF9E64, loginHelp: nil
    )

    private func state(
        remaining: Double?,
        resetsAt: Date? = nil,
        durationMins: Int? = 300
    ) -> ProviderState {
        let snap = LimitsSnapshot(
            loggedIn: true, plan: nil,
            windows: [SnapshotWindow(
                windowDurationMins: durationMins,
                usedPercent: remaining.map { 100 - $0 },
                resetsAt: resetsAt
            )],
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: nil, fetchedAt: Date()
        )
        return ProviderState(descriptor: descriptor, snapshot: snap)
    }

    // (a) normal → warning: ровно одно событие crossing.
    /// Пин (bd mac-limits-tracker-1og, ревью N1): error-снапшот (windows == nil)
    /// пропускается, baseline severity/resetsAt не трогается — после аварии
    /// дедуп сравнивает с до-аварийной базой, ложных событий нет.
    func test_errorSnapshot_skippedAndBaselinePreserved() {
        let evaluator = NotificationEvaluator()
        _ = evaluator.evaluate(states: [state(remaining: 50)], thresholds: .standard)

        let errorSnap = LimitsSnapshot(
            loggedIn: true, plan: nil, windows: nil,
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: "network down", fetchedAt: Date()
        )
        let errorState = ProviderState(descriptor: descriptor, snapshot: errorSnap,
                                       lastGoodSnapshot: state(remaining: 50).snapshot)
        XCTAssertEqual(evaluator.evaluate(states: [errorState], thresholds: .standard), [])

        // baseline не сброшен: то же значение после аварии — дедуп, событий нет.
        XCTAssertEqual(evaluator.evaluate(states: [state(remaining: 50)], thresholds: .standard), [])
        // а реальное ухудшение против до-аварийной базы — ловится.
        let events = evaluator.evaluate(states: [state(remaining: 10)], thresholds: .standard)
        XCTAssertEqual(events.count, 1)
    }

    func test_crossingIntoWarning_emitsOnce() {
        let e = NotificationEvaluator()
        XCTAssertEqual(e.evaluate(states: [state(remaining: 80)], thresholds: .standard), [])
        let events = e.evaluate(states: [state(remaining: 30)], thresholds: .standard)
        XCTAssertEqual(events, [NotificationEvent(
            providerId: "claude", providerName: "Claude Code", windowLabel: "5h",
            kind: .thresholdCrossed(severity: .warning, remainingPercent: 30)
        )])
    }

    // (b) warning → critical: новое событие (ухудшение зоны).
    func test_escalationToCritical_emitsAgain() {
        let e = NotificationEvaluator()
        _ = e.evaluate(states: [state(remaining: 30)], thresholds: .standard)
        let events = e.evaluate(states: [state(remaining: 10)], thresholds: .standard)
        XCTAssertEqual(events.map(\.kind),
                       [.thresholdCrossed(severity: .critical, remainingPercent: 10)])
    }

    // (c) удержание в warning между опросами: дедупликация, событий нет.
    func test_stayingInWarning_isDeduplicated() {
        let e = NotificationEvaluator()
        _ = e.evaluate(states: [state(remaining: 30)], thresholds: .standard)
        XCTAssertEqual(e.evaluate(states: [state(remaining: 28)], thresholds: .standard), [])
        XCTAssertEqual(e.evaluate(states: [state(remaining: 25)], thresholds: .standard), [])
    }

    // (d) восстановление выше порога — без события, но ре-арм: следующее
    // пересечение порога снова уведомляет.
    func test_recovery_rearmsCrossingNotification() {
        let e = NotificationEvaluator()
        _ = e.evaluate(states: [state(remaining: 30)], thresholds: .standard)
        XCTAssertEqual(e.evaluate(states: [state(remaining: 90)], thresholds: .standard), [])
        let events = e.evaluate(states: [state(remaining: 35)], thresholds: .standard)
        XCTAssertEqual(events.map(\.kind),
                       [.thresholdCrossed(severity: .warning, remainingPercent: 35)])
    }

    // Первое наблюдение окна уже за порогом (запуск приложения): считаем
    // переходом из normal — уведомляем один раз.
    func test_firstSightingBelowThreshold_emitsCrossing() {
        let e = NotificationEvaluator()
        let events = e.evaluate(states: [state(remaining: 10)], thresholds: .standard)
        XCTAssertEqual(events.map(\.kind),
                       [.thresholdCrossed(severity: .critical, remainingPercent: 10)])
    }

    // (e) смена resetsAt у уже наблюдавшегося окна = ресет окна.
    func test_resetsAtChange_emitsWindowReset() {
        let e = NotificationEvaluator()
        let t1 = Date(timeIntervalSince1970: 10_000)
        let t2 = Date(timeIntervalSince1970: 28_000)
        _ = e.evaluate(states: [state(remaining: 80, resetsAt: t1)], thresholds: .standard)
        let events = e.evaluate(states: [state(remaining: 99, resetsAt: t2)], thresholds: .standard)
        XCTAssertEqual(events, [NotificationEvent(
            providerId: "claude", providerName: "Claude Code", windowLabel: "5h",
            kind: .windowReset
        )])
    }

    // Первое появление resetsAt (базовая линия) — не ресет.
    func test_firstSightingOfResetsAt_isBaselineNotReset() {
        let e = NotificationEvaluator()
        let t1 = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(e.evaluate(states: [state(remaining: 80, resetsAt: t1)],
                                  thresholds: .standard), [])
    }

    // (f) слот без данных (usedPercent == nil) пропускается.
    func test_windowWithoutData_isSkipped() {
        let e = NotificationEvaluator()
        XCTAssertEqual(e.evaluate(states: [state(remaining: nil)], thresholds: .standard), [])
        XCTAssertEqual(e.evaluate(states: [state(remaining: nil)], thresholds: .standard), [])
    }

    // (g) кастомные пороги (issue #25) управляют пересечениями.
    func test_customThresholds_areRespected() {
        let lax = SeverityThresholds(warningRemaining: 20, criticalRemaining: 5)
        let e = NotificationEvaluator()
        _ = e.evaluate(states: [state(remaining: 80)], thresholds: lax)
        // 25% остатка: стандартно warning, при мягких порогах — normal, события нет.
        XCTAssertEqual(e.evaluate(states: [state(remaining: 25)], thresholds: lax), [])
        XCTAssertEqual(e.evaluate(states: [state(remaining: 15)], thresholds: lax).map(\.kind),
                       [.thresholdCrossed(severity: .warning, remainingPercent: 15)])
    }

    // Окна разных провайдеров/длительностей дедуплицируются независимо.
    func test_dedupState_isPerProviderAndWindow() {
        let e = NotificationEvaluator()
        _ = e.evaluate(states: [state(remaining: 30, durationMins: 300)], thresholds: .standard)
        // То же значение, но недельное окно — отдельное событие.
        let events = e.evaluate(states: [state(remaining: 30, durationMins: 10080)],
                                thresholds: .standard)
        XCTAssertEqual(events.map(\.windowLabel), ["Weekly"])
    }
}
