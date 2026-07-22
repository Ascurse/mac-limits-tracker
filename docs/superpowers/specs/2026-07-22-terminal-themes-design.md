# Терминальные темы интерфейса (feature/restyling)

Эпик: `mac-limits-tracker-8zk`. Дата: 2026-07-22.

## Цель

Попап меню-бара получает четыре темы с переключателем в футере:
`System` (текущий вид, по умолчанию), `Phosphor`, `Terminal`, `TUI`.
Меню-бар (строка в статус-баре) не темизируется — его вид диктует система.

## Архитектура

### 1. Модель содержимого (Core, тестируется)

Новый файл `Sources/MacLimitsTrackerCore/Models/PopupContent.swift`.
Вся логика форматирования переезжает из `StatusBarView` в чистые типы:

```swift
/// Строка попапа: порядок строк задаёт билдер — единый для всех тем.
public enum PopupRow: Equatable {
    case detail(key: String, value: String)
    case window(WindowContent)
    case error(String)
    case note(String)   // "Loading…", "5h usage unavailable"…
}

public struct WindowContent: Equatable {
    public let shortLabel: String        // "5h" / "wk" — компактные темы
    public let longLabel: String         // "5h" / "Weekly" — системная тема
    public let remainingPercent: Double  // 0…100, ОСТАТОК
    public let remainingText: String     // "72%"
    public let resetText: String?        // "in 2 hours" / nil
    public let severity: Severity
}

public enum Severity: Equatable {
    case normal    // остаток > 40%
    case warning   // 15% < остаток ≤ 40%
    case critical  // остаток ≤ 15%
    static func from(remainingPercent: Double) -> Severity
}

public enum PopupProvider: Equatable { case claude, codex }

/// Секция попапа одного провайдера: упорядоченный список строк.
public struct ProviderSectionContent: Equatable {
    public let provider: PopupProvider
    public let title: String   // "Claude Code" / "Codex"
    public let rows: [PopupRow]
}

/// Сборка секций из статусов провайдеров (чистые функции, unit-тесты).
public enum PopupContentBuilder {
    public static func claudeSection(_ status: ClaudeStatus?, now: Date = Date()) -> ProviderSectionContent
    public static func codexSection(_ status: CodexStatus?, now: Date = Date()) -> ProviderSectionContent
    public static func updatedText(claude: ClaudeStatus?, codex: CodexStatus?) -> String
}
```

Правила (перенос текущего поведения, не менять):
- Остаток = `max(0, 100 − использовано)`; Claude: `utilizationPercent`, Codex: `usedPercent`.
- Сброс — `RelativeDateTimeFormatter` (`.full`), как сейчас.
- Отсутствующее окно → `.note("5h/Weekly usage unavailable")` на его месте.
- `providerError` → секция из одной `.error`. `usageError` без usage → `.error` после Plan.
- `status == nil` → секция из одной `.note("Loading…")`.
- Codex-строки в текущем порядке: Plan, 5h, Weekly, Credits, rate-limit error, Auth, Account, Org, Renews in, Renews.
- `rateLimitReachedType` → `.error("rate limit reached: …")`.
- Первая строка секции — всегда Plan (`.detail(key: "Plan", …)`), кроме ошибки/загрузки; темы Terminal/Phosphor/TUI показывают её в заголовке секции и пропускают в списке.

### 2. Тема (App)

`Sources/MacLimitsTrackerCore/Models/AppTheme.swift` — по образцу `MenuBarDisplayMode`:

```swift
public enum AppTheme: String, CaseIterable, Identifiable {
    case system, terminal, phosphor, tui
    public var id: String { rawValue }
    public var title: String { "System" / "Terminal" / "Phosphor" / "TUI" }
}
```

Хранение: `@AppStorage("appTheme")`, по умолчанию `.system`.

### 3. Виды (App/UI)

- `StatusBarView` становится корневым переключателем: строит `ProviderSectionContent`
  через `PopupContentBuilder` и передаёт в конкретный вид темы.
- `SystemStatusView.swift` — текущая разметка (переезжает как есть).
- `TerminalStatusView.swift`, `PhosphorStatusView.swift`, `TUIStatusView.swift` — новые.
- Общий футер (Picker темы + Picker меню-бара + Auto-refresh + Quit) — единый
  компонент `PopupFooter`, каждая тема оборачивает его своими цветами через `.tint`/фон.
- Ширина попапа: как сейчас `minWidth 320, ideal 340`.

### 4. Палитры и оформление тем

Шрифт во всех терминальных темах — `.system(.caption, design: .monospaced)`
(значения — `.monospacedDigit()` поверх). Без внешних шрифтов.

**Terminal (Tokyo Night)** — основная:
- фон `#1A1B26`, текст `#C0CAF5`, вторичный `#565F89`, рамки/трек `#2F334D`
- заголовок `#7DCFFF` (циан), Claude-акцент `#FF9E64`, Codex-акцент `#9ECE6A`
- прогресс: `Capsule` высотой 4, цвет по severity: normal → акцент провайдера,
  warning → `#E0AF68`, critical → `#F7768E`; анимация `.easeOut` при изменении
- секция: `● claude  max` (точка цветом провайдера)

**Phosphor (ретро-CRT)** — монохром:
- фон `#050805`, яркий `#35E06A`, обычный `#1E9C48`, приглушённый `#164A26`
- заголовки секций `#8DFFB0`; critical — инверсия (текст фоном на ярко-зелёной плашке)
- прогресс: строка из 14 символов `█` (заполнено) / `░` (пусто), текстом
- футер: `[r]efresh · [q]uit ▮`, курсор `▮` мигает (opacity-анимация 1s repeat)
- ошибки: `!` префикс, тем же зелёным ярким (монохром не ломаем)

**TUI (htop)**:
- фон `#101216`, текст `#D0D5DD`, рамки `#3A4150`, подписи `#5A6374`
- секция — прямоугольник с обводкой 1pt и заголовком, врезанным в верхнюю
  кромку (`CLAUDE ─ max`); рамки рисуем SwiftUI-обводкой, НЕ символами
- датчик: `[||||||||······] 72%` — `|` цветом severity (normal `#9ECE6A`,
  warning `#E0AF68`, critical `#F7768E`), `·` цветом `#3A4150`, 14 делений
- футер: плашки-клавиши `F5 refresh`, `F10 quit` (реально кнопки)

### 5. Тесты (TDD)

- `PopupContentBuilderTests`: остатки/severity (границы 15/40), сбросы, ошибки,
  загрузка, отсутствие окон, порядок деталей Codex, `updatedText`.
- `AppThemeTests`: rawValue-стабильность (персистентность), titles, allCases.
- Символьные рендеры (бар Phosphor `█░`, датчик TUI `[||·]`) — чистые функции
  `String`-рендеринга в Core, тестируются на границах 0/50/100%.
- Раскладка видов — только глазами через `make-app.sh`.

## Порядок работ (беды)

1. `…-8zk.1` модель содержимого + рефакторинг StatusBarView (вид не меняется)
2. `…-8zk.2` AppTheme + переключатель + каркас (SystemStatusView)
3. `…-8zk.3` Terminal  4. `…-8zk.4` Phosphor  5. `…-8zk.5` TUI
6. `…-8zk.6` проверка глазами + README

Проверка каждой задачи: `swift build && swift test`.
