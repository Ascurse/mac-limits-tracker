# Decisions — журнал ключевых решений

Lightweight ADR: архитектурные и технические решения, которые иначе придётся объяснять заново каждому новому человеку и агенту. Сюда — *почему* выбрано так, а не *что* в коде (это видно из кода).

Формат записи:

```
## YYYY-MM-DD — Краткий заголовок

**Контекст:** что было до / какая проблема.
**Решение:** что приняли.
**Почему:** обоснование, отвергнутые альтернативы.
**Последствия:** что меняется для всех / что теперь устарело.
```

**Только суть.** Каждое поле — 1–4 предложения, финальный вывод и обоснование — не хроника по фазам/веткам/бидам. Если решение принималось поэтапно — в журнал идёт итоговое состояние, а не пересказ каждого шага.

Самые свежие — сверху. Если решение пересмотрено, а запись всё ещё короткая — **не удаляем**, помечаем `[пересмотрено: YYYY-MM-DD, см. <ссылка>]`. Если решение полностью отменено/заменено и запись больше не нужна для навигации — перенеси в `decisions-archive.md` с меткой `[снято: YYYY-MM-DD]`; это файл для аудита людьми, агент его не читает.

---

## 2026-07-25 — Stale-данные при сетевой ошибке: resolver в Core, menu bar не мигрирован (bd mac-limits-tracker-1og)

**Контекст:** сетевая ошибка заменяла данные провайдера красной ошибкой — попап «слеп», хотя данные минутной давности достаточны.
**Решение:** чистый `SnapshotResolver.resolve(ProviderState) -> ResolvedDisplay {snapshot, isStale, error}` — единая точка правил stale: last-good хранится в `ProviderState.lastGoodSnapshot` + backup-словарь `lastGoodSnapshots` в ViewModel (переживает disable/enable, т.к. state удаляется из `states`); попап/виджет/тултип/`updatedText` читают resolved-снапшот, при stale — приглушение `.opacity(0.55)`, `.note("updated … ago")` и мелкая `.error` внизу секции. **Сознательно НЕ мигрированы** `statusTitle`/`MenuBarDisplayMode.menuBarText` (ревью N2): во время аварии меню-бар показывает «Short: ?» / «—» как сигнал проблемы (наряду с иконкой-треугольником), а тултип — last-known значения; это расхождение intended, не баг. `rateLimitReachedType` в stale-мерже зануляется — иначе старый «rate limit reached» выглядит свежей ошибкой.
**Почему:** resolver в Core держит темы тонкими (новых кейсов `PopupRow` нет); backup-словарь добавлен после опровержения допущения плана, что `existingById` переживает disable/enable (см. gotcha 2026-07-25).
**Последствия:** `NotificationEvaluator` читает сырые снапшоты — error-снапшот без окон пропускается, baseline уведомлений переживает аварию (пин-тест `test_errorSnapshot_skippedAndBaselinePreserved`); если evaluator когда-либо переведут на resolved — этот пин сломается первым. Осознанный риск: `isGood` не требует `windows != nil`, поэтому «хороший» снапшот без окон (Kimi с пустым `limits[]`, Codex с двумя nil-окнами) даунгрейдит lastGood — редко, самолечится следующим удачным fetch.

## 2026-07-25 — Kimi: авто-refresh access_token (bd mac-limits-tracker-8kz)

**Контекст:** access_token Kimi живёт ~15 минут, CLI не обновляет его в фоне, и вне свежего окна попап показывал «Kimi login expired».
**Решение:** отдельный `KimiTokenRefresher` (DI-клоужуры, как у провайдера): pre-race перечитывание файла до refresh и повторное после `invalid_grant` (гонка ротации с CLI по образцу PR MoonshotAI/kimi-cli#1996, без lockfile); fail-fast без retry — приложение перезапросит на следующем тике; атомарная запись через temp-файл с `posixPermissions` 0600 до `replaceItemAt` + merge поверх сырого JSON-словаря (сохраняет неизвестные поля CLI); в `KimiLimitsProvider` новый DI-параметр `refresh`; 401 от usages при локально свежем токене → один refresh + один retry; `Http.httpPostForm` возвращает `(statusCode, body)` вместо throw на non-2xx, т.к. `invalid_grant` кодируется в теле.
**Почему:** reverse-engineered endpoint (`POST https://auth.kimi.com/api/oauth/token`) и паттерн PR #1996 проще и надёжнее, чем внедрение lockfile CLI; merge словаря сохраняет обратную совместимость с форматом, который контролирует сторонний CLI.
**Последствия:** init `KimiLimitsProvider` стал `internal` (параметр ссылается на internal `KimiCredentialsFile`); существующий тест `test_fetch_expiresAtInPast_httpGetNeverCalled` переведён на refresh-стаб; новые файлы `Providers/KimiTokenRefresher.swift` и тесты `KimiTokenRefresherTests` (8 шт.).

## 2026-07-24 — Динамическая регистрация провайдеров через DynamicProviderSpec (gh #27)

**Контекст:** состав реестра фиксировался в `ProviderRegistry.makeDefault()` при старте: залогинился в Kimi Code после запуска приложения — провайдер появлялся только после перезапуска.
**Решение:** `LimitsViewModel` принимает `dynamicProviders: [DynamicProviderSpec]` (`id` + `isAvailable` + `makeProvider`, замыкания инжектируются — в тестах стабы) и сверяет доступность синхронно в начале `refresh()` (`reconcileDynamicProviders`): добавляет/убирает провайдера по id, перечитывает настройки через `settingsStore.settings(for:)`, но **не сохраняет** их. Приложение передаёт `[.kimi]`; статический `makeDefault()` оставлен как есть — спек дедуплицирует по id, двойной регистрации нет. [дополнено: 2026-07-25] `providerSettings` ведётся по union `реестр ∪ id спек` (в init и reconcile): `save` пишет порядок/выключенность целиком, и без записи отсутствующего провайдера любое изменение настроек пользователем стирало бы его persisted-запись до возвращения (найдено на ревью). UI настроек читает только join с присутствующими (`providerSettingsWithDescriptors`), поэтому запись отсутствующего провайдера в `providerSettings` не видна снаружи.
**Почему:** reconcile до порождения fetch-Task + отмена предыдущего Task в `refresh()` даёт ту же защиту от гонки, что и `applyProviderSettingsChange` — устаревшая задача не запишет states после смены состава. Без save persisted-запись (порядок, выключенность) переживает цикл «пропал → появился».
**Последствия:** VerifyCli и тесты конструируют VM без spec (дефолт `[]`) — статический путь не изменился; watcher на файловую систему не заводили, перепроверка раз в refresh достаточна.

## 2026-07-24 — «Launch at login»: система — источник истины, без своей персистентности (gh #33)

**Контекст:** запуск при входе предлагался только ручной настройкой в System Settings → Login Items.
**Решение:** `LaunchAtLoginManager` (app-таргет) над `SMAppService.mainApp`: тоггл читает `status` (.requiresApproval считается включённым), перечитывает его при каждом открытии попапа, register/unregister без своего флага в UserDefaults; без бандла — no-op по паттерну `NotificationManager` (`Bundle.main.bundleIdentifier != nil`).
**Почему:** пользователь может менять login item в System Settings параллельно — свой persisted-флаг неизбежно рассинхронизировался бы; `SMAppService` уже персистит состояние в системе.
**Последствия:** юнит-тестов нет (системная граница, Tests-таргет видит только Core) — верификация сборкой и живым тогглом в бандле.

## 2026-07-24 — AppSettingsStore: единая точка настроек приложения

**Контекст:** интервал автообновления был зашит в `LimitsViewModel` (`TimeInterval = 300`), пороги severity — в `PopupContent` (15/40), настройки уведомлений отсутствовали; часть настроек жила в `@AppStorage` (view-уровень), часть — в `ProviderSettingsStore` (gh #24/#25/#29).
**Решение:** завели `AppSettingsStore` (Core, инжектируемый UserDefaults, ключи `autoRefreshInterval` / `severityThresholds.*` / `notificationsEnabled` в `.standard` рядом с @AppStorage-ключами). `LimitsViewModel` публикует `@Published`-проекции + сеттеры-персистеры; чистые функции (`PopupContentBuilder.section`, `Severity.from`, `NotificationEvaluator`) получают пороги параметром с дефолтом `.standard` — UserDefaults внутрь чистой логики не протягиваем.
**Почему:** повторяет проверенный паттерн `ProviderSettingsStore`; `NotificationManager` и ViewModel читают одни настройки, не владея друг другом; persisted-значения тестируются изолированно через `UserDefaults(suiteName:)`.
**Последствия:** `autoRefreshInterval` — enum `RefreshInterval`, а не `TimeInterval`; пороги severity настраиваемые (`SeverityThresholds`, инвариант critical < warning прижимается в init); уведомления вычисляет чистый `NotificationEvaluator` (dedup crossing по ухудшению зоны, re-arm после восстановления, ресет окна — по смене `resetsAt`, первое наблюдение окна за порогом = crossing из normal), доставка — `NotificationManager` в app-таргете (no-op без бандла, т.е. под `swift run`).

## 2026-07-23 — Kimi: реальный usage из `/coding/v1/usages`, план из membership вместо JWT

**Контекст:** Kimi был "тонким" провайдером без usage-данных (bd mac-limits-tracker-6gk.3). Живая разведка подтвердила `GET https://api.kimi.com/coding/v1/usages`: `limits[]` с окнами по `window.duration`/`timeUnit`, верхнеуровневый `usage` (limit/used/remaining) без указания периода, `user.membership.level` вместо plan-claim в JWT (которого в реальном токене нет).
**Решение:** `limits[]` → `SnapshotWindow[]` (длительность в минутах через multiplier по `timeUnit`: MINUTE×1/HOUR×60/DAY×1440); верхнеуровневый `usage` → `SnapshotDetail("Quota", "44 / 100 used · resets 27 Jul")`, а не окно — не хардкодим `windowDurationMins: 10080`, т.к. `subType: TYPE_PURCHASE` означает покупной пул без календарного периода. Plan = `prettify(membership.level)` (срезать `LEVEL_` префикс, Title Case) с fallback на старый JWT plan-claim (`KimiJwtPayloadParser.planClaim`, не удалён).
**Почему:** придумывать длительность для пула без периода — вводить в заблуждение (ложный "Weekly"-ярлык); UI различает "нет слота" (nil) и "слот без данных" уже для других провайдеров, деталь передаёт ту же информацию честно. `membership.level` — единственный live-источник плана, JWT claim в текущих токенах отсутствует, но оставлен как fallback на случай других сценариев авторизации.
**Последствия:** `KimiStatus.usage: KimiUsage?` (windows + quota), `KimiUsagesParser`/`KimiUsagesResponseJSON`/`KimiMembershipLevelFormatter` в `KimiModels.swift`. `Http.httpGet` получил параметр `userAgent` (дефолт сохраняет прежнее поведение Claude) — Kimi шлёт нейтральный `mac-limits-tracker/1.0` вместо `claude-code/...`. 401/протухший `expiresAt` → `usageError` "Kimi login expired…", `loggedIn` остаётся `true` (есть refresh_token).

## 2026-07-23 — Общий JwtPayloadDecoder: 2 сегмента вместо строгих 3

**Контекст:** декод base64url payload JWT дублировался в `KimiJwtPayloadParser` (≥2 сегмента, токен без подписи тоже валиден) и `ChatGPTClaims.payload` (строго 3 сегмента).
**Решение:** вынесли общий `JwtPayloadDecoder` (`Models/JwtPayloadDecoding.swift`) с более мягкой проверкой Kimi (`segments.count >= 2`) — Codex теперь тоже принимает 2-сегментный токен без подписи.
**Почему:** это правило корректнее по спеке JWT (unsecured JWT с `alg: none` легитимно имеет 2 сегмента); ни один из существующих характеризационных тестов Codex/Kimi не проверяет отказ именно на 2-сегментном токене, так что поведение не регрессирует.
**Последствия:** `ChatGPTClaims.payload(of:)` и `KimiJwtPayloadParser.planClaim(fromToken:)` — тонкие обёртки над `JwtPayloadDecoder.decode(token:)`.

## 2026-07-23 — Заведена общая память проекта (docs/journal/)

**Контекст:** не было единого источника для AI-ассистентов и общей технической памяти; знание жило в разрозненных bd remember и головах.
**Решение:** добавили `docs/journal/` (decisions/gotchas/glossary) как общую память + конвенции чтения/записи в `AGENTS.md`.
**Почему:** агент не помнит прошлые сессии; знание, не выводимое из кода, должно жить в одном закоммиченном месте, читаемом всеми инструментами (Claude/Codex/Cursor).
**Последствия:** все агенты читают `AGENTS.md` и `docs/journal/` перед нетривиальной задачей и грепают журнал перед правкой файла.
