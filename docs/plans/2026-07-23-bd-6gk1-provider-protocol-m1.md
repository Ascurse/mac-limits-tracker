# M1: протокол LimitsProvider + реестр + рефакторинг Claude/Codex

Бид: `mac-limits-tracker-6gk.1` (эпика `mac-limits-tracker-6gk`, GitHub #12, этап M1).
Статус: спека и план. Реализация — после подтверждения.

## 1. Цель

Убрать захардкоженную пару Claude/Codex из всего стека: провайдер описывает себя
один раз (дескриптор + загрузка снапшота), а попап, меню-бар, тултип, виджет и
все 4 темы строятся по списку зарегистрированных провайдеров. Поведение для
пользователя не меняется (кроме пяти микро-отклонений, перечисленных в §5 —
каждое требует подтверждения). Существующие тесты используются как
characterization: ожидаемые строки/тексты переносятся дословно на новый API.

## 2. Инвентаризация текущей связанности

Где сейчас код знает про конкретную пару провайдеров:

| Место | Что захардкожено |
|---|---|
| `Sources/MacLimitsTrackerCore/LimitsViewModel.swift:7-8, 41-53` | два поля `claude`/`codex`, два провайдера в `refresh()` |
| `LimitsViewModel.swift:72-94` | `statusTooltip`: окна только Claude, план Codex без окон |
| `Sources/MacLimitsTrackerCore/Models/PopupContent.swift:35-38, 69-120` | `PopupProvider` (enum из 2 кейсов), `claudeSection`/`codexSection` с разной логикой строк |
| `Sources/MacLimitsTrackerCore/Models/MenuBarDisplayMode.swift:23-49` | `menuBarText(claude:codex:)`, буквы `C`/`X`, поля обеих моделей напрямую |
| `Sources/MacLimitsTrackerCore/Formatting/LimitsFormatting.swift` | пары `claudeRemaining*`/`codexRemaining*` с одинаковой формулой |
| `Sources/MacLimitsTracker/App/MacLimitsTrackerApp.swift:47-61` | `statusIcon`/`statusTitle` смотрят на оба статуса напрямую |
| 4 темы (`SystemStatusView:13-15,50-51`, `TerminalStatusView:26-27`, `TUIStatusView:24-25`, `PhosphorStatusView:23-24`) | два явных вызова секций, цвет/имя/`showOpenClaude` по провайдеру |
| `Sources/MacLimitsTracker/UI/DesktopWidgetView.swift:8-22, 62-64, 76-93` | две секции, `.orange`/`.green`, разные пути к окнам |
| `Sources/VerifyCli/main.swift` | два блока печати по полям конкретных структур |
| `ClaudeStatus`/`CodexStatus` | разные по форме публичные модели (utilization vs usedPercent, разные наборы detail-полей) |

Темы уже почти «тупые»: внутри `section`/`rowView` provider-специфики нет —
только точка вызова и передаваемые accent/имя/кнопка. Это и переводим на данные.

## 3. Целевая архитектура (Core)

### 3.1 Дескриптор провайдера

```swift
/// Статичное самоописание провайдера: всё, что UI-слою нужно знать заранее.
public struct ProviderDescriptor: Equatable, Sendable {
    public let id: String              // "claude" / "codex" — ключ настроек (M2) и a11y
    public let displayName: String     // "Claude Code" — заголовок секции попапа
    public let shortName: String       // "Claude" — меню-бар, тултип, menuTitle
    public let menuBarSymbol: String   // "C" / "X" — компактные режимы меню-бара
    public let accentColorHex: UInt32  // 0xFF9E64 / 0x9ECE6A (из палитры Terminal-темы)
    public let loginHelp: LoginHelp?   // кнопка «открыть CLI» — сейчас только у Claude
}

public struct LoginHelp: Equatable, Sendable {
    public let helpText: String        // "Open Claude Code to refresh the claude.ai login"
    public let binaryPath: String      // что открывать в Terminal (defaultClaudeBinary())
}
```

### 3.2 Унифицированный снапшот

Форма повторяет то, что билдер уже умеет рендерить, — плоские optional-поля,
как в текущих статусах (минимальный риск при переносе characterization-тестов):

```swift
public struct LimitsSnapshot: Equatable, Sendable {
    public let loggedIn: Bool
    /// Сырой план (без capitalized); приоритет источников решает провайдер
    /// (Codex: live app-server > JWT-claim).
    public let plan: String?
    /// nil — usage ещё не загружен (строка «Loading usage…» / «Loading…»).
    public let windows: [SnapshotWindow]?
    public let creditsBalance: String?
    public let rateLimitReachedType: String?
    /// Упорядоченные detail-строки (Auth/Account/Org у Codex; у Claude пусто).
    public let details: [SnapshotDetail]
    public let daysUntilRenewal: Int?
    public let renewalDate: Date?
    public let usageError: String?
    public let providerError: String?
    public let fetchedAt: Date
}

public struct SnapshotWindow: Equatable, Sendable {
    public let windowDurationMins: Int?  // 300 / 10080 / прочее / nil (метки — RateLimitWindowLabel, как в w4a)
    /// nil — «слот заявлен, данных нет» → строка "«label» usage unavailable"
    /// (текущее поведение Claude-секции при отсутствии окна).
    public let usedPercent: Double?
    public let resetsAt: Date?
}

public struct SnapshotDetail: Equatable, Sendable {
    public let key: String
    public let value: String
}
```

Маппинг текущих моделей:

- **Claude**: `usage != nil` → `windows = [слот 300 (fiveHour), слот 10080 (sevenDay)]`,
  оба слота присутствуют всегда (с `usedPercent = nil`, если окна нет) — так
  сохраняются строки «5h/Weekly usage unavailable». `plan = subscriptionType`.
  `details = []`, renewal-поля nil.
- **Codex**: `windows` — только реально пришедшие окна (primary/secondary),
  `plan = usage?.snapshot?.planType ?? jwt.planType`, `details = [Auth, Account, Org]`,
  `daysUntilRenewal`/`renewalDate` из claims, `creditsBalance`/`rateLimitReachedType`
  из снапшота app-server.

`menuTitle` становится общим правилом в Core (расширение снапшота):
`providerError → "{shortName}: ?"`, `!loggedIn → "{shortName}: —"`,
`plan → "{shortName}: {plan.capitalized}"`, иначе `shortName`. Это дословно
текущая логика обоих `menuTitle` (у Codex приоритет live-плана уже уехал в `plan`).

### 3.3 Протокол и реестр

```swift
public protocol LimitsProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func fetch() async -> LimitsSnapshot
}

/// M1: фиксированный список. M2 добавит фильтр/порядок из UserDefaults.
public enum ProviderRegistry {
    public static func makeDefault() -> [any LimitsProvider] {
        [ClaudeLimitsProvider(), CodexLimitsProvider()]
    }
}
```

`ClaudeLimitsProvider`/`CodexLimitsProvider` остаются со своими DI-замыканиями и
пайплайнами (парсеры, Keychain, app-server RPC не трогаем). `ClaudeStatus`/
`CodexStatus` перестают быть публичным API: превращаются во внутренние DTO
шага fetch (или растворяются в мапперах — по вкусу на реализации). Замыкания
провайдеров помечаются `@Sendable` (они и сейчас пересекают границы Task).

### 3.4 ViewModel и билдер

```swift
public struct ProviderState: Identifiable {
    public let descriptor: ProviderDescriptor
    public let snapshot: LimitsSnapshot?   // nil — ещё грузится («Loading…»)
    public var id: String { descriptor.id }
}

@MainActor public final class LimitsViewModel: ObservableObject {
    @Published public private(set) var states: [ProviderState]
    public init(providers: [any LimitsProvider] = ProviderRegistry.makeDefault(), ...)
    // refresh(): параллельный fetch всех провайдеров (TaskGroup), результат — в порядке реестра
}
```

`PopupContentBuilder`:

- `section(_ state: ProviderState, now: Date) -> ProviderSectionContent` — одна
  функция вместо пары. Порядок строк (надмножество текущих секций; у Claude
  части просто пусты): `error(providerError)` | `Plan` → окна (сортировка из
  w4a: 300, 10080, прочие по возрастанию, nil в конце) → `Credits` →
  `error(rate limit reached)` → (`usageError` | «Loading usage…» при
  `windows == nil`) → details → «Renews in» → «Renews» (только будущая дата).
- `ProviderSectionContent` вместо `provider: PopupProvider` несёт
  `descriptor: ProviderDescriptor`; enum `PopupProvider` удаляется.
- `updatedText(states:)` — максимум `fetchedAt` по списку.

`MenuBarDisplayMode.menuBarText(states:)`:

- `.iconAndText`: `"{shortName}: {план}"` через `" · "` — «Claude: Max · Codex: Plus»;
- `.iconAnd5h`: `"{symbol} {остаток окна 300}"` через `" · "` — «C 72% · X 64%»;
- `.iconAnd5hWeekly`: `"{symbol} 5h {r300} / {r10080}"` через `" · "`.

`statusTooltip`/`statusTitle`/`statusIcon` — циклы по `states` (иконка ошибки —
если у любого провайдера `providerError != nil`).

`LimitsFormatting`: пары `claude*/codex*` схлопываются в
`remainingPercent(_ window: SnapshotWindow)` / `remainingText` (формула одна:
`max(0, 100 − used)`).

### 3.5 UI-слой (app target)

- Темы: `ForEach(viewModel.states)` → `section(builderResult)`; accent =
  `Color(hex: descriptor.accentColorHex)`; кнопка «открыть» — если
  `descriptor.loginHelp != nil`; `openClaudeCode()` → `openProviderCLI(_ help: LoginHelp)`
  (тот же Terminal-механизм). Phosphor остаётся монохромным (accent не берёт),
  имя секции — `descriptor.displayName` в стиле темы (upper/lower — как сейчас).
- `DesktopWidgetView`: цикл по `states`; окна — только слоты с
  `usedPercent != nil`; метки — `RateLimitWindowLabel.labels(...).short`.
- `MacLimitsTrackerApp`: label меню-бара и тултип через generic-аксессоры.
- `VerifyCli`: цикл по реестру, печать полей снапшота (id, loggedIn, plan,
  providerError, usageError, окна, credits, reached, menuTitle).

### 3.6 Альтернативы (правило трёх)

1. **Снапшот-enum состояний usage** (`loaded/unavailable/pending`) вместо плоских
   optional — чище, но дальше от текущих характеризационных ожиданий; отклонено
   для M1 (можно ужесточить в M2+).
2. **Провайдер сам строит `[PopupRow]`** — максимально гибко, но темы теряют
   гарантию единого порядка строк, а меню-бар/виджет всё равно требуют
   структурных данных; отклонено.
3. **Плоский снапшот + общий билдер** (выбрано) — данные структурные, порядок
   строк один на всех, тесты переносятся дословно.

## 4. Характеризация: как фиксируем «без изменения поведения»

Существующие тесты — источник истины. Перенос без изменения ожиданий:

- Каждый кейс `PopupContentBuilderClaudeTests`/`CodexTests` переезжает на
  `section(ProviderState)`: хелперы `makeStatus(...)` заменяются на построение
  снапшота **через новый маппер провайдера** (не вручную) — так тест проверяет
  и маппинг, и рендер разом; литералы ожидаемых строк не меняются.
- Тесты `MenuBarDisplayMode` — тем же способом (ожидаемые строки «C 72% · X 64%»
  и т.д. остаются literal).
- Тесты `fetch()` обоих провайдеров — ожидания переписываются с полей
  `ClaudeStatus`/`CodexStatus` на поля `LimitsSnapshot` (значения те же).
- Парсеры/JWT/бинарь-discovery — не трогаются, их тесты не меняются.

## 5. Осознанные микро-отклонения (нужно подтверждение)

Строгий «ноль отличий» возможен, но потребует костыльных флагов в дескрипторе.
Предлагаю принять пять отклонений — все в духе эпики:

| # | Что меняется | Было → станет |
|---|---|---|
| Д1 | Тултип меню-бара показывает окна и у Codex (сейчас — только у Claude) и метку `weekly` в нижнем регистре для всех | «…· Codex: Plus» → «…· Codex: Plus · 5h 64% · weekly 31%» |
| Д2 | `.iconAndText`: план Codex берётся live-first (как в `menuTitle`), а не из JWT | устаревший план после продления → актуальный |
| Д3 | System-тема и виджет: `.orange`/`.green` → фиксированные hex `0xFF9E64`/`0x9ECE6A` (единый акцент провайдера из дескриптора, совпадает с Terminal-темой) | едва заметный сдвиг оттенка |
| Д4 | Виджет: метка недельного окна Claude «week» → «wk» (единые метки `RateLimitWindowLabel`) | «week» → «wk» |
| Д5 | Вывод VerifyCli — единый формат по списку провайдеров | другой порядок/подписи строк диагностики |

## 6. План реализации (одна ветка = один PR; шаги = коммиты, каждый: build + test зелёные)

Worktree: `bd worktree create .worktrees/bd-mac-limits-tracker-6gk.1 --branch bd-mac-limits-tracker-6gk.1`.
TDD: на каждый шаг сначала красные тесты.

1. **Модель**: `ProviderDescriptor`, `LoginHelp`, `LimitsSnapshot`,
   `SnapshotWindow`, `SnapshotDetail`, generic `menuTitle`. Тесты: menuTitle
   (4 ветки), Equatable-семантика.
2. **Мапперы**: `ClaudeStatus → LimitsSnapshot`, `CodexStatus → LimitsSnapshot`
   (внутри провайдеров). Тесты: слоты-заглушки Claude, приоритет live-плана
   Codex, details/renewal, прокидка ошибок.
3. **Generic-билдер**: `PopupContentBuilder.section(state:now:)` + перенос всех
   кейсов `PopupContentBuilderTests` (литералы не меняются); удалить
   `claudeSection`/`codexSection`/`PopupProvider`; `updatedText(states:)`.
4. **Протокол + реестр**: `LimitsProvider`, конформанс обоих провайдеров
   (`fetch() -> LimitsSnapshot`), `ProviderRegistry`; тесты `fetch()`
   переписаны на снапшот; `ClaudeStatus`/`CodexStatus` уходят из публичного API;
   VerifyCli на цикл по реестру (проверка: `swift run -c release VerifyCli` —
   debug ловит ложный nano-malloc abort).
5. **ViewModel + меню-бар**: `states`/`ProviderState`, TaskGroup-refresh,
   generic `statusTooltip`/`statusTitle`/`statusIcon`;
   `MenuBarDisplayMode.menuBarText(states:)` + перенос его тестов;
   унификация `LimitsFormatting`.
6. **UI**: 4 темы, `DesktopWidgetView`, `MacLimitsTrackerApp` на
   `states`/дескрипторы; `openProviderCLI`; удаление остатков прямых обращений
   к `claude`/`codex` (grep-чистота: `viewModel.claude|viewModel.codex` = 0).
7. **Чистка и доки**: мёртвый код, обновление секции Architecture в
   `CLAUDE.md`/`AGENTS.md` проекта; `bd remember` про форму снапшота.
8. **Верификация**: `swift build`, `swift test` (все ~97+ зелёные),
   `swift run -c release VerifyCli`, `./make-app.sh`, ручная проверка: попап во
   всех 4 темах, все 4 режима меню-бара, виджет, кнопка «open» у Claude.
   Затем PR в `main` (ветка защищена — напрямую не пушим), `bd close` после мержа.

## 7. Критерии приёмки (из бида)

- Claude и Codex работают через `LimitsProvider`/реестр — ни одного прямого
  упоминания конкретного провайдера в `LimitsViewModel`, `PopupContentBuilder`,
  `MenuBarDisplayMode`, темах, виджете, VerifyCli (кроме `ProviderRegistry` и
  самих реализаций провайдеров).
- Поведение попапа/меню-бара/виджета/тем не изменилось (модуло Д1–Д5, если
  приняты).
- Characterization-тесты зелёные с неизменёнными литералами ожиданий.

## 8. Риски

- **Сорт окон с nil-`usedPercent`** (слоты-заглушки Claude) — покрыть тестом,
  чтобы заглушка 300 не уехала за 10080.
- **Sendable-конформанс** структур с замыканиями — возможно `@unchecked Sendable`
  с комментарием (текущий код уже пересекает границы Task).
- **Порядок строк Claude-секции**: в generic-порядке `usageError` идёт после
  окон, у Claude окон при этом нет (`windows == nil`) — позиция строки
  фактически совпадает; проверяется перенесёнными литералами.
- Двойная инициализация `LimitsViewModel` в `MacLimitsTrackerApp.init`
  (строки 7 и 13) — существующая странность, в M1 не трогаем (отдельный бид,
  если мешает).
