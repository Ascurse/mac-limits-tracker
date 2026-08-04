# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->


## Build & Test

```bash
swift build              # собрать всё (MacLimitsTracker app + Core + VerifyCli)
swift test                # прогнать тесты (Tests/MacLimitsTrackerTests)
swift run -c release VerifyCli  # диагностика реальных лимитов; ТОЛЬКО release —
                                 # debug ловит ложный nano-malloc abort при выходе
./make-app.sh              # собрать .app-бандл
```

## Architecture Overview

Swift Package с тремя таргетами:

- **MacLimitsTrackerCore** — бизнес-логика без SwiftUI. Провайдер лимитов
  реализует протокол `LimitsProvider` (`descriptor: ProviderDescriptor` +
  `fetch() async -> LimitsSnapshot`); список зарегистрированных провайдеров —
  `ProviderRegistry.makeDefault()`. Claude, Codex и Kimi — `ClaudeLimitsProvider`/
  `CodexLimitsProvider`/`KimiLimitsProvider` в `Providers/LimitsProviders.swift`;
  каждый строит внутренний DTO (`ClaudeStatus`/`CodexStatus`/`KimiStatus`,
  `internal`) и мапит его в публичный `LimitsSnapshot` через `toSnapshot()`
  (`Providers/SnapshotMapping.swift`). Kimi: логин-детект по
  `~/.kimi-code/credentials/kimi-code.json` (логин = непустой `refresh_token`,
  не `expires_at` — access_token живёт ~900с), usage — live-запрос
  `GET https://api.kimi.com/coding/v1/usages` (`KimiUsagesParser`,
  `KimiModels.swift`); `limits[]` → окна (`windowDurationMins` из
  `window.duration`×multiplier по `timeUnit`), верхнеуровневый `usage` (покупной
  пул без периода, `subType: TYPE_PURCHASE`) → деталь `"Quota"`, не окно с
  придуманной длительностью. План = `membership.level` (Title Case через
  `KimiMembershipLevelFormatter`), fallback — старый JWT plan-claim. 401/протухший
  `expiresAt` → `usageError` "Kimi login expired…", `loggedIn` остаётся `true`
  (см. bd mac-limits-tracker-6gk.8, docs/journal/decisions.md).
  Без рабочих credentials Kimi не регистрируется в `ProviderRegistry` вовсе
  (`KimiLimitsProvider.hasUsableCredentials`) — скрыт из попапа/меню-бара/виджета
  без единой правки в UI-слое. `LimitsViewModel` держит `states: [ProviderState]`
  (дескриптор + последний снапшот), обновляет их параллельно через `TaskGroup`.
  Включённость и порядок провайдеров хранит `ProviderSettingsStore`
  (`Providers/ProviderSettingsStore.swift`) в `UserDefaults` —
  `LimitsViewModel.providerSettings`/`setProviderEnabled`/
  `moveProviderUp`/`moveProviderDown`; выключенный провайдер не опрашивается и
  не попадает в `states`, порядок секций попапа/виджета/меню-бара следует
  сохранённому (bd mac-limits-tracker-6gk.2).
- **MacLimitsTracker** — SwiftUI app (menu-bar + попап в 4 темах + десктоп-виджет).
  Темы (`UI/*StatusView.swift`) рендерят `PopupContentBuilder.section(state:)` —
  ни одна тема не знает о конкретном провайдере, только `ProviderDescriptor`
  (акцентный цвет, имя, кнопка «открыть CLI») и `PopupRow`.
- **VerifyCli** — диагностический CLI, крутится по `ProviderRegistry` и печатает
  снапшоты; запускать только в release (см. Build & Test).

Добавление нового провайдера: новый тип, конформящий `LimitsProvider`, плюс
запись в `ProviderRegistry` — без правок в `LimitsViewModel`,
`PopupContentBuilder`, темах или виджете. Пошаговый гайд —
[docs/adding-a-provider.md](docs/adding-a-provider.md).

## Conventions & Patterns

- Окна лимитов различаются по `windowDurationMins` (300 = 5h, 10080 = weekly),
  не по позиции в ответе API — см. `RateLimitWindowLabel` и bd mac-limits-tracker-w4a.
- `SnapshotWindow.usedPercent == nil` — слот заявлен, данных нет («… usage
  unavailable»); билдер и виджет различают «слота нет» и «слот пуст».
- Темы (`UI/*StatusView.swift`) — тупые рендеры `PopupRow`; provider-специфичная
  логика запрещена в UI-слое, только в `Core/Providers` и мапперах.
- Строки «ключ — значение» в Terminal/TUI идут через `CompactKeyValueRow`
  (`UI/ProviderOverview.swift`): `ViewThatFits` роняет значение на свою строку
  вместо сжатия в многоточие. Числовые значения окон помечены `.fixedSize()` —
  сжимается полоса, не процент.
- Кнопка открытия CLI — общий `ProviderOpenButton` (`UI/ProviderOverview.swift`):
  подпись `LoginHelp.actionTitle` показывается, пока помещается, иначе остаётся
  иконка. Метку VoiceOver для всех тем даёт
  `LoginHelp.accessibilityLabel(providerTitle:)` — не писать её литералом в теме.
- Цвета тем — hex-константы в `Core/Models/ThemePalette.swift`; `TerminalPalette`/
  `PhosphorPalette`/`TuiPalette` в `UI/ProviderOverview.swift` только оборачивают
  их в `Color`. Новый цвет заводится в Core, иначе его не увидит гейт контраста
  `ThemePaletteContrastTests` (WCAG AA: 4.5:1 для текста, 3:1 для полос, рамок и
  stale-состояния при `StaleAppearance.opacity`).

## Headless UI-тесты (без запуска приложения)

Темы попапа и десктоп-виджет рендерят одно и то же состояние, но код view лежит в
executable target `MacLimitsTracker`, который test target `MacLimitsTrackerTests`
импортировать не может. Поэтому headless-тесты идут через чистую модель контента
`ProviderSectionContent` из `PopupContentBuilder.section(state:now:history:thresholds:)`
(`Sources/MacLimitsTrackerCore/Models/PopupContent.swift`). Все темы получают эту
модель через `ProviderOverview` и отличаются только визуальной подачей, поэтому
один набор тестов на контент покрывает Terminal / Phosphor / TUI / System.

### Что покрывается этим стеком

- Структура и текст секции провайдера: окна, спарклайны, детали, ошибки,
  заглушки (`"… usage unavailable"`, `"Loading…"`).
- Поведенческие различия: пустой слот vs отсутствующий слот, stale-состояние,
  сортировка строк.
- Правила `PopupContentBuilder` — единый источник истины для всех тем.

### Что НЕ покрывается

- Сами view в `Sources/MacLimitsTracker/UI/*StatusView.swift` — они в
  executable target и недоступны тестам.
- `DesktopWidgetView` — тоже в executable target; виджет рисует собственный
  layout напрямую из `viewModel.states`, не через `ProviderOverview`.
- `AppDelegate` и `DesktopWidgetController` — работают с `NSStatusItem`,
  `NSPopover`, `NSPanel` и реальными window-сессиями; это уровень UI-тестов,
  запускающих приложение, а не `swift test`.
- Визуальные детали тем (цвета, шрифты, отступы, анимации, ASCII-бары) —
  они не попадают в `ProviderSectionContent`.

### Минимальный шаблон теста поведения (ViewInspector)

```swift
import SwiftUI
import ViewInspector
import XCTest
@testable import MacLimitsTrackerCore

final class PhosphorStatusViewBehaviorTests: XCTestCase {
    private let descriptor = ProviderDescriptor(
        id: "claude", displayName: "Claude Code", shortName: "Claude",
        menuBarSymbol: "C", accentColorHex: 0xFF9E64, loginHelp: nil
    )
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func state(usedPercent: Double?) -> ProviderState {
        let snapshot = LimitsSnapshot(
            loggedIn: true, plan: "max",
            windows: [SnapshotWindow(windowDurationMins: 300, usedPercent: usedPercent, resetsAt: nil)],
            creditsBalance: nil, rateLimitReachedType: nil, details: [],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: nil, fetchedAt: now
        )
        return ProviderState(descriptor: descriptor, snapshot: snapshot)
    }

    func test_nilUsedPercent_rendersUsageUnavailable() throws {
        let section = PopupContentBuilder.section(state(usedPercent: nil), now: now)

        // Проверяем модель контента: пустой слот не рендерит window-строку.
        XCTAssertFalse(section.rows.contains { if case .window = $0 { return true }; return false })
        XCTAssertTrue(section.rows.contains { if case .note(let t) = $0 { return t.contains("usage unavailable") }; return false })

        // Минимальный рендер: в Terminal/Phosphor/TUI note-строка — Text(text).
        let sut = NoteRow(text: "5h usage unavailable")
        let inspected = try sut.inspect().find(text: "5h usage unavailable")
        XCTAssertFalse(try inspected.string().isEmpty)
    }
}

private struct NoteRow: View {
    let text: String
    var body: some View { Text(text) }
}

extension NoteRow: Inspectable {}
```

Аналогичный тест для Terminal см. в
`Tests/MacLimitsTrackerTests/TerminalStatusViewBehaviorTests.swift` (bd-t9e.2).

### Минимальный шаблон snapshot-теста (.dump)

```swift
import SnapshotTesting
import XCTest
@testable import MacLimitsTrackerCore

final class TUIStatusViewSnapshotTests: XCTestCase {
    private let descriptor = ProviderDescriptor(
        id: "claude", displayName: "Claude Code", shortName: "Claude",
        menuBarSymbol: "C", accentColorHex: 0xFF9E64, loginHelp: nil
    )
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func state(windows: [SnapshotWindow]) -> ProviderState {
        let snapshot = LimitsSnapshot(
            loggedIn: true, plan: "max", windows: windows,
            creditsBalance: nil, rateLimitReachedType: nil,
            details: [SnapshotDetail(key: "Email", value: "a@b.co")],
            daysUntilRenewal: nil, renewalDate: nil, usageError: nil,
            providerError: nil, fetchedAt: now
        )
        return ProviderState(descriptor: descriptor, snapshot: snapshot)
    }

    private func sample(windowMins: Int, hoursAgo: Double, used: Double) -> UsageSample {
        UsageSample(providerId: "claude", windowMins: windowMins,
                    fetchedAt: now.addingTimeInterval(-hoursAgo * 3600),
                    usedPercent: used, resetsAt: nil)
    }

    func test_dump_populatedState() {
        let section = PopupContentBuilder.section(
            state(windows: [
                SnapshotWindow(windowDurationMins: 300, usedPercent: 42, resetsAt: nil),
                SnapshotWindow(windowDurationMins: 10080, usedPercent: 69, resetsAt: nil)
            ]),
            now: now,
            history: [
                sample(windowMins: 300, hoursAgo: 10, used: 20),
                sample(windowMins: 300, hoursAgo: 5, used: 30),
                sample(windowMins: 300, hoursAgo: 2, used: 40)
            ]
        )
        assertSnapshot(of: section, as: .dump)
    }
}
```

`.dump` записывает дерево `ProviderSectionContent` в
`Tests/MacLimitsTrackerTests/__Snapshots__/{TestClass}/{testName}.1.txt`.
Снапшот детерминирован, если:

- `now` зафиксирован (`Date(timeIntervalSince1970:)`),
- `resetsAt` везде `nil` (иначе `RelativeDateTimeFormatter` зависит от локали
  раннера),
- история спарклайна задана явно и лежит внутри 7-дневного окна от `now`.

### Переиспользование между темами

Все четыре темы (`SystemStatusView`, `TerminalStatusView`, `PhosphorStatusView`,
`TUIStatusView`) вызывают `ProviderOverview` с одним и тем же
`PopupContentBuilder.sections(...)`. Поэтому для новой темы не нужен отдельный
snapshot: достаточно проверить, что она использует тот же билдер и тот же
`ProviderSectionContent`. Практический приём: один общий класс
`StatusViewSnapshotTests`, параметризованный дескриптором/состоянием, плюс
минимальный ViewInspector-тест на рендер `.note`/`Text`, если тема имеет
особое оформление строк.

### DesktopWidgetView

Виджет не использует `ProviderOverview` и строит собственный `[LimitWindow]`
прямо в view. Этот код пока в executable target, поэтому headless snapshot
стека (Core + `swift test`) его не покрывает. Можно тестировать входные данные:
`LimitsSnapshot`, `SnapshotResolver.resolve`, `Severity.from` и
`LimitsFormatting` — они в Core. Чтобы покрыть layout виджета, нужно либо
вынести сборку `LimitWindow` в Core, либо поднимать UI-тест с запущенным app.

### Проверка перед коммитом

```bash
swift test
```

Тесты должны проходить без запуска приложения и без `XCTest` в `MacLimitsTracker`
executable target.

## Общая память проекта

Конвенция журнала `docs/journal/` (decisions/gotchas/glossary) — чтение перед задачей, grep перед правкой файла, дозапись после находки — описана в [AGENTS.md](AGENTS.md), секция «Общая память проекта». Следуй ей; здесь не дублируется.
