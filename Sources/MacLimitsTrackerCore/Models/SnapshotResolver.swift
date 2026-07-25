import Foundation

/// Результат разрешения состояния провайдера в то, что видит UI:
/// снапшот для отрисовки, факт «данные устарели» и ошибка для мелкого лейбла.
public struct ResolvedDisplay: Equatable {
    public let snapshot: LimitsSnapshot?
    public let isStale: Bool
    public let error: String?
}

/// Разрешает `ProviderState` в `ResolvedDisplay` по правилам stale-данных.
public enum SnapshotResolver {
    /// Возвращает снапшот для отображения и метаданные об ошибках/устаревании.
    public static func resolve(_ state: ProviderState) -> ResolvedDisplay {
        guard let snapshot = state.snapshot else {
            return ResolvedDisplay(snapshot: nil, isStale: false, error: nil)
        }

        if let providerError = snapshot.providerError {
            if let lastGood = state.lastGoodSnapshot {
                return ResolvedDisplay(snapshot: lastGood, isStale: true, error: providerError)
            }
            return ResolvedDisplay(snapshot: snapshot, isStale: false, error: nil)
        }

        if let usageError = snapshot.usageError,
           snapshot.windows == nil,
           let lastGood = state.lastGoodSnapshot,
           lastGood.windows != nil {
            // rateLimitReachedType не переносим: это транзиентное состояние,
            // и stale-копия рисовала бы его как свежую красную ошибку рядом с сетевой.
            let merged = LimitsSnapshot(
                loggedIn: snapshot.loggedIn,
                plan: snapshot.plan,
                windows: lastGood.windows,
                creditsBalance: lastGood.creditsBalance,
                rateLimitReachedType: nil,
                details: snapshot.details,
                daysUntilRenewal: snapshot.daysUntilRenewal,
                renewalDate: snapshot.renewalDate,
                usageError: snapshot.usageError,
                providerError: snapshot.providerError,
                fetchedAt: lastGood.fetchedAt
            )
            return ResolvedDisplay(snapshot: merged, isStale: true, error: usageError)
        }

        return ResolvedDisplay(snapshot: snapshot, isStale: false, error: nil)
    }

    /// Считаем снапшот «хорошим», если в нём нет ни provider-, ни usage-ошибки.
    public static func isGood(_ snapshot: LimitsSnapshot) -> Bool {
        snapshot.providerError == nil && snapshot.usageError == nil
    }
}
