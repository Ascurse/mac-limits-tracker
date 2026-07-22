import Foundation

/// Текущее состояние одного провайдера в реестре: дескриптор + последний снапшот.
/// `snapshot == nil` — ещё грузится (первый fetch не завершился).
public struct ProviderState: Identifiable, Equatable {
    public let descriptor: ProviderDescriptor
    public let snapshot: LimitsSnapshot?
    public var id: String { descriptor.id }

    public init(descriptor: ProviderDescriptor, snapshot: LimitsSnapshot?) {
        self.descriptor = descriptor
        self.snapshot = snapshot
    }
}
