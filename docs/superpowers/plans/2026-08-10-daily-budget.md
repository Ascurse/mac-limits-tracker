# Дневной ориентир недельного лимита Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить в menu-bar popup управляемый настройкой ориентир дневного расхода для weekly-лимита.

**Architecture:** Чистый `DailyBudgetCalculator` в Core считает долю остатка до конца локального дня и не знает о UI. `PopupContentBuilder` добавляет готовый `DailyBudgetContent` только для свежего weekly-снапшота; `AppSettingsStore` и `LimitsViewModel` управляют глобальным persisted toggle по существующему паттерну `showUsageTrends`.

**Tech Stack:** Swift 6.1, SwiftUI, Foundation `Calendar`/`UserDefaults`, XCTest, существующий `PopupContentBuilder`.

## Global Constraints

- Не менять провайдерские API и маппинг `LimitsSnapshot`.
- Не переиспользовать `BurnRateCalculator`: burn rate и daily budget — разные метрики.
- Первый scope ограничен weekly-окном, четырьмя menu-bar темами и обычным desktop-окном; desktop widget и 5h budget не добавлять.
- Все derived values вычислять в Core и покрывать pure/unit tests.
- Пустые, stale и невалидные входы молча скрывают derived row; не показывать ложный «гарантированный» лимит.
- TDD: каждый production change начинать с одного failing test и проверять RED/GREEN.

---

### Task 1: DailyBudgetCalculator

**Files:**
- Create: `Sources/MacLimitsTrackerCore/Models/DailyBudgetCalculator.swift`
- Create: `Tests/MacLimitsTrackerTests/DailyBudgetCalculatorTests.swift`

**Interfaces:**
- Produces `DailyBudget` with `budgetPercent` and `resetAt`.
- Produces `DailyBudgetCalculator.calculate(remainingPercent:resetAt:now:calendar:) -> DailyBudget?`.

- [ ] **Step 1: Write the failing tests**

  Add tests for a weekly reset after the end of the local day, reset before the end of the local day, missing/past reset, zero/clamped remaining, 5h independence, and a calendar boundary using an injected timezone.

- [ ] **Step 2: Run the focused test and verify RED**

  Run: `swift test --filter DailyBudgetCalculatorTests`

  Expected: compilation/test failure because `DailyBudgetCalculator` does not exist.

- [ ] **Step 3: Implement the minimal pure calculator**

  Use `calendar.startOfDay(for:)`, add one calendar day for `endOfLocalDay`, clamp `remainingPercent` to `0...100`, cap the usable interval at `resetAt`, and return `nil` for missing or non-future reset data.

- [ ] **Step 4: Run the focused test and verify GREEN**

  Run: `swift test --filter DailyBudgetCalculatorTests`

  Expected: all calculator tests pass.

---

### Task 2: Popup presentation contract

**Files:**
- Modify: `Sources/MacLimitsTrackerCore/Models/PopupContent.swift`
- Modify: `Tests/MacLimitsTrackerTests/PopupContentBuilderTests.swift`
- Modify: `Sources/MacLimitsTracker/UI/SystemStatusView.swift`
- Modify: `Sources/MacLimitsTracker/UI/TerminalStatusView.swift`
- Modify: `Sources/MacLimitsTracker/UI/PhosphorStatusView.swift`
- Modify: `Sources/MacLimitsTracker/UI/TUIStatusView.swift`
- Modify: `Sources/MacLimitsTracker/UI/DesktopWindowView.swift`
- Modify: `Sources/MacLimitsTracker/UI/ProviderOverview.swift`

**Interfaces:**
- Adds `DailyBudgetContent` and `PopupRow.dailyBudget`.
- Extends `PopupContentBuilder.section/sections` with `showDailyBudget: Bool = true` and `calendar: Calendar = .current`.
- The four themed status views and `DesktopWindowView` pass `viewModel.showDailyBudget` into the shared popup-content path. `DesktopWidgetView` remains unchanged.

- [ ] **Step 1: Write failing builder tests**

  Add tests proving a fresh weekly window creates one daily-budget row after the weekly window, `showDailyBudget == false` omits it, 5h windows do not create it, stale states omit it, and missing/past reset omits it.

- [ ] **Step 2: Run the focused test and verify RED**

  Run: `swift test --filter PopupContentBuilderTests`

  Expected: compilation failure for the missing row/content and new builder arguments.

- [ ] **Step 3: Add the Core presentation contract and builder wiring**

  Add neutral copy (`Today pace: ~N% of weekly limit`), call the calculator only for `windowDurationMins == 10080`, pass `calendar` through the builder, and gate derived output on `!resolved.isStale` and `showDailyBudget`.

- [ ] **Step 4: Render the new row in all four popup themes**

  Add a compact `dailyBudget` branch next to the existing `burnRate` branch in `ProviderOverview.rowView`, preserving the existing theme tokens and accessibility value. Pass the setting from each shared status view and `DesktopWindowView`; do not add provider-specific UI branches.

- [ ] **Step 5: Run focused tests and verify GREEN**

  Run: `swift test --filter PopupContentBuilderTests`

  Expected: all existing and new builder tests pass.

---

### Task 3: Persisted setting and Settings toggle

**Files:**
- Modify: `Sources/MacLimitsTrackerCore/Providers/AppSettingsStore.swift`
- Modify: `Sources/MacLimitsTrackerCore/LimitsViewModel.swift`
- Modify: `Sources/MacLimitsTracker/UI/Settings/DisplaySettingsSection.swift`
- Modify: `Tests/MacLimitsTrackerTests/AppSettingsStoreTests.swift`

**Interfaces:**
- Adds `AppSettingsStore.showDailyBudget: Bool`, default `true`, key `showDailyBudget`.
- Adds `LimitsViewModel.showDailyBudget` and `setShowDailyBudget(_:)`.

- [ ] **Step 1: Write failing persistence and ViewModel tests**

  Add tests for default true, false round-trip, ViewModel load/set/persist, and unchanged fetch counter after toggling.

- [ ] **Step 2: Run focused tests and verify RED**

  Run: `swift test --filter 'AppSettingsStoreTests|LimitsViewModelDisplaySettingsTests'`

  Expected: compilation failure for the missing property and setter.

- [ ] **Step 3: Implement the setting using the `showUsageTrends` pattern**

  Read with `object(forKey:) as? Bool ?? true`, persist through `AppSettingsStore`, initialize the published ViewModel property, and expose `setShowDailyBudget(_:)` without calling `refresh()`.

- [ ] **Step 4: Add the Settings control**

  Add `Toggle("Show daily budget", ...)` to `DisplaySettingsSection` with the same control size, binding style, and accessibility label as the trends toggle.

- [ ] **Step 5: Run focused tests and verify GREEN**

  Run: `swift test --filter 'AppSettingsStoreTests|LimitsViewModelDisplaySettingsTests'`

  Expected: all focused tests pass.

---

### Task 4: Full verification and manual QA

**Files:**
- Modify: `scripts/qa/scenarios/04-settings-first.sh` only if an existing stable selector needs to be extended.

- [ ] **Step 1: Run the complete Swift suite**

  Run: `swift test --disable-sandbox`

  Expected: zero test failures.

- [ ] **Step 2: Run static/build gates**

  Run: `swift build`, `git diff --check`

  Expected: both exit 0.

- [ ] **Step 3: Run manual/AX acceptance**

  Build and launch the app through the designated QA flow. In Settings, verify the toggle is present, defaults on, hides/shows the weekly daily-budget row without a refresh, and survives relaunch. Check System, Terminal, Phosphor, and TUI popup themes plus the regular desktop window; verify accessibility exposes the row as an approximate daily pace and that no row appears for 5h/no-reset/stale states.
