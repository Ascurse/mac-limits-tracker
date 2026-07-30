import Foundation

/// Разбор одного файла `~/.codex/sessions/**/*.jsonl`. В отличие от Claude,
/// модель здесь не лежит в той же строке, что usage: `turn_context` несёт
/// `payload.model` для текущего хода, а токены приходят позже отдельными
/// `event_msg`/`token_count`-строками — поэтому разбор стейтфул на уровне
/// файла (`currentModel` переносится между строками одного файла, но не
/// между файлами — каждый вызов `parseFile` независим).
///
/// КРИТИЧНО: `payload.info.total_token_usage` — это нарастающий итог за всю
/// сессию, а не токены одного вызова. Если просуммировать его по всем строкам
/// файла, стоимость окажется задвоена в разы. Здесь читается ТОЛЬКО
/// `payload.info.last_token_usage` — токены именно этого хода.
enum CodexCostLogParser {
    static func parseFile(lines: [String]) -> [CostLineParseResult] {
        var currentModel: String?
        return lines.map { parseLine($0, currentModel: &currentModel) }
    }

    private static func parseLine(_ line: String, currentModel: inout String?) -> CostLineParseResult {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = json["payload"] as? [String: Any] else {
            return .malformed
        }

        switch json["type"] as? String {
        case "turn_context":
            guard let model = payload["model"] as? String, !model.isEmpty else {
                return .malformed
            }
            currentModel = model
            return .ignored

        case "event_msg":
            guard payload["type"] as? String == "token_count" else { return .ignored }
            // `info: null` — событие без данных использования (частый пограничный
            // случай в реальных rollout-логах), не ошибка формата.
            guard let info = payload["info"] as? [String: Any] else { return .ignored }
            guard let model = currentModel else { return .malformed }
            guard let usage = info["last_token_usage"] as? [String: Any],
                  let timestampString = json["timestamp"] as? String,
                  let timestamp = CostTimestampParsing.parse(timestampString),
                  let rawInputTokens = costNonNegativeInt(usage["input_tokens"]),
                  let outputTokens = costNonNegativeInt(usage["output_tokens"]) else {
                return .malformed
            }
            let cachedTokens = costNonNegativeInt(usage["cached_input_tokens"]) ?? 0
            // input_tokens у OpenAI включает cached — вычитаем, чтобы каждый токен
            // ценился ровно по одному тарифу (полному или cache-read), без задвоения.
            let inputTokens = max(0, rawInputTokens - cachedTokens)

            return .record(CostUsageRecord(
                source: .codex,
                timestamp: timestamp,
                model: model,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: 0,
                cacheReadTokens: cachedTokens
            ))

        default:
            return .ignored
        }
    }
}
