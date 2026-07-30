import Foundation

/// Разбор одной строки `~/.claude/projects/**/*.jsonl`. Поле `usage` каждой
/// ассистентской реплики содержит токены ИМЕННО ЭТОГО вызова модели — это
/// то, что нам нужно; кумулятивные суммы за сессию Claude в эти строки не
/// пишет, так что здесь нет риска случайно просуммировать «нарастающий итог»
/// (в отличие от Codex, где `total_token_usage` — ловушка, см. `CodexCostLogParser`).
///
/// Неизвестные поля игнорируются намеренно (tolerant parsing) — строгий
/// `Decodable` отбросил бы всю строку при любом дрейфе схемы, а нам нужно
/// уметь отличить «это не usage-строка» (`.ignored`) от «это usage-строка,
/// но она сломана» (`.malformed`).
enum ClaudeCostLogParser {
    static func parseLine(_ line: String) -> CostLineParseResult {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .malformed
        }
        guard json["type"] as? String == "assistant" else {
            return .ignored
        }
        guard let message = json["message"] as? [String: Any],
              let model = message["model"] as? String, !model.isEmpty,
              let usage = message["usage"] as? [String: Any],
              let timestampString = json["timestamp"] as? String,
              let timestamp = CostTimestampParsing.parse(timestampString),
              let inputTokens = costNonNegativeInt(usage["input_tokens"]),
              let outputTokens = costNonNegativeInt(usage["output_tokens"]) else {
            return .malformed
        }

        return .record(CostUsageRecord(
            source: .claude,
            timestamp: timestamp,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: costNonNegativeInt(usage["cache_creation_input_tokens"]) ?? 0,
            cacheReadTokens: costNonNegativeInt(usage["cache_read_input_tokens"]) ?? 0
        ))
    }
}
