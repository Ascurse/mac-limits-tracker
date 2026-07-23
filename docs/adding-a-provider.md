# Как добавить нового провайдера лимитов

Гайд для тех, кто добавляет источник данных о лимитах нового AI-инструмента
(по образцу Claude/Codex, и Kimi как самый свежий пример — bd
mac-limits-tracker-6gk.3) и не хочет читать весь стек кода. Изучать нужно
только `Sources/MacLimitsTrackerCore/Providers/` и модели, перечисленные
ниже, — UI-слой трогать не придётся.

## Контракт: протокол `LimitsProvider`

Файл: [`Sources/MacLimitsTrackerCore/Providers/LimitsProvider.swift`](../Sources/MacLimitsTrackerCore/Providers/LimitsProvider.swift)

```swift
public protocol LimitsProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func fetch() async -> LimitsSnapshot
}
```

Это единственная граница между новым провайдером и остальным приложением.
`descriptor` — статичное самоописание (имя, цвет, иконка), не требующее
сети. `fetch()` — асинхронный опрос реального источника (CLI/файл/keychain/
HTTP), результат которого приводится к единому `LimitsSnapshot`.

## Шаги

### 1. Новый тип, конформящий `LimitsProvider`

Заведи `struct` рядом с `ClaudeLimitsProvider`/`CodexLimitsProvider` в
[`Providers/LimitsProviders.swift`](../Sources/MacLimitsTrackerCore/Providers/LimitsProviders.swift)
(для крупного провайдера — отдельный файл в `Providers/`, но `LimitsProviders.swift`
уже держит оба существующих, так что дробить не обязательно).

Паттерн — DI через замыкания в `init` с продовыми дефолтами, чтобы тесты
подменяли источники данных без реальных подпроцессов/сети/файлов:

```swift
public struct NewProvider: @unchecked Sendable {
    let credentialsURL: URL
    let fileReader: (URL) async throws -> Data

    public init(
        credentialsURL: URL = NewProvider.defaultCredentialsURL,
        fileReader: @escaping (URL) async throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.credentialsURL = credentialsURL
        self.fileReader = fileReader
    }

    func fetchStatus() async -> NewProviderStatus { ... }
}
```

`@unchecked Sendable` оправдан, только если замыкания без состояния
(процесс/файл/keychain-ридеры в проде их и не имеют) — см. комментарий над
`ClaudeLimitsProvider` в коде. Если провайдер держит мутируемое состояние —
нужен другой примитив, не просто аннотация.

Публичный статический URL по умолчанию (`defaultCredentialsURL` и т.п.)
должен быть `public`, если на него ссылается `ProviderRegistry` — Swift
требует видимость параметра по умолчанию не ниже видимости функции, даже в
пределах модуля (грабли, на которые уже наступил Kimi-провайдер).

### 2. Внутренний DTO + маппинг в `LimitsSnapshot`

Внутренний статус-тип (`NewProviderStatus`, `internal`/`struct Equatable`)
живёт в `Models/NewProviderModels.swift` — по образцу `Models/ClaudeModels.swift`
/ `Models/CodexModels.swift` (Kimi — `Models/KimiModels.swift`). Наружу из
модуля этот тип не уходит: единственный публичный результат — `LimitsSnapshot`.

Маппинг `DTO → LimitsSnapshot` — расширение `toSnapshot()` в
[`Providers/SnapshotMapping.swift`](../Sources/MacLimitsTrackerCore/Providers/SnapshotMapping.swift),
плюс расширение `NewProvider: LimitsProvider`, где `fetch()` — это ровно
`await fetchStatus().toSnapshot()`:

```swift
extension NewProvider: LimitsProvider {
    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: "newprovider",
            displayName: "New Provider",
            shortName: "NewP",
            menuBarSymbol: "N",
            accentColorHex: 0x7AA2F7,
            loginHelp: nil
        )
    }

    public func fetch() async -> LimitsSnapshot {
        await fetchStatus().toSnapshot()
    }
}

extension NewProviderStatus {
    func toSnapshot() -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: loggedIn,
            plan: plan,
            windows: windows,           // nil, если usage ещё не опрошен
            creditsBalance: nil,
            rateLimitReachedType: nil,
            details: [],
            daysUntilRenewal: nil,
            renewalDate: nil,
            usageError: usageError,
            providerError: providerError,
            fetchedAt: fetchedAt
        )
    }
}
```

`ProviderDescriptor` (см. [`Models/ProviderDescriptor.swift`](../Sources/MacLimitsTrackerCore/Models/ProviderDescriptor.swift)):
`id` — ключ для настроек и accessibility (уникальный, стабильный, не менять
после релиза — на нём завязано хранилище `ProviderSettingsStore`);
`displayName` — заголовок секции попапа; `shortName`/`menuBarSymbol` —
компактные режимы меню-бара; `loginHelp` — если у провайдера есть команда
для обновления логина (как у Claude), иначе `nil`.

Если у провайдера **нет локального источника usage** (нет ни файла, ни CLI,
ни подтверждённого API — так у Kimi) — это нормально: `windows` в снапшоте
всегда `nil`, а `usageError` объясняет пользователю, что данных не будет
(не `"Loading…"` — это подразумевало бы, что они появятся). Пример —
`KimiStatus.toSnapshot()` на ветке bd-mac-limits-tracker-6gk.3.

### 3. Регистрация в `ProviderRegistry.makeDefault()`

[`Providers/LimitsProvider.swift`](../Sources/MacLimitsTrackerCore/Providers/LimitsProvider.swift):

```swift
public enum ProviderRegistry {
    public static func makeDefault() -> [any LimitsProvider] {
        [ClaudeLimitsProvider(), CodexLimitsProvider()]
    }
}
```

Добавь конструктор нового провайдера в возвращаемый массив. Больше никаких
правок не требуется: `LimitsViewModel` строит `states: [ProviderState]` по
этому списку и обновляет их параллельно через `TaskGroup`, ничего не зная о
конкретных провайдерах.

Если провайдер требует credentials, которых может не быть (как Kimi — файл
`~/.kimi-code/credentials/kimi-code.json` есть не у всех), сделай
регистрацию условной: синхронная проверка без сети/подпроцессов
(`hasUsableCredentials(at:)`) перед добавлением в массив, чтобы провайдер
без рабочих credentials просто не появлялся в реестре, а не показывал
постоянную ошибку. См. Шаг (g) ниже.

### 4. Правило «UI не знает о провайдере»

Ни одна тема (`Sources/MacLimitsTracker/UI/*StatusView.swift`), меню-бар или
десктоп-виджет **не должны** содержать `if descriptor.id == "..."` или любую
другую provider-специфичную логику. Всё, что доступно UI-слою — это
`ProviderDescriptor` (цвет/имя/иконка/`loginHelp`) и `PopupRow`, который
строит `PopupContentBuilder.section(state:)` из `LimitsSnapshot`
(`Sources/MacLimitsTrackerCore/Models/PopupContent.swift`). Если для нового
провайдера кажется, что нужна ветка в UI — это сигнал, что данные нужно
привести к существующей форме `LimitsSnapshot`/`PopupRow` в маппере (Шаг 2),
а не добавлять условие в тему.

### 5. Конвенции по данным

- **Окна лимитов** различаются по `SnapshotWindow.windowDurationMins`
  (300 = 5h, 10080 = weekly), **не по позиции** в ответе API — порядок окон
  в ответе не гарантирован. См. `RateLimitWindowLabel` и
  `CodexStatus.windowSortKey` в `SnapshotMapping.swift` (bd
  mac-limits-tracker-w4a).
- **`SnapshotWindow.usedPercent == nil`** значит «слот заявлен, но данных
  нет» (в попапе — «… usage unavailable»), а не «слота нет». Различай это
  от `LimitsSnapshot.windows == nil` («usage вообще ещё не загружен» /
  «нет источника usage» — тогда попап покажет `usageError` или
  «Loading usage…»).

### 6. Как проверить

```bash
swift build              # весь пакет: MacLimitsTracker + Core + VerifyCli
swift test                # Tests/MacLimitsTrackerTests
swift run -c release VerifyCli  # диагностика реальных лимитов
```

`VerifyCli` крутится по `ProviderRegistry.makeDefault()` и печатает реальные
снапшоты по всем зарегистрированным провайдерам — удобно проверить новый
провайдер целиком, с настоящими credentials. **Только `-c release`** — в
debug-сборке `swift run VerifyCli` падает с ложным abort про
«pointer being freed was not allocated» при выходе из процесса (не баг кода
проекта, а срабатывание nano-malloc-проверки в debug); см.
[`docs/journal/gotchas.md`](journal/gotchas.md) и
[`Sources/VerifyCli/main.swift`](../Sources/VerifyCli/main.swift).

Для юнит-тестов маппинга/дескриптора смотри существующие примеры:
`Tests/MacLimitsTrackerTests/SnapshotMappingTests.swift` (тесты
`toSnapshot()` через DI-замыкания без реальной сети/файлов),
`ProviderDescriptorTests.swift`.

### 7. Поведение без CLI/credentials

Два разных случая, не путать:

- **Нет способа узнать, залогинен ли пользователь, без сети/подпроцесса**
  (обычный кейс) — провайдер регистрируется всегда, `fetchStatus()` при
  ошибке чтения/сети возвращает `NewProviderStatus` с `loggedIn: false` и
  понятным `providerError` (строка вида `"<источник> read failed: ..."`,
  через `friendly(error)`); попап показывает эту ошибку как секцию с
  ошибкой, не крашится и не показывает «Loading…» вечно.
- **Есть дешёвая синхронная проверка наличия credentials** (файл на диске,
  как у Kimi) — сделай её и вызови **до** добавления провайдера в
  `ProviderRegistry.makeDefault()`, чтобы провайдер без рабочих credentials
  не показывался в реестре вообще, а не висел с постоянной ошибкой
  логина. Это не должно требовать сети или подпроцессов — только чтение
  локального файла/несложный парсинг.

Выбирай между двумя вариантами по стоимости проверки: если "залогинен ли
пользователь" нельзя понять быстро и без сети — используй первый вариант
(секция с ошибкой); если можно — второй (скрыть из реестра) даёт менее
шумный UI.
