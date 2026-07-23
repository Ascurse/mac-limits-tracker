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

## Общая память проекта

Конвенция журнала `docs/journal/` (decisions/gotchas/glossary) — чтение перед задачей, grep перед правкой файла, дозапись после находки — описана в [AGENTS.md](AGENTS.md), секция «Общая память проекта». Следуй ей; здесь не дублируется.
