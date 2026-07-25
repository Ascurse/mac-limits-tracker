import Foundation

/// Текущее состояние одного провайдера в реестре: дескриптор + последний снапшот.
/// `snapshot == nil` — ещё грузится (первый fetch не завершился).
public struct ProviderState: Identifiable, Equatable {
    public let descriptor: ProviderDescriptor
    public let snapshot: LimitsSnapshot?
    /// Последний успешный снапшот, сохраняемый при сетевой ошибке для stale-отображения.
    public let lastGoodSnapshot: LimitsSnapshot?
    public var id: String { descriptor.id }

    public init(
        descriptor: ProviderDescriptor,
        snapshot: LimitsSnapshot?,
        lastGoodSnapshot: LimitsSnapshot? = nil
    ) {
        self.descriptor = descriptor
        self.snapshot = snapshot
        self.lastGoodSnapshot = lastGoodSnapshot
    }
}
