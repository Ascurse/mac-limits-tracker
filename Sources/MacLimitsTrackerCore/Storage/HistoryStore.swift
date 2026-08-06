import Foundation

private struct HistoryFile: Codable {
    let version: Int
    var samples: [UsageSample]
}

/// Хранит историю usage-показаний в JSON на диске. Дедупликация подряд
/// идущих одинаковых точек уменьшает объём файла и убирает плато на
/// sparkline; прунинг старше 7 дней ограничивает рост истории.
public final class HistoryStore {
    private static let sharedDecoder = JSONDecoder()
    private static let sharedEncoder = JSONEncoder()
    private static let fileName = "history.json"
    private static let currentVersion = 1
    private static let retentionDays: TimeInterval = 7

    private let directory: URL
    private let fileURL: URL
    private var samples: [UsageSample]

    private struct IndexKey: Hashable {
        let providerId: String
        let windowMins: Int
    }
    private var lastIndexByKey: [IndexKey: Int] = [:]

    public init(
        directory: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("dev.ascurse.MacLimitsTracker", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("dev.ascurse.MacLimitsTracker", isDirectory: true)
    ) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent(Self.fileName)
        self.samples = Self.load(from: fileURL)
        rebuildIndices()
    }

    private func rebuildIndices() {
        lastIndexByKey.removeAll(keepingCapacity: true)
        for (index, sample) in samples.enumerated() {
            let key = IndexKey(providerId: sample.providerId, windowMins: sample.windowMins)
            lastIndexByKey[key] = index
        }
    }

    public func append(
        providerId: String,
        windowMins: Int,
        fetchedAt: Date,
        usedPercent: Double,
        resetsAt: Date?
    ) {
        let newSample = UsageSample(
            providerId: providerId,
            windowMins: windowMins,
            fetchedAt: fetchedAt,
            usedPercent: usedPercent,
            resetsAt: resetsAt
        )

        let key = IndexKey(providerId: newSample.providerId, windowMins: newSample.windowMins)

        if let lastIndex = lastIndexByKey[key],
            samples[lastIndex].usedPercent == newSample.usedPercent,
            samples[lastIndex].resetsAt == newSample.resetsAt {
            samples[lastIndex].fetchedAt = newSample.fetchedAt
        } else {
            samples.append(newSample)
            lastIndexByKey[key] = samples.count - 1
        }

        let cutoff = newSample.fetchedAt.addingTimeInterval(-Self.retentionDays * 24 * 3600)
        let oldCount = samples.count
        samples.removeAll { $0.fetchedAt < cutoff }
        if samples.count != oldCount {
            rebuildIndices()
        }

        persist()
    }

    /// Сэмплы одного окна — гарантированно в хронологическом порядке: `append`
    /// либо дописывает в конец, либо обновляет последний сэмпл этого же ключа.
    /// Поэтому потребителям пересортировка не нужна.
    public func samples(
        providerId: String,
        windowMins: Int,
        since: Date
    ) -> [UsageSample] {
        samples
            .filter {
                $0.providerId == providerId
                    && $0.windowMins == windowMins
                    && $0.fetchedAt >= since
            }
    }

    /// Сэмплы всех окон провайдера. ВНИМАНИЕ: хронологический порядок здесь
    /// гарантирован только внутри одного `windowMins` — дедупликация в `append`
    /// сдвигает `fetchedAt` у сэмпла, стоящего раньше сэмплов других окон.
    /// Потребитель обязан сначала сгруппировать по `windowMins`.
    public func samples(
        providerId: String,
        since: Date
    ) -> [UsageSample] {
        samples
            .filter {
                $0.providerId == providerId
                    && $0.fetchedAt >= since
            }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let file = HistoryFile(version: Self.currentVersion, samples: samples)
            let data = try Self.sharedEncoder.encode(file)

            let tmpURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
            let created = FileManager.default.createFile(
                atPath: tmpURL.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            )
            guard created else { return }
            _ = try? FileManager.default.replaceItemAt(fileURL, withItemAt: tmpURL)
        } catch {
            // Молча игнорируем ошибки записи: следующий append попробует снова.
        }
    }

    private static func load(from fileURL: URL) -> [UsageSample] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? Self.sharedDecoder.decode(HistoryFile.self, from: data),
              file.version == currentVersion
        else { return [] }
        return file.samples
    }
}
