import Foundation

private struct HistoryFile: Codable {
    let version: Int
    var samples: [UsageSample]
}

/// Хранит историю usage-показаний в JSON на диске. Дедупликация подряд
/// идущих одинаковых точек уменьшает объём файла и убирает плато на
/// sparkline; прунинг старше 7 дней ограничивает рост истории.
public final class HistoryStore {
    private static let fileName = "history.json"
    private static let currentVersion = 1
    private static let retentionDays: TimeInterval = 7

    private let directory: URL
    private let fileURL: URL
    private var samples: [UsageSample]

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

        // Дедуп ищет последнюю точку именно этого (providerId, windowMins):
        // append'ы разных окон/провайдеров чередуются внутри одного refresh.
        if let lastIndex = samples.lastIndex(where: {
            $0.providerId == newSample.providerId && $0.windowMins == newSample.windowMins
        }),
            samples[lastIndex].usedPercent == newSample.usedPercent,
            samples[lastIndex].resetsAt == newSample.resetsAt {
            samples[lastIndex].fetchedAt = newSample.fetchedAt
        } else {
            samples.append(newSample)
        }

        let cutoff = newSample.fetchedAt.addingTimeInterval(-Self.retentionDays * 24 * 3600)
        samples.removeAll { $0.fetchedAt < cutoff }

        persist()
    }

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
            .sorted { $0.fetchedAt < $1.fetchedAt }
    }

    public func samples(
        providerId: String,
        since: Date
    ) -> [UsageSample] {
        samples
            .filter {
                $0.providerId == providerId
                    && $0.fetchedAt >= since
            }
            .sorted { $0.fetchedAt < $1.fetchedAt }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let file = HistoryFile(version: Self.currentVersion, samples: samples)
            let data = try JSONEncoder().encode(file)

            let tmpURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
            let created = FileManager.default.createFile(
                atPath: tmpURL.path,
                contents: data,
                attributes: nil
            )
            guard created else { return }
            _ = try? FileManager.default.replaceItemAt(fileURL, withItemAt: tmpURL)
        } catch {
            // Молча игнорируем ошибки записи: следующий append попробует снова.
        }
    }

    private static func load(from fileURL: URL) -> [UsageSample] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(HistoryFile.self, from: data),
              file.version == currentVersion
        else { return [] }
        return file.samples
    }
}
