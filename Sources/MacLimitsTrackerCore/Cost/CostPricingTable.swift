import Foundation

/// Тариф модели в долларах за токен. `Decimal` — не `Double`, чтобы избежать
/// накопления ошибки округления двоичной плавающей точки на денежных суммах.
struct CostRate: Equatable {
    let inputPerToken: Decimal
    let outputPerToken: Decimal
    let cacheCreationPerToken: Decimal
    let cacheReadPerToken: Decimal
}

/// Статическая таблица тарифов моделей, зашитая в бинарь. НЕ live-запрос —
/// цены могут устареть, поэтому таблица версионирована (`version`) и попадает
/// в `CostEstimate.pricingTableVersion`, чтобы UI мог показать «оценка по
/// тарифам от …» вместо ложного ощущения точности.
///
/// Источники (по состоянию на версию ниже, могли измениться у поставщика —
/// таблица не проверяется автоматически, обновляется вручную):
/// - Claude: https://docs.claude.com/en/docs/about-claude/pricing (Sonnet 4.5, Opus 4.1)
/// - Codex/OpenAI: https://openai.com/api/pricing (gpt-5-codex)
enum CostPricingTable {
    /// Версия таблицы — меняется вручную при любой правке цен ниже.
    static let version = "2026-07-static-v1"

    /// Цена — `USD за миллион токенов` в источнике; здесь переведена в USD/токен.
    private static func perToken(_ perMillion: String) -> Decimal {
        Decimal(string: perMillion)! / 1_000_000
    }

    private static let rates: [String: CostRate] = [
        "claude-sonnet-4-5": CostRate(
            inputPerToken: perToken("3.00"),
            outputPerToken: perToken("15.00"),
            cacheCreationPerToken: perToken("3.75"),
            cacheReadPerToken: perToken("0.30")
        ),
        "claude-opus-4-1": CostRate(
            inputPerToken: perToken("15.00"),
            outputPerToken: perToken("75.00"),
            cacheCreationPerToken: perToken("18.75"),
            cacheReadPerToken: perToken("1.50")
        ),
        "gpt-5-codex": CostRate(
            inputPerToken: perToken("1.25"),
            outputPerToken: perToken("10.00"),
            cacheCreationPerToken: 0,
            cacheReadPerToken: perToken("0.125")
        )
    ]

    /// Алиасы — версионированные/датированные идентификаторы моделей из логов
    /// (`claude-sonnet-4-5-20260101`) сводятся к базовому тарифу по префиксу.
    private static let aliasPrefixes: [(prefix: String, tariffId: String)] = [
        ("claude-sonnet-4-5", "claude-sonnet-4-5"),
        ("claude-opus-4-1", "claude-opus-4-1"),
        ("gpt-5-codex", "gpt-5-codex")
    ]

    /// Возвращает тариф для модели из лога, либо `nil`, если модель неизвестна —
    /// НИКОГДА не подставляется приблизительный/чужой тариф вместо `nil`.
    static func rate(forModel model: String) -> (tariffId: String, rate: CostRate)? {
        if let exact = rates[model] {
            return (model, exact)
        }
        guard let match = aliasPrefixes.first(where: { model.hasPrefix($0.prefix) }),
              let rate = rates[match.tariffId] else {
            return nil
        }
        return (match.tariffId, rate)
    }
}
