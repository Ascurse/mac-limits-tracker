# Терминальные темы попапа — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Четыре темы попапа меню-бара (System / Terminal / Phosphor / TUI) с переключателем в футере; вся логика форматирования — в тестируемой модели содержимого.

**Architecture:** Ядро (`MacLimitsTrackerCore`) получает `PopupContentBuilder` — чистые функции, собирающие упорядоченный список строк (`PopupRow`) из статусов провайдеров. Каждая тема — отдельный SwiftUI-вид в App-таргете, рендерящий одни и те же строки по-своему. Корневой `StatusBarView` переключает вид по `@AppStorage("appTheme")`.

**Tech Stack:** Swift 5.9+, SwiftUI (macOS, MenuBarExtra), XCTest, SwiftPM. Без внешних зависимостей.

**Спека:** `docs/superpowers/specs/2026-07-22-terminal-themes-design.md`
**Ветка:** `feature/restyling` (уже создана, работать в ней).
**Беды:** эпик `mac-limits-tracker-8zk`; соответствие задач плана бидам — в конце документа.

## Global Constraints

- Без внешних зависимостей и внешних шрифтов; моноширинный — только `.system(size:…, design: .monospaced)` / `.monospacedDigit()`.
- Комментарии в коде — по-русски, кратко, только для неочевидного (стиль проекта).
- Попап: `padding(16)`, `frame(minWidth: 320, idealWidth: 340)` — во всех темах.
- Меню-бар (label `MenuBarExtra`) не темизируется — `MacLimitsTrackerApp.swift` не трогать.
- Не менять: `Providers/`, `LimitsViewModel` (логику), `MenuBarDisplayMode`, `VerifyCli`.
- Ключи `@AppStorage`: тема — `"appTheme"` (default `.system`), режим меню-бара — существующий `"menuBarDisplayMode"`.
- Проверка каждой задачи: `swift build 2>&1 | tail -3` и `swift test 2>&1 | tail -5` — зелёные.
- Коммит после каждой задачи, трейлер: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Никакой обратной совместимости и «на вырост»-абстракций.

## Структура файлов

| Файл | Ответственность |
|---|---|
| `Sources/MacLimitsTrackerCore/Models/PopupContent.swift` | создать — типы строк попапа + `PopupContentBuilder` |
| `Sources/MacLimitsTrackerCore/Models/AppTheme.swift` | создать — перечисление тем |
| `Sources/MacLimitsTrackerCore/Models/AsciiRender.swift` | создать — текстовые рендеры полос (`AsciiBar`, `TuiGauge`) |
| `Sources/MacLimitsTracker/UI/StatusBarView.swift` | переписать — тонкий корневой переключатель тем |
| `Sources/MacLimitsTracker/UI/SystemStatusView.swift` | создать — текущий системный вид (рендер по `PopupRow`) |
| `Sources/MacLimitsTracker/UI/PopupFooter.swift` | создать — общий футер (пикеры, автообновление, Quit) |
| `Sources/MacLimitsTracker/UI/ThemeSupport.swift` | создать — `Color(hex:)` и общие мелочи тем |
| `Sources/MacLimitsTracker/UI/TerminalStatusView.swift` | создать — тема Terminal (Tokyo Night) |
| `Sources/MacLimitsTracker/UI/PhosphorStatusView.swift` | создать — тема Phosphor (CRT) |
| `Sources/MacLimitsTracker/UI/TUIStatusView.swift` | создать — тема TUI (htop) |
| `Tests/MacLimitsTrackerTests/PopupContentBuilderTests.swift` | создать |
| `Tests/MacLimitsTrackerTests/AppThemeTests.swift` | создать |
| `Tests/MacLimitsTrackerTests/AsciiRenderTests.swift` | создать |
| `README.md` | дополнить — раздел про темы |

---

### Task 1: Модель содержимого попапа (Core)

**Files:**
- Create: `Sources/MacLimitsTrackerCore/Models/PopupContent.swift`
- Test: `Tests/MacLimitsTrackerTests/PopupContentBuilderTests.swift`

**Interfaces:**
- Consumes: `ClaudeStatus`, `CodexStatus` (существующие модели Core).
- Produces (на них полагаются задачи 2–6):
  - `PopupRow` — enum: `.detail(key: String, value: String)`, `.window(WindowContent)`, `.error(String)`, `.note(String)`
  - `WindowContent` — `shortLabel: String`, `longLabel: String`, `remainingPercent: Double`, `remainingText: String`, `resetText: String?`, `severity: Severity`
  - `Severity` — `.normal | .warning | .critical`, `Severity.from(remainingPercent:)`
  - `PopupProvider` — `.claude | .codex`
  - `ProviderSectionContent` — `provider: PopupProvider`, `title: String`, `rows: [PopupRow]`
  - `PopupContentBuilder.claudeSection(_:now:) -> ProviderSectionContent`
  - `PopupContentBuilder.codexSection(_:now:) -> ProviderSectionContent`
  - `PopupContentBuilder.updatedText(claude:codex:) -> String`

- [ ] **Step 1: Написать падающие тесты**

Файл `Tests/MacLimitsTrackerTests/PopupContentBuilderTests.swift` целиком:

```swift
import XCTest
@testable import MacLimitsTrackerCore

final class SeverityTests: XCTestCase {
    func test_thresholdsByRemaining() {
        XCTAssertEqual(Severity.from(remainingPercent: 100), .normal)
        XCTAssertEqual(Severity.from(remainingPercent: 41), .normal)
        XCTAssertEqual(Severity.from(remainingPercent: 40), .warning)   // граница входит в warning
        XCTAssertEqual(Severity.from(remainingPercent: 16), .warning)
        XCTAssertEqual(Severity.from(remainingPercent: 15), .critical)  // граница входит в critical
        XCTAssertEqual(Severity.from(remainingPercent: 0), .critical)
    }
}

final class PopupContentBuilderClaudeTests: XCTestCase {
    private func makeStatus(
        providerError: String? = nil,
        usage: ClaudeUsage? = nil,
        usageError: String? = nil,
        subscriptionType: String? = "max"
    ) -> ClaudeStatus {
        ClaudeStatus(
            loggedIn: true, authMethod: "claude.ai", apiProvider: nil, email: "a@b.co",
            subscriptionType: subscriptionType, orgName: nil,
            today: nil, latestDay: nil, lastComputedDate: nil,
            totalSessions: nil, totalMessages: nil,
            usage: usage, usageError: usageError,
            fetchedAt: Date(timeIntervalSince1970: 1_000_000), providerError: providerError
        )
    }

    private func window(_ utilization: Double, resetsAt: Date? = nil) -> ClaudeUsageWindow {
        ClaudeUsageWindow(utilizationPercent: utilization, resetsAt: resetsAt,
                          limitDollars: nil, usedDollars: nil, remainingDollars: nil)
    }

    func test_nilStatus_isLoadingNote() {
        let s = PopupContentBuilder.claudeSection(nil)
        XCTAssertEqual(s.provider, .claude)
        XCTAssertEqual(s.title, "Claude Code")
        XCTAssertEqual(s.rows, [.note("Loading…")])
    }

    func test_providerError_isSingleErrorRow() {
        let s = PopupContentBuilder.claudeSection(makeStatus(providerError: "boom"))
        XCTAssertEqual(s.rows, [.error("boom")])
    }

    func test_planRow_showsRawSubscriptionType() {
        let s = PopupContentBuilder.claudeSection(makeStatus(usage: ClaudeUsage(fiveHour: nil, sevenDay: nil)))
        // Тариф без капитализации — как в текущем попапе.
        XCTAssertEqual(s.rows.first, .detail(key: "Plan", value: "max"))
    }

    func test_planRow_dashWhenNil() {
        let s = PopupContentBuilder.claudeSection(
            makeStatus(usage: ClaudeUsage(fiveHour: nil, sevenDay: nil), subscriptionType: nil))
        XCTAssertEqual(s.rows.first, .detail(key: "Plan", value: "—"))
    }

    func test_windows_remainingIsInverseOfUtilization() {
        let usage = ClaudeUsage(fiveHour: window(28), sevenDay: window(69))
        let s = PopupContentBuilder.claudeSection(makeStatus(usage: usage))
        guard case .window(let fh) = s.rows[1], case .window(let wk) = s.rows[2] else {
            return XCTFail("ожидались окна, rows: \(s.rows)")
        }
        XCTAssertEqual(fh.shortLabel, "5h")
        XCTAssertEqual(fh.longLabel, "5h")
        XCTAssertEqual(fh.remainingPercent, 72)
        XCTAssertEqual(fh.remainingText, "72%")
        XCTAssertEqual(fh.severity, .normal)
        XCTAssertEqual(wk.shortLabel, "wk")
        XCTAssertEqual(wk.longLabel, "Weekly")
        XCTAssertEqual(wk.remainingPercent, 31)
        XCTAssertEqual(wk.severity, .warning)
    }

    func test_windows_remainingClampedToZero() {
        let usage = ClaudeUsage(fiveHour: window(140), sevenDay: nil)
        let s = PopupContentBuilder.claudeSection(makeStatus(usage: usage))
        guard case .window(let fh) = s.rows[1] else { return XCTFail("\(s.rows)") }
        XCTAssertEqual(fh.remainingPercent, 0)
        XCTAssertEqual(fh.remainingText, "0%")
        XCTAssertEqual(fh.severity, .critical)
    }

    func test_missingWindow_becomesUnavailableNote() {
        let usage = ClaudeUsage(fiveHour: nil, sevenDay: window(10))
        let s = PopupContentBuilder.claudeSection(makeStatus(usage: usage))
        XCTAssertEqual(s.rows[1], .note("5h usage unavailable"))
        guard case .window = s.rows[2] else { return XCTFail("\(s.rows)") }
    }

    func test_resetText_presentOnlyWithResetsAt() {
        let usage = ClaudeUsage(fiveHour: window(50, resetsAt: Date().addingTimeInterval(7200)),
                                sevenDay: window(50))
        let s = PopupContentBuilder.claudeSection(makeStatus(usage: usage))
        guard case .window(let fh) = s.rows[1], case .window(let wk) = s.rows[2] else {
            return XCTFail("\(s.rows)")
        }
        // Точный текст зависит от локали — проверяем только наличие.
        XCTAssertNotNil(fh.resetText)
        XCTAssertNil(wk.resetText)
    }

    func test_usageError_shownWhenNoUsage() {
        let s = PopupContentBuilder.claudeSection(makeStatus(usageError: "token expired"))
        XCTAssertEqual(s.rows, [.detail(key: "Plan", value: "max"), .error("token expired")])
    }

    func test_noUsageNoError_loadingUsageNote() {
        let s = PopupContentBuilder.claudeSection(makeStatus())
        XCTAssertEqual(s.rows, [.detail(key: "Plan", value: "max"), .note("Loading usage…")])
    }
}

final class PopupContentBuilderCodexTests: XCTestCase {
    private func makeStatus(
        providerError: String? = nil,
        usage: CodexUsage? = nil,
        usageError: String? = nil,
        planType: String? = "plus",
        authMode: String? = "chatgpt",
        email: String? = "x@y.z",
        accountOwner: String? = "Acme",
        daysUntilRenewal: Int? = 12,
        subscriptionActiveUntil: Date? = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> CodexStatus {
        CodexStatus(
            loggedIn: true, authMode: authMode, email: email, planType: planType,
            subscriptionActiveUntil: subscriptionActiveUntil,
            daysUntilRenewal: daysUntilRenewal, accountOwner: accountOwner,
            usage: usage, usageError: usageError,
            fetchedAt: Date(timeIntervalSince1970: 2_000_000), providerError: providerError
        )
    }

    private func window(_ used: Double) -> CodexUsageWindow {
        CodexUsageWindow(usedPercent: used, windowDurationMins: nil, resetsAt: nil)
    }

    func test_nilStatus_isLoadingNote() {
        let s = PopupContentBuilder.codexSection(nil)
        XCTAssertEqual(s.provider, .codex)
        XCTAssertEqual(s.title, "Codex")
        XCTAssertEqual(s.rows, [.note("Loading…")])
    }

    func test_providerError_isSingleErrorRow() {
        let s = PopupContentBuilder.codexSection(makeStatus(providerError: "no auth.json"))
        XCTAssertEqual(s.rows, [.error("no auth.json")])
    }

    func test_snapshotPlanTypeWinsOverJwtClaim() {
        let snap = CodexUsageSnapshot(primary: nil, secondary: nil, planType: "pro",
                                      creditsBalance: nil, rateLimitReachedType: nil)
        let s = PopupContentBuilder.codexSection(makeStatus(usage: CodexUsage(snapshot: snap)))
        XCTAssertEqual(s.rows.first, .detail(key: "Plan", value: "pro"))
    }

    func test_fullSnapshot_rowOrder() {
        let snap = CodexUsageSnapshot(primary: window(42), secondary: window(56),
                                      planType: nil, creditsBalance: "12.50",
                                      rateLimitReachedType: "primary")
        let s = PopupContentBuilder.codexSection(makeStatus(usage: CodexUsage(snapshot: snap)))
        // Plan, 5h, weekly, Credits, rate-limit error, Auth, Account, Org, Renews in, Renews
        XCTAssertEqual(s.rows.count, 10)
        XCTAssertEqual(s.rows[0], .detail(key: "Plan", value: "plus"))
        guard case .window(let fh) = s.rows[1] else { return XCTFail("\(s.rows)") }
        XCTAssertEqual(fh.remainingPercent, 58)
        guard case .window(let wk) = s.rows[2] else { return XCTFail("\(s.rows)") }
        XCTAssertEqual(wk.remainingPercent, 44)
        XCTAssertEqual(s.rows[3], .detail(key: "Credits", value: "12.50"))
        XCTAssertEqual(s.rows[4], .error("rate limit reached: primary"))
        XCTAssertEqual(s.rows[5], .detail(key: "Auth", value: "chatgpt"))
        XCTAssertEqual(s.rows[6], .detail(key: "Account", value: "x@y.z"))
        XCTAssertEqual(s.rows[7], .detail(key: "Org", value: "Acme"))
        XCTAssertEqual(s.rows[8], .detail(key: "Renews in", value: "12 days"))
        guard case .detail(let key, _) = s.rows[9], key == "Renews" else { return XCTFail("\(s.rows)") }
    }

    func test_emptyCredits_skipped() {
        let snap = CodexUsageSnapshot(primary: nil, secondary: nil, planType: nil,
                                      creditsBalance: "", rateLimitReachedType: nil)
        let s = PopupContentBuilder.codexSection(
            makeStatus(usage: CodexUsage(snapshot: snap), authMode: nil, email: nil,
                       accountOwner: nil, daysUntilRenewal: nil, subscriptionActiveUntil: nil))
        XCTAssertEqual(s.rows, [.detail(key: "Plan", value: "plus"),
                                .note("5h usage unavailable"),
                                .note("Weekly usage unavailable")])
    }

    func test_usageError_shownWhenNoSnapshot() {
        let s = PopupContentBuilder.codexSection(
            makeStatus(usageError: "app-server unavailable", authMode: nil, email: nil,
                       accountOwner: nil, daysUntilRenewal: nil, subscriptionActiveUntil: nil))
        XCTAssertEqual(s.rows, [.detail(key: "Plan", value: "plus"),
                                .error("app-server unavailable")])
    }
}

final class PopupContentBuilderUpdatedTextTests: XCTestCase {
    func test_bothNil_dash() {
        XCTAssertEqual(PopupContentBuilder.updatedText(claude: nil, codex: nil), "—")
    }

    func test_latestOfTwoDates_used() {
        let claude = ClaudeStatus(
            loggedIn: true, authMethod: nil, apiProvider: nil, email: nil,
            subscriptionType: nil, orgName: nil, today: nil, latestDay: nil,
            lastComputedDate: nil, totalSessions: nil, totalMessages: nil,
            usage: nil, usageError: nil,
            fetchedAt: Date(timeIntervalSince1970: 100), providerError: nil)
        let text = PopupContentBuilder.updatedText(claude: claude, codex: nil)
        XCTAssertTrue(text.hasPrefix("Updated "), "получено: \(text)")
    }
}
```

- [ ] **Step 2: Убедиться, что тесты красные**

Run: `swift test 2>&1 | tail -5`
Expected: ошибка компиляции — `cannot find 'PopupContentBuilder' in scope` (красный за счёт некомпиляции — это валидный красный).

- [ ] **Step 3: Реализация**

Файл `Sources/MacLimitsTrackerCore/Models/PopupContent.swift` целиком:

```swift
import Foundation

/// Строка попапа. Темы рендерят каждый вид по-своему;
/// порядок строк задаёт PopupContentBuilder — единый для всех тем.
public enum PopupRow: Equatable {
    case detail(key: String, value: String)
    case window(WindowContent)
    case error(String)
    case note(String)
}

/// Серьёзность остатка лимита: пороги по ОСТАТКУ (не по использованному).
public enum Severity: Equatable {
    case normal
    case warning
    case critical

    public static func from(remainingPercent: Double) -> Severity {
        if remainingPercent <= 15 { return .critical }
        if remainingPercent <= 40 { return .warning }
        return .normal
    }
}

/// Одно окно лимита, готовое к показу.
public struct WindowContent: Equatable {
    public let shortLabel: String       // "5h" / "wk" — компактные темы
    public let longLabel: String        // "5h" / "Weekly" — системная тема
    public let remainingPercent: Double // 0…100, остаток
    public let remainingText: String    // "72%"
    public let resetText: String?       // "in 2 hours" / nil
    public let severity: Severity
}

public enum PopupProvider: Equatable {
    case claude
    case codex
}

/// Секция попапа одного провайдера.
public struct ProviderSectionContent: Equatable {
    public let provider: PopupProvider
    public let title: String
    public let rows: [PopupRow]
}

/// Сборка секций попапа из статусов провайдеров. Чистые функции — покрыты тестами.
public enum PopupContentBuilder {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    public static func claudeSection(_ status: ClaudeStatus?, now: Date = Date()) -> ProviderSectionContent {
        var rows: [PopupRow] = []
        if let c = status {
            if let e = c.providerError {
                rows.append(.error(e))
            } else {
                rows.append(.detail(key: "Plan", value: c.subscriptionType ?? "—"))
                if let u = c.usage {
                    rows.append(windowRow(short: "5h", long: "5h",
                                          remaining: u.fiveHour.map { max(0, 100 - $0.utilizationPercent) },
                                          resetsAt: u.fiveHour?.resetsAt, now: now,
                                          unavailable: "5h usage unavailable"))
                    rows.append(windowRow(short: "wk", long: "Weekly",
                                          remaining: u.sevenDay.map { max(0, 100 - $0.utilizationPercent) },
                                          resetsAt: u.sevenDay?.resetsAt, now: now,
                                          unavailable: "Weekly usage unavailable"))
                } else if let ue = c.usageError {
                    rows.append(.error(ue))
                } else {
                    rows.append(.note("Loading usage…"))
                }
            }
        } else {
            rows.append(.note("Loading…"))
        }
        return ProviderSectionContent(provider: .claude, title: "Claude Code", rows: rows)
    }

    public static func codexSection(_ status: CodexStatus?, now: Date = Date()) -> ProviderSectionContent {
        var rows: [PopupRow] = []
        if let x = status {
            if let e = x.providerError {
                rows.append(.error(e))
            } else {
                // Приоритет: live planType из app-server над JWT-claimом.
                let plan = x.usage?.snapshot?.planType ?? x.planType
                rows.append(.detail(key: "Plan", value: plan ?? "—"))
                if let snap = x.usage?.snapshot {
                    rows.append(windowRow(short: "5h", long: "5h",
                                          remaining: snap.primary.map { max(0, 100 - $0.usedPercent) },
                                          resetsAt: snap.primary?.resetsAt, now: now,
                                          unavailable: "5h usage unavailable"))
                    rows.append(windowRow(short: "wk", long: "Weekly",
                                          remaining: snap.secondary.map { max(0, 100 - $0.usedPercent) },
                                          resetsAt: snap.secondary?.resetsAt, now: now,
                                          unavailable: "Weekly usage unavailable"))
                    if let bal = snap.creditsBalance, !bal.isEmpty {
                        rows.append(.detail(key: "Credits", value: bal))
                    }
                    if let reached = snap.rateLimitReachedType {
                        rows.append(.error("rate limit reached: \(reached)"))
                    }
                } else if let ue = x.usageError {
                    rows.append(.error(ue))
                } else {
                    rows.append(.note("Loading usage…"))
                }
                if let auth = x.authMode { rows.append(.detail(key: "Auth", value: auth)) }
                if let email = x.email { rows.append(.detail(key: "Account", value: email)) }
                if let owner = x.accountOwner { rows.append(.detail(key: "Org", value: owner)) }
                if let days = x.daysUntilRenewal {
                    rows.append(.detail(key: "Renews in", value: "\(days) days"))
                }
                if let until = x.subscriptionActiveUntil {
                    rows.append(.detail(key: "Renews", value: dateFormatter.string(from: until)))
                }
            }
        } else {
            rows.append(.note("Loading…"))
        }
        return ProviderSectionContent(provider: .codex, title: "Codex", rows: rows)
    }

    public static func updatedText(claude: ClaudeStatus?, codex: CodexStatus?) -> String {
        let claudeFetched = claude?.fetchedAt ?? .distantPast
        let codexFetched = codex?.fetchedAt ?? .distantPast
        let latest = max(claudeFetched, codexFetched)
        if latest == .distantPast { return "—" }
        return "Updated \(timeFormatter.string(from: latest))"
    }

    private static func windowRow(short: String, long: String, remaining: Double?,
                                  resetsAt: Date?, now: Date, unavailable: String) -> PopupRow {
        guard let p = remaining else { return .note(unavailable) }
        return .window(WindowContent(
            shortLabel: short,
            longLabel: long,
            remainingPercent: p,
            remainingText: String(format: "%.0f%%", p),
            resetText: resetsAt.map { relativeFormatter.localizedString(for: $0, relativeTo: now) },
            severity: .from(remainingPercent: p)
        ))
    }
}
```

- [ ] **Step 4: Зелёный прогон**

Run: `swift test 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed`, число тестов выросло на ~18.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacLimitsTrackerCore/Models/PopupContent.swift Tests/MacLimitsTrackerTests/PopupContentBuilderTests.swift
git commit -m "feat(core): модель содержимого попапа PopupContentBuilder

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Рефакторинг StatusBarView на модель содержимого (вид не меняется)

**Files:**
- Create: `Sources/MacLimitsTracker/UI/SystemStatusView.swift`
- Create: `Sources/MacLimitsTracker/UI/PopupFooter.swift`
- Modify: `Sources/MacLimitsTracker/UI/StatusBarView.swift` (переписать целиком)

**Interfaces:**
- Consumes: `PopupContentBuilder`, `PopupRow`, `ProviderSectionContent` (Task 1); `LimitsViewModel`.
- Produces:
  - `SystemStatusView(viewModel:)` — текущая системная разметка, рендер по строкам
  - `PopupFooter(viewModel:)` — общий футер (пока без пикера темы, его добавит Task 3)
  - `StatusBarView(viewModel:)` — public-обёртка (та же сигнатура, что сейчас)

Визуальный результат ИДЕНТИЧЕН текущему. Юнит-тестов на вью нет — гейт задачи: сборка + существующие тесты + сравнение глазами в Task 7.

- [ ] **Step 1: Создать PopupFooter**

Файл `Sources/MacLimitsTracker/UI/PopupFooter.swift` целиком:

```swift
import SwiftUI
import MacLimitsTrackerCore

/// Общий футер всех тем: режим меню-бара, автообновление, выход.
struct PopupFooter: View {
    @ObservedObject var viewModel: LimitsViewModel
    @AppStorage("menuBarDisplayMode") private var displayMode: MenuBarDisplayMode = .iconAndText

    var body: some View {
        VStack(spacing: 8) {
            Picker("Menu bar", selection: $displayMode) {
                ForEach(MenuBarDisplayMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .controlSize(.mini)

            HStack {
                Toggle("Auto-refresh (5 min)", isOn: Binding(
                    get: { viewModel.autoRefresh },
                    set: { viewModel.setAutoRefresh($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
```

- [ ] **Step 2: Создать SystemStatusView**

Файл `Sources/MacLimitsTracker/UI/SystemStatusView.swift` целиком (перенос текущей разметки на рендер по `PopupRow`):

```swift
import SwiftUI
import MacLimitsTrackerCore

/// Системная тема: текущий нативный вид попапа.
struct SystemStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            section(PopupContentBuilder.claudeSection(viewModel.claude))
            Divider()
            section(PopupContentBuilder.codexSection(viewModel.codex))
            Divider()
            PopupFooter(viewModel: viewModel)
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Limits Tracker")
                    .font(.headline)
                Text(PopupContentBuilder.updatedText(claude: viewModel.claude, codex: viewModel.codex))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: viewModel.isRefreshing
                      ? "arrow.triangle.2.circlepath.circle"
                      : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
        }
    }

    private func section(_ s: ProviderSectionContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(s.title, color: s.provider == .claude ? .orange : .green)
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: PopupRow) -> some View {
        switch row {
        case .detail(let key, let value):
            detailRow(key, value)
        case .window(let w):
            detailRow("\(w.longLabel) remaining", w.remainingText)
            detailRow("\(w.longLabel) resets", w.resetText ?? "—")
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        case .note(let text):
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func sectionLabel(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
```

- [ ] **Step 3: Переписать StatusBarView**

Файл `Sources/MacLimitsTracker/UI/StatusBarView.swift` целиком (тонкая public-обёртка; переключение тем добавит Task 3):

```swift
import SwiftUI
import MacLimitsTrackerCore

/// Корень попапа статус-бара. Публичная точка входа для App.
public struct StatusBarView: View {
    @ObservedObject var viewModel: LimitsViewModel

    public init(viewModel: LimitsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SystemStatusView(viewModel: viewModel)
            .accessibilityIdentifier("statusBarPopup")
    }
}
```

- [ ] **Step 4: Сборка и тесты**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -5`
Expected: сборка без ошибок, `Test Suite 'All tests' passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacLimitsTracker/UI/
git commit -m "refactor(ui): StatusBarView рендерит через PopupContentBuilder, футер вынесен

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: AppTheme + переключатель + каркас тем

**Files:**
- Create: `Sources/MacLimitsTrackerCore/Models/AppTheme.swift`
- Create: `Sources/MacLimitsTracker/UI/ThemeSupport.swift`
- Modify: `Sources/MacLimitsTracker/UI/StatusBarView.swift`
- Modify: `Sources/MacLimitsTracker/UI/PopupFooter.swift`
- Test: `Tests/MacLimitsTrackerTests/AppThemeTests.swift`

**Interfaces:**
- Produces:
  - `AppTheme` — `case system, terminal, phosphor, tui`; `title: String`; `RawRepresentable (String)`, `CaseIterable`, `Identifiable`
  - `Color(hex: UInt32)` — extension в App-таргете
  - `StatusBarView` switch по теме (пока все терминальные case → `SystemStatusView`; задачи 4–6 заменят каждый на свой вид)
  - В `PopupFooter` появляется Picker «Theme» первым элементом

- [ ] **Step 1: Падающий тест**

Файл `Tests/MacLimitsTrackerTests/AppThemeTests.swift` целиком:

```swift
import XCTest
@testable import MacLimitsTrackerCore

final class AppThemeTests: XCTestCase {
    func test_rawValuesStable_forPersistence() {
        // rawValue персистится в @AppStorage — менять нельзя.
        XCTAssertEqual(AppTheme.system.rawValue, "system")
        XCTAssertEqual(AppTheme.terminal.rawValue, "terminal")
        XCTAssertEqual(AppTheme.phosphor.rawValue, "phosphor")
        XCTAssertEqual(AppTheme.tui.rawValue, "tui")
    }

    func test_allCasesOrder_systemFirst() {
        XCTAssertEqual(AppTheme.allCases, [.system, .terminal, .phosphor, .tui])
    }

    func test_titles() {
        XCTAssertEqual(AppTheme.system.title, "System")
        XCTAssertEqual(AppTheme.terminal.title, "Terminal")
        XCTAssertEqual(AppTheme.phosphor.title, "Phosphor")
        XCTAssertEqual(AppTheme.tui.title, "TUI")
    }
}
```

- [ ] **Step 2: Красный прогон**

Run: `swift test 2>&1 | tail -5`
Expected: ошибка компиляции `cannot find 'AppTheme' in scope`.

- [ ] **Step 3: Реализация AppTheme**

Файл `Sources/MacLimitsTrackerCore/Models/AppTheme.swift` целиком:

```swift
import Foundation

/// Тема попапа. rawValue персистится в @AppStorage("appTheme") — значения не менять.
public enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case terminal
    case phosphor
    case tui

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system:   return "System"
        case .terminal: return "Terminal"
        case .phosphor: return "Phosphor"
        case .tui:      return "TUI"
        }
    }
}
```

- [ ] **Step 4: Зелёный прогон**

Run: `swift test 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 5: ThemeSupport + переключение**

Файл `Sources/MacLimitsTracker/UI/ThemeSupport.swift` целиком:

```swift
import SwiftUI

extension Color {
    /// Цвет из hex-константы палитры темы: Color(hex: 0x1A1B26).
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
```

В `StatusBarView.swift` body заменить на switch (терминальные темы пока падают в System — их заменят задачи 4–6):

```swift
public struct StatusBarView: View {
    @ObservedObject var viewModel: LimitsViewModel
    @AppStorage("appTheme") private var theme: AppTheme = .system

    public init(viewModel: LimitsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            switch theme {
            case .system:
                SystemStatusView(viewModel: viewModel)
            case .terminal:
                SystemStatusView(viewModel: viewModel) // заменит Task 4
            case .phosphor:
                SystemStatusView(viewModel: viewModel) // заменит Task 5
            case .tui:
                SystemStatusView(viewModel: viewModel) // заменит Task 6
            }
        }
        .accessibilityIdentifier("statusBarPopup")
    }
}
```

В `PopupFooter.swift` добавить пикер темы ПЕРВЫМ элементом VStack (до пикера «Menu bar»):

```swift
    @AppStorage("appTheme") private var theme: AppTheme = .system
```

```swift
            Picker("Theme", selection: $theme) {
                ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .controlSize(.mini)
```

- [ ] **Step 6: Сборка и тесты**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -5`
Expected: зелёные.

- [ ] **Step 7: Commit**

```bash
git add Sources/MacLimitsTrackerCore/Models/AppTheme.swift Sources/MacLimitsTracker/UI/ Tests/MacLimitsTrackerTests/AppThemeTests.swift
git commit -m "feat(ui): AppTheme и переключатель темы в футере

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Тема Terminal (Tokyo Night)

**Files:**
- Create: `Sources/MacLimitsTracker/UI/TerminalStatusView.swift`
- Modify: `Sources/MacLimitsTracker/UI/StatusBarView.swift` (case `.terminal`)

**Interfaces:**
- Consumes: `PopupContentBuilder`, `PopupRow`, `WindowContent`, `Severity`, `PopupFooter`, `Color(hex:)`.
- Produces: `TerminalStatusView(viewModel:)`.

- [ ] **Step 1: Реализация**

Файл `Sources/MacLimitsTracker/UI/TerminalStatusView.swift` целиком:

```swift
import SwiftUI
import MacLimitsTrackerCore

/// Тема Terminal: палитра Tokyo Night, тонкие полосы прогресса.
struct TerminalStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel

    private enum Palette {
        static let bg = Color(hex: 0x1A1B26)
        static let fg = Color(hex: 0xC0CAF5)
        static let dim = Color(hex: 0x565F89)
        static let track = Color(hex: 0x2F334D)
        static let cyan = Color(hex: 0x7DCFFF)
        static let claude = Color(hex: 0xFF9E64)
        static let codex = Color(hex: 0x9ECE6A)
        static let warning = Color(hex: 0xE0AF68)
        static let critical = Color(hex: 0xF7768E)
    }

    private let mono = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            section(PopupContentBuilder.claudeSection(viewModel.claude), accent: Palette.claude, name: "claude")
            section(PopupContentBuilder.codexSection(viewModel.codex), accent: Palette.codex, name: "codex")
            Rectangle().fill(Palette.track).frame(height: 1)
            PopupFooter(viewModel: viewModel)
                .tint(Palette.cyan)
        }
        .font(mono)
        .foregroundStyle(Palette.fg)
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
        .background(Palette.bg)
        .environment(\.colorScheme, .dark) // системные контролы читаемы на тёмном фоне
    }

    private var header: some View {
        HStack {
            Text("limits-tracker").foregroundStyle(Palette.cyan)
            Spacer()
            Text(PopupContentBuilder.updatedText(claude: viewModel.claude, codex: viewModel.codex))
                .foregroundStyle(Palette.dim)
            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(viewModel.isRefreshing ? Palette.dim : Palette.cyan)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
        }
    }

    private func section(_ s: ProviderSectionContent, accent: Color, name: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("●").foregroundStyle(accent)
                Text(name)
                // Значение Plan из первой detail-строки показываем рядом с именем.
                if case .detail(let key, let value) = s.rows.first, key == "Plan" {
                    Text(value).foregroundStyle(Palette.dim)
                }
                Spacer()
            }
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, row in
                rowView(row, accent: accent)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: PopupRow, accent: Color) -> some View {
        switch row {
        case .detail(let key, let value):
            // Plan уже показан в заголовке секции.
            if key != "Plan" {
                HStack {
                    Text(key.lowercased()).foregroundStyle(Palette.dim)
                    Spacer(minLength: 8)
                    Text(value).lineLimit(1).truncationMode(.middle)
                }
            }
        case .window(let w):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(w.shortLabel).foregroundStyle(Palette.dim)
                        .frame(width: 20, alignment: .leading)
                    bar(w, accent: accent)
                    Text(w.remainingText).monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                if let reset = w.resetText {
                    Text("resets \(reset)")
                        .foregroundStyle(Palette.dim)
                        .padding(.leading, 26)
                }
            }
        case .error(let message):
            Text("✗ \(message)").foregroundStyle(Palette.critical)
        case .note(let text):
            Text(text).foregroundStyle(Palette.dim)
        }
    }

    private func bar(_ w: WindowContent, accent: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(barColor(w.severity, accent: accent))
                    .frame(width: max(4, geo.size.width * w.remainingPercent / 100))
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.3), value: w.remainingPercent)
    }

    private func barColor(_ severity: Severity, accent: Color) -> Color {
        switch severity {
        case .normal:   return accent
        case .warning:  return Palette.warning
        case .critical: return Palette.critical
        }
    }
}
```

В `StatusBarView.swift` case `.terminal` заменить на:

```swift
            case .terminal:
                TerminalStatusView(viewModel: viewModel)
```

- [ ] **Step 2: Сборка и тесты**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -5`
Expected: зелёные.

- [ ] **Step 3: Commit**

```bash
git add Sources/MacLimitsTracker/UI/
git commit -m "feat(ui): тема Terminal (Tokyo Night)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Тема Phosphor (ретро-CRT)

**Files:**
- Create: `Sources/MacLimitsTrackerCore/Models/AsciiRender.swift` (только `AsciiBar`; `TuiGauge` добавит Task 6)
- Create: `Sources/MacLimitsTracker/UI/PhosphorStatusView.swift`
- Modify: `Sources/MacLimitsTracker/UI/StatusBarView.swift` (case `.phosphor`)
- Test: `Tests/MacLimitsTrackerTests/AsciiRenderTests.swift`

**Interfaces:**
- Produces:
  - `AsciiBar.render(remainingPercent: Double, width: Int = 14) -> String` — строка из `█`/`░`
  - `PhosphorStatusView(viewModel:)`

- [ ] **Step 1: Падающие тесты**

Файл `Tests/MacLimitsTrackerTests/AsciiRenderTests.swift` (пока только AsciiBar; Task 6 допишет сюда TuiGauge):

```swift
import XCTest
@testable import MacLimitsTrackerCore

final class AsciiBarTests: XCTestCase {
    func test_empty_full_half() {
        XCTAssertEqual(AsciiBar.render(remainingPercent: 0), String(repeating: "░", count: 14))
        XCTAssertEqual(AsciiBar.render(remainingPercent: 100), String(repeating: "█", count: 14))
        XCTAssertEqual(AsciiBar.render(remainingPercent: 50),
                       String(repeating: "█", count: 7) + String(repeating: "░", count: 7))
    }

    func test_clampsOutOfRange() {
        XCTAssertEqual(AsciiBar.render(remainingPercent: -5), String(repeating: "░", count: 14))
        XCTAssertEqual(AsciiBar.render(remainingPercent: 140), String(repeating: "█", count: 14))
    }

    func test_customWidth() {
        XCTAssertEqual(AsciiBar.render(remainingPercent: 50, width: 4), "██░░")
    }
}
```

- [ ] **Step 2: Красный прогон**

Run: `swift test 2>&1 | tail -5`
Expected: ошибка компиляции `cannot find 'AsciiBar' in scope`.

- [ ] **Step 3: Реализация AsciiBar**

Файл `Sources/MacLimitsTrackerCore/Models/AsciiRender.swift`:

```swift
import Foundation

/// Текстовая полоса прогресса темы Phosphor: `██████░░░░` (заполнено = остаток).
public enum AsciiBar {
    public static func render(remainingPercent: Double, width: Int = 14) -> String {
        let clamped = min(100, max(0, remainingPercent))
        let filled = Int((clamped / 100 * Double(width)).rounded())
        return String(repeating: "█", count: filled)
             + String(repeating: "░", count: width - filled)
    }
}
```

- [ ] **Step 4: Зелёный прогон**

Run: `swift test 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 5: PhosphorStatusView**

Файл `Sources/MacLimitsTracker/UI/PhosphorStatusView.swift` целиком:

```swift
import SwiftUI
import MacLimitsTrackerCore

/// Тема Phosphor: монохромный зелёный CRT.
struct PhosphorStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel
    @State private var cursorVisible = true

    private enum Palette {
        static let bg = Color(hex: 0x050805)
        static let bright = Color(hex: 0x35E06A)
        static let mid = Color(hex: 0x1E9C48)
        static let dim = Color(hex: 0x164A26)
        static let heading = Color(hex: 0x8DFFB0)
    }

    private let mono = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            section(PopupContentBuilder.claudeSection(viewModel.claude), name: "CLAUDE CODE")
            section(PopupContentBuilder.codexSection(viewModel.codex), name: "CODEX")
            promptLine
            PopupFooter(viewModel: viewModel)
                .tint(Palette.mid)
        }
        .font(mono)
        .foregroundStyle(Palette.bright)
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
        .background(Palette.bg)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Text("~/limits — \(PopupContentBuilder.updatedText(claude: viewModel.claude, codex: viewModel.codex).lowercased())")
                .foregroundStyle(Palette.mid)
            Spacer()
            Button {
                viewModel.refresh()
            } label: {
                Text("[r]").foregroundStyle(viewModel.isRefreshing ? Palette.dim : Palette.bright)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
        }
    }

    // Мигающий курсор — единственная анимация темы.
    private var promptLine: some View {
        HStack(spacing: 2) {
            Text("$").foregroundStyle(Palette.mid)
            Text("▮")
                .foregroundStyle(Palette.bright)
                .opacity(cursorVisible ? 1 : 0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        cursorVisible = false
                    }
                }
        }
    }

    private func section(_ s: ProviderSectionContent, name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("▸ \(name)").foregroundStyle(Palette.heading)
                if case .detail(let key, let value) = s.rows.first, key == "Plan" {
                    Text("[\(value)]").foregroundStyle(Palette.mid)
                }
                Spacer()
            }
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: PopupRow) -> some View {
        switch row {
        case .detail(let key, let value):
            if key != "Plan" {
                HStack {
                    Text(key.lowercased()).foregroundStyle(Palette.mid)
                    Spacer(minLength: 8)
                    Text(value).lineLimit(1).truncationMode(.middle)
                }
            }
        case .window(let w):
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(w.shortLabel)
                        .foregroundStyle(Palette.mid)
                        .frame(width: 20, alignment: .leading)
                    if w.severity == .critical {
                        // Критичный остаток — инверсия: тёмный текст на яркой плашке.
                        Text(AsciiBar.render(remainingPercent: w.remainingPercent))
                            .foregroundStyle(Palette.bg)
                            .background(Palette.bright)
                    } else {
                        Text(AsciiBar.render(remainingPercent: w.remainingPercent))
                    }
                    Text(w.remainingText).monospacedDigit()
                }
                if let reset = w.resetText {
                    Text("reset \(reset)")
                        .foregroundStyle(Palette.mid)
                        .padding(.leading, 26)
                }
            }
        case .error(let message):
            Text("! \(message)").foregroundStyle(Palette.heading)
        case .note(let text):
            Text(text).foregroundStyle(Palette.mid)
        }
    }
}
```

В `StatusBarView.swift` case `.phosphor` заменить на:

```swift
            case .phosphor:
                PhosphorStatusView(viewModel: viewModel)
```

- [ ] **Step 6: Сборка и тесты**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -5`
Expected: зелёные.

- [ ] **Step 7: Commit**

```bash
git add Sources/MacLimitsTrackerCore/Models/AsciiRender.swift Sources/MacLimitsTracker/UI/ Tests/MacLimitsTrackerTests/AsciiRenderTests.swift
git commit -m "feat(ui): тема Phosphor (ретро-CRT) + AsciiBar

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Тема TUI (htop-панель)

**Files:**
- Modify: `Sources/MacLimitsTrackerCore/Models/AsciiRender.swift` (добавить `TuiGauge`)
- Create: `Sources/MacLimitsTracker/UI/TUIStatusView.swift`
- Modify: `Sources/MacLimitsTracker/UI/StatusBarView.swift` (case `.tui`)
- Test: `Tests/MacLimitsTrackerTests/AsciiRenderTests.swift` (дописать)

**Interfaces:**
- Produces:
  - `TuiGauge.filledCount(remainingPercent: Double, width: Int = 14) -> Int`
  - `TUIStatusView(viewModel:)`

- [ ] **Step 1: Падающие тесты**

Дописать в `Tests/MacLimitsTrackerTests/AsciiRenderTests.swift`:

```swift
final class TuiGaugeTests: XCTestCase {
    func test_boundaries() {
        XCTAssertEqual(TuiGauge.filledCount(remainingPercent: 0), 0)
        XCTAssertEqual(TuiGauge.filledCount(remainingPercent: 100), 14)
        XCTAssertEqual(TuiGauge.filledCount(remainingPercent: 50), 7)
    }

    func test_clampsOutOfRange() {
        XCTAssertEqual(TuiGauge.filledCount(remainingPercent: -1), 0)
        XCTAssertEqual(TuiGauge.filledCount(remainingPercent: 101), 14)
    }

    func test_customWidth() {
        XCTAssertEqual(TuiGauge.filledCount(remainingPercent: 25, width: 8), 2)
    }
}
```

- [ ] **Step 2: Красный прогон**

Run: `swift test 2>&1 | tail -5`
Expected: ошибка компиляции `cannot find 'TuiGauge' in scope`.

- [ ] **Step 3: Реализация TuiGauge**

Дописать в `Sources/MacLimitsTrackerCore/Models/AsciiRender.swift`:

```swift
/// Датчик темы TUI `[||||······]`: число заполненных делений (заполнено = остаток).
public enum TuiGauge {
    public static func filledCount(remainingPercent: Double, width: Int = 14) -> Int {
        let clamped = min(100, max(0, remainingPercent))
        return Int((clamped / 100 * Double(width)).rounded())
    }
}
```

- [ ] **Step 4: Зелёный прогон**

Run: `swift test 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 5: TUIStatusView**

Файл `Sources/MacLimitsTracker/UI/TUIStatusView.swift` целиком:

```swift
import SwiftUI
import MacLimitsTrackerCore

/// Тема TUI: панели с рамками и датчиками в духе htop.
struct TUIStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel

    private enum Palette {
        static let bg = Color(hex: 0x101216)
        static let fg = Color(hex: 0xD0D5DD)
        static let border = Color(hex: 0x3A4150)
        static let dim = Color(hex: 0x5A6374)
        static let normal = Color(hex: 0x9ECE6A)
        static let warning = Color(hex: 0xE0AF68)
        static let critical = Color(hex: 0xF7768E)
    }

    private let mono = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            panel(PopupContentBuilder.claudeSection(viewModel.claude))
            panel(PopupContentBuilder.codexSection(viewModel.codex))
            PopupFooter(viewModel: viewModel)
                .tint(Palette.normal)
        }
        .font(mono)
        .foregroundStyle(Palette.fg)
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
        .background(Palette.bg)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Text(PopupContentBuilder.updatedText(claude: viewModel.claude, codex: viewModel.codex))
                .foregroundStyle(Palette.dim)
            Spacer()
            Button {
                viewModel.refresh()
            } label: {
                keyBadge("F5 refresh")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
        }
    }

    private func keyBadge(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Palette.border)
            .foregroundStyle(Palette.fg)
    }

    // Панель с рамкой; заголовок врезан в верхнюю кромку — рамку рисуем
    // SwiftUI-обводкой, не символами (символьные рамки «плывут» по ширине).
    private func panel(_ s: ProviderSectionContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
        }
        .padding(10)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Palette.border, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                Text(s.title.uppercased())
                if case .detail(let key, let value) = s.rows.first, key == "Plan" {
                    Text("─ \(value)").foregroundStyle(Palette.dim)
                }
            }
            .padding(.horizontal, 4)
            .background(Palette.bg)
            .foregroundStyle(Palette.dim)
            .offset(x: 8, y: -8)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func rowView(_ row: PopupRow) -> some View {
        switch row {
        case .detail(let key, let value):
            if key != "Plan" {
                HStack {
                    Text(key.lowercased()).foregroundStyle(Palette.dim)
                    Spacer(minLength: 8)
                    Text(value).lineLimit(1).truncationMode(.middle)
                }
            }
        case .window(let w):
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(w.shortLabel)
                        .foregroundStyle(Palette.dim)
                        .frame(width: 20, alignment: .leading)
                    gauge(w)
                    Text(w.remainingText).monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                if let reset = w.resetText {
                    Text("reset \(reset)")
                        .foregroundStyle(Palette.dim)
                        .padding(.leading, 24)
                }
            }
        case .error(let message):
            Text("✗ \(message)").foregroundStyle(Palette.critical)
        case .note(let text):
            Text(text).foregroundStyle(Palette.dim)
        }
    }

    // Датчик [||||······]: заполнено = остаток; цвет по severity.
    private func gauge(_ w: WindowContent) -> some View {
        let width = 14
        let filled = TuiGauge.filledCount(remainingPercent: w.remainingPercent, width: width)
        return (
            Text("[")
            + Text(String(repeating: "|", count: filled))
                .foregroundStyle(severityColor(w.severity))
            + Text(String(repeating: "·", count: width - filled))
                .foregroundStyle(Palette.border)
            + Text("]")
        )
        .foregroundStyle(Palette.dim)
    }

    private func severityColor(_ severity: Severity) -> Color {
        switch severity {
        case .normal:   return Palette.normal
        case .warning:  return Palette.warning
        case .critical: return Palette.critical
        }
    }
}
```

В `StatusBarView.swift` case `.tui` заменить на:

```swift
            case .tui:
                TUIStatusView(viewModel: viewModel)
```

- [ ] **Step 6: Сборка и тесты**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -5`
Expected: зелёные.

- [ ] **Step 7: Commit**

```bash
git add Sources/MacLimitsTrackerCore/Models/AsciiRender.swift Sources/MacLimitsTracker/UI/ Tests/MacLimitsTrackerTests/AsciiRenderTests.swift
git commit -m "feat(ui): тема TUI (htop-панель) + TuiGauge

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Проверка глазами + README

**Files:**
- Modify: `README.md` (раздел про темы)

**Interfaces:**
- Consumes: всё предыдущее.

- [ ] **Step 1: Полный прогон**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -5`
Expected: зелёные, все тесты.

- [ ] **Step 2: Собрать и запустить приложение**

```bash
./make-app.sh && open MacLimitsTracker.app
```

Проверить глазами (чек-лист):
- [ ] System: попап выглядит как до рестайлинга (сравнить с main).
- [ ] Переключение темы в футере мгновенно меняет вид; после перезапуска приложения тема сохранена.
- [ ] Terminal: тёмный фон без белых «просветов», полосы заполнены на величину ОСТАТКА, проценты совпадают с System.
- [ ] Phosphor: монохром, полоса `█░`, курсор мигает.
- [ ] TUI: рамки не рвутся при длинных значениях (проверить длинный email в Account).
- [ ] В каждой теме работают: Refresh, пикер меню-бара, автообновление, Quit.
- [ ] Кейс ошибки: временно переименовать `~/.codex/auth.json` → секция Codex показывает ошибку во всех темах; вернуть файл обратно.

- [ ] **Step 3: README**

Добавить в `README.md` после описания возможностей раздел:

```markdown
## Themes

The popup supports four themes, switchable from the footer picker:

- **System** — native macOS look (default)
- **Terminal** — Tokyo Night palette with progress bars
- **Phosphor** — monochrome green CRT with `█░` bars
- **TUI** — htop-style panels with `[||||··]` gauges

The choice is persisted in `UserDefaults` (`appTheme`).
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: раздел Themes в README

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Соответствие задач плана бидам

| Задача плана | Бид |
|---|---|
| Task 1, Task 2 | `mac-limits-tracker-8zk.1` |
| Task 3 | `mac-limits-tracker-8zk.2` |
| Task 4 | `mac-limits-tracker-8zk.3` |
| Task 5 | `mac-limits-tracker-8zk.4` |
| Task 6 | `mac-limits-tracker-8zk.5` |
| Task 7 | `mac-limits-tracker-8zk.6` |

После каждой задачи: `bd close <бид> --reason "…" ` (для .1 — после Task 2). Эпик `mac-limits-tracker-8zk` закрывается после Task 7 и слияния ветки (слияние в `main` — только через PR, с подтверждением пользователя).

## Известные риски

- `RelativeDateTimeFormatter`/локаль: тексты сброса не проверяются на точное совпадение — только на наличие (см. тесты).
- `MenuBarExtra(.window)` может добавлять системный фон вокруг контента: если по углам видны белые полосы — добавить `.ignoresSafeArea()` к `.background(...)` темы.
- Пикеры/тумблер на тёмном фоне: обязателен `.environment(\.colorScheme, .dark)` на корне темы (уже в коде).
- В `PopupFooter` кнопка Quit со стилем `.borderedProminent` в тёмных темах перекрашивается через `.tint` родителя — это ожидаемо.
