import Foundation
import OSLog
import XCTest
@testable import MacLimitsTrackerCore

/// Проверяет, что после `date` в unified log появилась запись категории
/// HistoryStore, содержащая подстроку `containing`. Требует
/// `swift test --disable-sandbox` — OSLogStore не читает журнал в песочнице.
private func assertLogged(containing needle: String, since date: Date, file: StaticString = #filePath, line: UInt = #line) {
    guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else {
        XCTFail("OSLogStore недоступен — запустите swift test --disable-sandbox", file: file, line: line)
        return
    }
    guard let position = try? store.position(date: date),
          let entries = try? store.getEntries(at: position) else {
        XCTFail("Не удалось прочитать unified log", file: file, line: line)
        return
    }
    let found = entries.contains { entry in
        guard let logEntry = entry as? OSLogEntryLog else { return false }
        return logEntry.category == "HistoryStore" && logEntry.composedMessage.contains(needle)
    }
    XCTAssertTrue(found, "Не найдена запись лога, содержащая '\(needle)'", file: file, line: line)
}

final class HistoryStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    func test_append_persistsSampleAcrossInstances() {
        let first = HistoryStore(directory: tempDirectory)
        let now = Date()
        first.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: now,
            usedPercent: 42.0,
            resetsAt: now.addingTimeInterval(3600)
        )

        let second = HistoryStore(directory: tempDirectory)
        let samples = second.samples(providerId: "claude", windowMins: 300, since: .distantPast)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.usedPercent, 42.0)
    }

    func test_append_identicalConsecutiveSample_updatesFetchedAtInsteadOfAppending() {
        let store = HistoryStore(directory: tempDirectory)
        let firstFetch = Date()
        let secondFetch = firstFetch.addingTimeInterval(60)

        store.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: firstFetch,
            usedPercent: 50.0,
            resetsAt: firstFetch.addingTimeInterval(3600)
        )
        store.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: secondFetch,
            usedPercent: 50.0,
            resetsAt: firstFetch.addingTimeInterval(3600)
        )

        let samples = store.samples(providerId: "claude", windowMins: 300, since: .distantPast)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.fetchedAt, secondFetch)
    }

    func test_append_interleavedKeys_dedupesPerProviderWindow() {
        let store = HistoryStore(directory: tempDirectory)
        let firstFetch = Date()
        let resets = firstFetch.addingTimeInterval(3600)

        store.append(providerId: "claude", windowMins: 300, fetchedAt: firstFetch, usedPercent: 50.0, resetsAt: resets)
        store.append(providerId: "claude", windowMins: 10080, fetchedAt: firstFetch, usedPercent: 30.0, resetsAt: resets)
        store.append(providerId: "claude", windowMins: 300, fetchedAt: firstFetch.addingTimeInterval(300), usedPercent: 50.0, resetsAt: resets)

        let fiveHour = store.samples(providerId: "claude", windowMins: 300, since: .distantPast)
        XCTAssertEqual(fiveHour.count, 1)
        XCTAssertEqual(fiveHour.first?.fetchedAt, firstFetch.addingTimeInterval(300))
    }

    func test_append_samePercentDifferentResetsAt_appendsNewSample() {
        let store = HistoryStore(directory: tempDirectory)
        let now = Date()

        store.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: now,
            usedPercent: 50.0,
            resetsAt: now.addingTimeInterval(3600)
        )
        store.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: now.addingTimeInterval(60),
            usedPercent: 50.0,
            resetsAt: now.addingTimeInterval(7200)
        )

        let samples = store.samples(providerId: "claude", windowMins: 300, since: .distantPast)
        XCTAssertEqual(samples.count, 2)
    }

    func test_append_olderThanRetention_isPruned() {
        let store = HistoryStore(directory: tempDirectory)
        let now = Date()
        let oldFetch = now.addingTimeInterval(-8 * 24 * 3600)

        store.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: oldFetch,
            usedPercent: 10.0,
            resetsAt: nil
        )
        store.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: now,
            usedPercent: 20.0,
            resetsAt: nil
        )

        let samples = store.samples(providerId: "claude", windowMins: 300, since: .distantPast)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.usedPercent, 20.0)
    }

    func test_samples_filtersByProviderWindowAndSince() {
        let store = HistoryStore(directory: tempDirectory)
        let now = Date()
        let cutoff = now.addingTimeInterval(-3600)

        store.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: now.addingTimeInterval(-7200),
            usedPercent: 10.0,
            resetsAt: nil
        )
        store.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: now.addingTimeInterval(-1800),
            usedPercent: 20.0,
            resetsAt: nil
        )
        store.append(
            providerId: "claude",
            windowMins: 10080,
            fetchedAt: now.addingTimeInterval(-1800),
            usedPercent: 30.0,
            resetsAt: nil
        )
        store.append(
            providerId: "codex",
            windowMins: 300,
            fetchedAt: now.addingTimeInterval(-1800),
            usedPercent: 40.0,
            resetsAt: nil
        )

        let samples = store.samples(providerId: "claude", windowMins: 300, since: cutoff)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.usedPercent, 20.0)
    }

    func test_samples_providerIdSince_returnsAllWindowsForProvider() {
        let store = HistoryStore(directory: tempDirectory)
        let now = Date()
        let resets = now.addingTimeInterval(3600)

        store.append(providerId: "claude", windowMins: 300, fetchedAt: now, usedPercent: 10.0, resetsAt: resets)
        store.append(providerId: "claude", windowMins: 10080, fetchedAt: now, usedPercent: 20.0, resetsAt: resets)
        store.append(providerId: "codex", windowMins: 300, fetchedAt: now, usedPercent: 30.0, resetsAt: resets)

        let samples = store.samples(providerId: "claude", since: .distantPast)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples.map(\.windowMins).sorted(), [300, 10080])
        XCTAssertEqual(samples.map(\.usedPercent), [10.0, 20.0])
    }

    func test_init_corruptedFile_startsEmpty() {
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        let garbage = Data("not json".utf8)
        try? garbage.write(to: tempDirectory.appendingPathComponent("history.json"))

        let store = HistoryStore(directory: tempDirectory)
        XCTAssertTrue(store.samples(providerId: "claude", windowMins: 300, since: .distantPast).isEmpty)

        let now = Date()
        store.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: now,
            usedPercent: 55.0,
            resetsAt: nil
        )
        XCTAssertEqual(
            store.samples(providerId: "claude", windowMins: 300, since: .distantPast).count,
            1
        )
    }

    func test_init_missingDirectory_createsItOnAppend() {
        let nonExistentDirectory = tempDirectory.appendingPathComponent("nested")
        let store = HistoryStore(directory: nonExistentDirectory)
        let now = Date()

        store.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: now,
            usedPercent: 33.0,
            resetsAt: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: nonExistentDirectory.path))
        let samples = store.samples(providerId: "claude", windowMins: 300, since: .distantPast)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.usedPercent, 33.0)
    }

    /// Каталог истории на самом деле файл — createDirectory гарантированно
    /// падает с ENOTDIR независимо от прав/root, детерминированная имитация
    /// "недоступного для записи каталога".
    func test_append_directoryUnwritable_doesNotCrashAndLogsFailure() {
        try? FileManager.default.createDirectory(
            at: tempDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: tempDirectory.path, contents: Data())

        let logStart = Date()
        let store = HistoryStore(directory: tempDirectory)
        let now = Date()

        store.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: now,
            usedPercent: 42.0,
            resetsAt: nil
        )

        // Не роняет процесс, in-memory состояние остаётся консистентным.
        let samples = store.samples(providerId: "claude", windowMins: 300, since: .distantPast)
        XCTAssertEqual(samples.count, 1)

        assertLogged(containing: "каталог", since: logStart)
    }

    func test_persist_replaceItemFails_removesOrphanedTmpFile() {
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let historyURL = tempDirectory.appendingPathComponent("history.json")
        FileManager.default.createFile(atPath: historyURL.path, contents: Data())
        // immutable-флаг делает replaceItemAt гарантированно неуспешным независимо от прав/root.
        try? FileManager.default.setAttributes([.immutable: true], ofItemAtPath: historyURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: historyURL.path) }

        let logStart = Date()
        let store = HistoryStore(directory: tempDirectory)
        store.append(
            providerId: "claude",
            windowMins: 300,
            fetchedAt: Date(),
            usedPercent: 10.0,
            resetsAt: nil
        )

        let leftoverTmp = (try? FileManager.default.contentsOfDirectory(atPath: tempDirectory.path))?
            .filter { $0.hasSuffix(".tmp") } ?? []
        XCTAssertTrue(leftoverTmp.isEmpty, "Осиротевший .tmp не удалён: \(leftoverTmp)")

        assertLogged(containing: "заменить", since: logStart)
    }

    func test_init_corruptedFile_logsReadFailureReason() {
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let garbage = Data("not json".utf8)
        try? garbage.write(to: tempDirectory.appendingPathComponent("history.json"))

        let logStart = Date()
        _ = HistoryStore(directory: tempDirectory)

        assertLogged(containing: "JSON", since: logStart)
    }

    func test_init_versionMismatch_logsReason() {
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let json = Data(#"{"version": 99, "samples": []}"#.utf8)
        try? json.write(to: tempDirectory.appendingPathComponent("history.json"))

        let logStart = Date()
        let store = HistoryStore(directory: tempDirectory)

        XCTAssertTrue(store.samples(providerId: "claude", windowMins: 300, since: .distantPast).isEmpty)
        assertLogged(containing: "Версия", since: logStart)
    }
}
