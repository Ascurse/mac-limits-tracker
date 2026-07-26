import Foundation

public struct UsageSample: Codable, Equatable, Sendable {
    public let providerId: String
    public let windowMins: Int
    public var fetchedAt: Date
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(
        providerId: String,
        windowMins: Int,
        fetchedAt: Date,
        usedPercent: Double,
        resetsAt: Date?
    ) {
        self.providerId = providerId
        self.windowMins = windowMins
        self.fetchedAt = fetchedAt
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}
