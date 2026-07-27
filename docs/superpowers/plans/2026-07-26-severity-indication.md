# Severity-индикация в menu bar и desktop widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or execute the same task-by-task loop inline) and keep each task independently testable.

**Goal:** Протянуть настроенные `SeverityThresholds` из core в tint menu-bar label и цвета progress bars desktop widget.

**Architecture:** Добавить чистый helper `Severity.worst(in:thresholds:)` рядом с существующей классификацией severity; он смотрит на resolved snapshots всех провайдеров и игнорирует окна без `usedPercent`. App target использует результат для общего tint menu-bar `Image + Text`, а `DesktopWidgetView` вычисляет severity каждого окна и выбирает цвет бара, сохраняя accent провайдера для normal.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Package Manager, XCTest, macOS MenuBarExtra.

## Global Constraints

- Severity считается по остатку лимита: `remaining = max(0, 100 - usedPercent)`.
- Пороги всегда передаются из `LimitsViewModel.severityThresholds`; не подменять их `.standard` в UI.
- Окна идентифицируются данными окна и длительностью, не позицией массива.
- Stale/loading/error ветки и существующие menu-bar строки должны сохранить поведение.
- Не добавлять зависимости и не изменять пользовательские `.beads/interactions.jsonl` или `.codex/config.toml`.

---

### Task 1: Core worst-severity classifier

**Files:**
- Modify: `Sources/MacLimitsTrackerCore/Models/PopupContent.swift` рядом с `Severity.from`.
- Test: `Tests/MacLimitsTrackerTests/PopupContentBuilderTests.swift` в `SeverityThresholdsTests`/новом `SeverityWorstTests`.

**Interfaces:**
- Produces `Severity.worst(in states: [ProviderState], thresholds: SeverityThresholds = .standard) -> Severity`.
- Uses `SnapshotResolver.resolve(_:)`, so stale states classify their last-good visible snapshot.

- [ ] **Step 1: Write the failing tests**

  Add tests that construct Claude/Codex states with 70% remaining, 30% remaining, and 5% remaining windows and assert `.normal`, `.warning`, and `.critical` respectively; add a mixed-state assertion that the result is `.critical`, and an empty/no-usable-window assertion that the result is `.normal`. Use a non-standard `SeverityThresholds(warningRemaining: 60, criticalRemaining: 20)` in one assertion so the test proves configured thresholds are used.

- [ ] **Step 2: Run the focused tests to verify RED**

  Run `swift test --filter SeverityWorstTests`.

  Expected: compile/test failure because the new `Severity.worst(in:thresholds:)` API is absent; do not accept a syntax or fixture failure.

- [ ] **Step 3: Implement the smallest classifier**

  Add the helper next to `Severity.from`; iterate resolved snapshots and windows, skip `usedPercent == nil`, classify each remaining value with the passed thresholds, and retain the most severe of `.normal < .warning < .critical`. Return `.normal` when no usable window exists.

- [ ] **Step 4: Run focused and adjacent tests to verify GREEN**

  Run `swift test --filter SeverityWorstTests` and `swift test --filter MenuBarDisplayModeTests`.

  Expected: all new tests pass and all existing menu-bar text assertions remain unchanged.

### Task 2: Menu-bar severity tint

**Files:**
- Modify: `Sources/MacLimitsTracker/App/MacLimitsTrackerApp.swift` label group and `LimitsViewModel` extension.
- Test: `Tests/MacLimitsTrackerTests/PopupContentBuilderTests.swift` or `MacLimitsTrackerTests.swift` only if a pure helper assertion is needed; otherwise use the surface scenario below.

**Interfaces:**
- `LimitsViewModel.statusSeverity` derives from `Severity.worst(in: states, thresholds: severityThresholds)`.
- A local SwiftUI color mapping uses system tint for `.normal`, `.orange` for `.warning`, and `.red` for `.critical`.

- [ ] **Step 1: Capture the pre-change surface RED**

  Run `swift run -c release MacLimitsTracker` with fixture/stub state or the existing app test harness, then inspect the live menu-bar item in `iconAndText`, `iconOnly`, `iconAnd5h`, and `iconAnd5hWeekly` while a window is below the configured warning/critical threshold.

  PASS/FAIL observable: before the change, the label's `Image` and `Text` do not change tint with severity; capture an action log and screenshot in `.tmp/ulw-qa/menu-bar-red/`.

- [ ] **Step 2: Apply the shared tint**

  Wrap the existing menu-bar label contents in the mapped foreground style without changing the `MenuBarDisplayMode` text branches, `statusIcon`, refresh task, or tooltip.

- [ ] **Step 3: Run regression tests**

  Run `swift test --filter MenuBarDisplayModeTests` and `swift build`.

  Expected: unchanged text contracts and a successful app build.

### Task 3: Desktop widget severity bars

**Files:**
- Modify: `Sources/MacLimitsTracker/UI/DesktopWidgetView.swift` `LimitWindow`, `windows`, `providerSection`, and `windowRow`.
- Test: surface QA; retain existing core tests from Task 1 as the classifier contract.

**Interfaces:**
- `LimitWindow` carries `severity` in addition to label, remaining percent, and reset text.
- `windows(for:thresholds:)` receives the view model's configured thresholds.
- `barColor(_ severity:accent:)` returns provider accent for normal, orange for warning, red for critical.

- [ ] **Step 1: Capture the pre-change widget RED**

  With the release app running and desktop widget enabled, present normal, warning, and critical windows for at least one provider and capture the widget screenshot.

  PASS/FAIL observable: before the change, every progress bar uses the provider accent even when the corresponding remaining percentage is below warning/critical thresholds; save action log and screenshot in `.tmp/ulw-qa/widget-red/`.

- [ ] **Step 2: Thread thresholds and severity into each bar**

  Compute severity from each usable window using `viewModel.severityThresholds`, preserve resolved stale snapshot selection and existing unavailable/error branches, and apply `barColor` to the `ProgressView` tint.

- [ ] **Step 3: Run widget-adjacent verification**

  Run `swift test --filter SeverityWorstTests` and `swift build` after the edit; then repeat the widget surface scenario with a normal, warning, critical, stale, and no-data state.

  Expected: only bars change color; labels, remaining values, reset text, opacity, and error/loading messages remain unchanged.

### Task 4: Final verification and Beads handoff

**Files:**
- Verify: changed Swift files, design/plan docs, Beads state, and QA artifacts.

- [ ] **Step 1: Run the full Swift test suite**

  Run `swift test` and read the complete output; expected exit code 0 with no skipped or newly suppressed tests.

- [ ] **Step 2: Run release build and real-surface QA**

  Run `swift build -c release`, repeat the exact menu-bar and widget scenarios, and capture final screenshots/action logs. Tear down the app process and verify no QA-only process or temporary resource remains.

- [ ] **Step 3: Self-review the diff and diagnostics**

  Run `git diff --check`, LSP diagnostics for each changed Swift file, and inspect the diff for unrelated edits. Record the result in the ULW notepad.

- [ ] **Step 4: Update and close Beads**

  Close completed sub-tasks and `mac-limits-tracker-5wb` only after all criteria and cleanup receipts are recorded. Keep commits/pushes pending because the repository's conservative Beads profile requires explicit authorization for git integration.
