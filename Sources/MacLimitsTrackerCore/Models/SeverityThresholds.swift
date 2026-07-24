import Foundation

/// Пороги серьёзности по ОСТАТКУ лимита в процентах (issue #25):
/// remaining ≤ critical → critical, remaining ≤ warning → warning.
/// Инвариант: critical строго ниже warning — при инициализации critical
/// прижимается к warning - 1, иначе зона warning стала бы недостижимой.
public struct SeverityThresholds: Equatable, Sendable {
    public let warningRemaining: Double
    public let criticalRemaining: Double

    public static let standard = SeverityThresholds()

    public init(warningRemaining: Double = 40, criticalRemaining: Double = 15) {
        self.warningRemaining = warningRemaining
        self.criticalRemaining = min(criticalRemaining, warningRemaining - 1)
    }
}
