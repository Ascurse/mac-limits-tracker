import Foundation

/// Один обнаруженный лог-файл — источник и путь к нему держатся только
/// внутри этого модуля, наружу (диагностика) путь не просачивается.
struct CostLogFile {
    let source: CostSource
    let url: URL
}

/// Находит лог-файлы Claude/Codex на диске и построчно их читает.
/// Единственное место, где Cost-домен трогает файловую систему — парсеры
/// (`ClaudeCostLogParser`/`CodexCostLogParser`) файлов не открывают сами.
enum LocalCostLogSource {
    /// Защита от аномально большого файла (повреждён/не тот файл) —
    /// такие файлы не читаем целиком в память, считаем недоступными.
    private static let maxFileSizeBytes = 200 * 1024 * 1024

    /// Рекурсивно находит все `*.jsonl` под корнем. Отсутствующий корень —
    /// это «логов нет», а не ошибка (CLI мог не устанавливаться вовсе).
    /// Порядок результата детерминирован (сортировка по пути) — важно для
    /// стабильности diagnostics/тестов между запусками.
    static func discoverFiles(source: CostSource, root: URL, fileManager: FileManager) -> [CostLogFile] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        var urls: [URL] = []
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        )
        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension == "jsonl" else { continue }
            urls.append(item)
        }

        return urls
            .sorted { $0.path < $1.path }
            .map { CostLogFile(source: source, url: $0) }
    }

    /// Построчно читает файл. `nil` — файл нечитаем (права/удалён между discovery
    /// и чтением/слишком большой) — вызывающий код учитывает это в diagnostics
    /// как `unreadableFiles`, а не падает.
    static func readLines(of file: CostLogFile, fileManager: FileManager) -> [String]? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: file.url.path),
              let size = attrs[.size] as? Int,
              size <= maxFileSizeBytes,
              let data = fileManager.contents(atPath: file.url.path),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
