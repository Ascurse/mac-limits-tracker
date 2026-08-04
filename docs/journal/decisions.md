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

## 2026-08-04 — Действие «открыть провайдера» названо словом, пока помещается (bd mac-limits-tracker-avs)

**Контекст:** System и Terminal показывали открытие CLI одной иконкой `arrow.up.forward.app` в borderless-кнопке — она читалась как украшение заголовка, и смысл появлялся только при наведении. Phosphor и TUI при этом писали `[open]` текстом.
**Решение:** общий `ProviderOpenButton` на `ViewThatFits`: помещается — иконка плюс подпись `LoginHelp.actionTitle`, не помещается — только иконка. Подсказка и метка VoiceOver в обеих ветках одинаковые; `LoginHelp.accessibilityLabel(providerTitle:)` в Core — единственный источник этой метки для всех четырёх тем.
**Почему:** сама подпись — тот же приём, что и в `CompactKeyValueRow`: ширину меряет layout, а не подобранный лимит символов. Постоянную подпись отвергли — она конкурирует за ширину в узком попапе, ровно то, что чинил bd mac-limits-tracker-6ke; bordered-стиль кнопки отвергли — он делает иконку кнопкой, но не объясняет действие.
**Последствия:** видимый текст и озвучка расходятся только в оформлении (`[open]` у моноширинных тем против `Open`), слово одно. Расположение и ширину подписи `swift test` не проверяет — код view в executable-таргете; гейтом покрыты только строки в Core (`ProviderActionLabelTests`).

## 2026-08-04 — Severity в монохромной теме: текстура полосы плюс маркер (bd mac-limits-tracker-r7h)

**Контекст:** Phosphor выделял только критичное состояние (инверсия плашки), а normal и warning отличались лишь восклицательным знаком перед значением — на зелёном CRT приближение к порогу терялось.
**Решение:** каждое состояние несёт два нецветовых признака. Текстура полосы `AsciiBar` идёт рядом «сплошное → плотное → разреженное» (`█`/`▓`/`▒`), маркер `Severity.asciiMarker` — «пусто/`!`/`!!`»; инверсия критичного сохранена как третий признак. Доля заполнения от severity не зависит.
**Почему:** признаки живут в Core и проверяются `SeverityAsciiCueTests` (три состояния — три различимых вида), а не держатся на глаз в теле view. Инверсию не трогали: она уже работала и её потеря была бы регрессией.
**Последствия:** `Severity.accessibilityLabel` заменил приватный `severityLabel` в теме — ярлык VoiceOver и визуальный контракт меняются вместе. Terminal и TUI остались на цветовом различении: там палитра цветная.

## 2026-08-04 — Палитры тем переехали в Core под гейт контраста (bd mac-limits-tracker-be5)

**Контекст:** аудит заявлял провал контраста тусклого текста (Terminal 2.76:1, Phosphor 1.96:1, TUI 3.10:1), но проверить это было нечем: цвета были литералами `Color(hex:)` в executable-таргете, недоступном тестам. Пересчёт по WCAG показал, что заявленные числа не воспроизводятся — все текстовые токены уже проходили AA (5.66–12.72:1). Проваливалось другое: подложка полосы Terminal 1.38:1, рамка панели TUI 1.83:1 и любой токен в stale-секции, которую `.opacity(0.55)` смешивала с фоном (хуже всех Phosphor mid — 2.39:1).
**Решение:** hex-значения переехали в `Core/Models/ThemePalette.swift`, UI-энумы стали обёртками `hex → Color`; рядом легли `WcagContrast` и `StaleAppearance.opacity`. `ThemePaletteContrastTests` держит пороги 4.5:1 для текста и 3:1 для нетекстовых элементов и stale-состояния. Правки: `Terminal.track` 0x2F334D → 0x5C6497, `Tui.border` 0x3A4150 → 0x566177, stale-прозрачность 0.55 → 0.7.
**Почему:** аудит по скриншотам даёт числа, которые никто не может перепроверить; число в Core перепроверяет тест на каждом прогоне. Полосу и рамку подняли по минимуму до порога (3.0–3.03:1), чтобы не ломать вид тем. Stale чинили прозрачностью, а не осветлением зелёного Phosphor: 0.55 роняла все темы разом, а stale-секция несёт реальные данные и отдельно помечена строкой ошибки, так что 0.7 остаётся различимым приглушением.
**Последствия:** новый цвет темы заводится в `ThemePalette`, иначе он не попадает в гейт. `StaleAppearance.opacity` — единственный источник stale-приглушения для попапа и виджета. Заявленные аудитом числа контраста тусклого текста считать недостоверными.

## 2026-07-31 — Ad-hoc zip как временный релиз вместо запрета публикации (bd mac-limits-tracker-l3n, l3n.1) [пересматривает: 2026-07-29 «Распространение без Developer ID»]

**Контекст:** запись от 2026-07-29 и README расходились: журнал уже допускал `.zip` в GitHub Releases «с честным предупреждением про Gatekeeper», а README прямо запрещал публиковать `v*`-тег или ad-hoc zip как релиз. К моменту этой записи fallback в `.github/workflows/release.yml` (bd mac-limits-tracker-l3n.1) уже реализован и README нужно было привести в соответствие.
**Решение:** пайплайн публикует GitHub Release по каждому `v*`-тегу: если все три секрета Developer ID (`MACOS_CERT_P12_BASE64`/`MACOS_CERT_PASSWORD`/`DEVELOPER_ID_APPLICATION`) отсутствуют — собирает `dist/MacLimitsTracker.zip` из ad-hoc-подписанного бандла (подпись линкера, `make-app.sh`) и публикует его с заметкой о предупреждении Gatekeeper и инструкцией обхода (`xattr -cr` или правый клик → «Открыть»). Частичный набор секретов остаётся fail-closed как ошибка конфигурации. При полном наборе секретов путь signed+notarized применяется как и раньше, без изменений в приоритете.
**Почему:** запрет в README держал репозиторий в противоречивом состоянии — конвейер уже умел безопасно публиковать неподписанный артефакт с честным предупреждением, а документация утверждала обратное. Публикация ad-hoc zip с явным предупреждением не хуже статус-кво (сборка из исходников), но снимает трение для пользователей, которые всё равно готовы обойти Gatekeeper.
**Последствия:** README (`Install`, `Signed and notarized release`) больше не запрещает `v*`-теги и ad-hoc zip — описывает оба пути и их автоматический выбор по наличию секретов. Публикация в Homebrew (cask/formula) по-прежнему отложена до нотаризации — это решение её не затрагивает.

## 2026-07-30 — Hybrid desktop architecture: один state owner, четыре surfaces, два launch mode

**Контекст:** Приложение выросло из `MenuBarExtra` в полноценный macOS-клиент с singleton desktop window, нативными Settings и отдельным desktop widget. Независимые модели, таймеры и правила форматирования на каждой поверхности приводили бы к гонкам refresh, рассинхрону настроек и разному отображению одного снапшота.
**Решение:** [MacLimitsTrackerApp](../../Sources/MacLimitsTracker/App/MacLimitsTrackerApp.swift) создаёт один `LimitsViewModel` и один `LaunchAtLoginManager` на весь процесс. Menu-bar popup и [DesktopWindowView](../../Sources/MacLimitsTracker/UI/DesktopWindowView.swift) используют общий `ProviderOverview`; popup, desktop disclosure и [SettingsRootView](../../Sources/MacLimitsTracker/UI/Settings/SettingsRootView.swift) компонуют те же settings-секции. [DesktopWidgetController](../../Sources/MacLimitsTracker/UI/DesktopWidgetController.swift) остаётся отдельной AppKit-оболочкой над shared state, потому что ему нужен non-activating `NSPanel` на desktop level.
**Почему:** один state owner сохраняет refresh/history/settings при открытии и закрытии сцен; нативные `Window`/`Settings` дают системный lifecycle без собственных `NSWindowController`. `WindowPresentationController` централизует activation policy и не позволяет окнам независимо передёргивать Dock/Cmd-Tab.
**Последствия:** `swift run` использует `.hybrid`: стартует `.accessory`, становится `.regular`, пока открыт main window или Settings, и возвращается в `.accessory` после закрытия последнего окна. Bundled `.app` использует `.persistentRegular` и остаётся `.regular`; `MenuBarExtra` и widget при этом не исчезают. Новое активирующее окно обязано регистрировать своё состояние в [WindowPresentationController](../../Sources/MacLimitsTrackerCore/App/WindowPresentationController.swift), а новая popup/desktop-поверхность — переиспользовать shared state и существующие rendering/settings components.
## 2026-07-29 — Распространение без Developer ID: сборка из исходников, не Homebrew [пересмотрено: 2026-07-31, см. выше]

**Контекст:** Релизный конвейер подписи готов, но требует платного членства в Apple Developer Program и сертификата Developer ID. Проверяли, есть ли способ раздавать `.app` без членства — в частности через Homebrew.
**Решение:** Homebrew обходом не считаем и cask не заводим. До появления сертификата основной путь распространения — сборка из исходников (`./make-app.sh`); конвейер подписи остаётся в репозитории нетронутым и включается без правок, как только сертификат появится.
**Почему:** Homebrew по умолчанию сам вешает атрибут карантина, флаг `--no-quarantine` удаляется, и с 2026-09-01 cask, не проходящие проверку Gatekeeper, не поддерживаются ([Homebrew/brew#20755](https://github.com/Homebrew/brew/issues/20755)) — то есть через cask неподписанное приложение раздать нельзя в принципе. Локально скомпилированный бинарник карантин не получает вообще (его ставит скачивающая программа), поэтому сборка из исходников работает без подписи, а требование Apple Silicon закрывается автоматической ad-hoc-подписью компоновщика. Дополнительный довод за подпись в будущем: приложение читает файлы с учётными данными (`~/.claude`, `~/.codex`, `~/.kimi-code`), и для стороннего пользователя это вопрос доверия, а не только удобства установки.
**Последствия:** Пользовательская документация описывает сборку из исходников как основной способ установки; готовый `.zip` в GitHub Releases остаётся, но с честным предупреждением про Gatekeeper. Публикация в Homebrew (cask или formula) откладывается до нотаризации и отдельной задачей сейчас не ведётся.

## 2026-07-29 — Релизный pipeline: подпись Developer ID, notarization, staple, fail-closed

**Контекст:** Релизы собирались ad-hoc, подпись менялась каждую пересборку, macOS переспрашивал доступ к Keychain `Claude Code-credentials`, а Gatekeeper блокировал скачанное приложение. Нужен pipeline, при котором неподписанный артефакт никогда не публикуется.
**Решение:** [scripts/release/sign-and-notarize.sh](../../scripts/release/sign-and-notarize.sh) работает fail-closed: preflight проверяет инструменты, бандл, `DEVELOPER_ID_APPLICATION` и notary-авторизацию, и при любой проблеме падает до мутации артефактов. Подпись корня бандла без `--deep`, hardened runtime через `--options runtime` без entitlements-файла; sandbox отключён. Notary-zip используется только для отправки и отбрасывается; release-zip собирается уже после `stapler staple` из .app. Приоритет авторизации: API key (`NOTARY_KEY`/`NOTARY_KEY_ID`/`NOTARY_ISSUER`) для CI, `NOTARY_PROFILE` локально, тройка Apple ID — fallback.
**Почему:** Ad-hoc-подпись нестабильна, поэтому ACL-промпт возвращается после каждой чистой пересборки; стабильная Developer ID-подпись позволяет пользователю нажать «Always Allow» один раз на сборку. `keychain-access-groups` не дают доступ к чужому элементу `Claude Code-credentials`, вопрос решается не entitlements, а стабильной подписью. Sandbox запрещён, потому что приложение читает `~/.claude`, `~/.codex`, `~/.kimi-code` и запускает subprocesses; entitlements не нужны, так как hardened runtime — это флаг, а не entitlement. `--deep` избыточен, потому что в бандле нет вложенного кода, а zip до stapling не содержал бы notarization ticket.
**Последствия:** [.github/workflows/release.yml](../../.github/workflows/release.yml) импортирует сертификат во временный keychain, проходит gate `swift test` и запускает скрипт, публикуя только stapled-артефакт. Локальный ad-hoc bundle не считается релизом; production zip появляется только после успешных Developer ID signing, notarization, staple и Gatekeeper assessment.

## 2026-07-26 — HistoryStore: первая JSON-персистентность на диске + sparkline за 24ч (bd mac-limits-tracker-08m, gh #31)

**Контекст:** каждый refresh перезаписывал снапшот, история нигде не сохранялась — невозможны ни графики, ни burn-rate прогноз (gvo), ни экспорт (dti). До этого все сторы проекта жили на UserDefaults.
**Решение:** `HistoryStore` (Core, `Storage/`) — плоский `history.json` (`{version: 1, samples: [UsageSample{providerId, windowMins, fetchedAt, usedPercent, resetsAt}]}`) в `~/Library/Application Support/dev.ascurse.MacLimitsTracker/`, ретенция 7 дней (прунинг при append), дедуп подряд идущих одинаковых значений **по ключу (providerId, windowMins)** — сдвиг `fetchedAt` вместо новой строки (без этого ночные плато раздувают файл; поиск именно по ключу, а не по `samples.last`, т.к. append'ы окон чередуются внутри одного refresh). Записываются только окна с реальными данными (nil `usedPercent`/ошибки снапшота — пропуск). Запись — в `refresh()` после `self.states = ...`. В попапе новый `PopupRow.sparkline(SparklineContent)` после каждой window-строки с данными за 24ч: System — Swift Charts (`LineMark`+`PointMark`, без PointMark одиночная точка не рисуется), Terminal/Phosphor/TUI — `AsciiSparkline` (`▁▂▃▄▅▆▇█`, бакет-максимум при даунсемпле) в Core рядом с `AsciiBar`/`TuiGauge`. Идентичность окна — `windowMins`, никогда не индекс.
**Почему:** плоский массив сэмплов проще в append/прунинге/будущем CSV-экспорте, чем вложенная по провайдерам структура; 7 дней покрывают полный цикл weekly-окна для будущего прогноза; `resetsAt` в сэмпле позволит детектить ролловер окна; дедуп по ключу — единственный вариант, работающий при многооконных провайдерах.
**Последствия:** новый кейс `PopupRow` обрабатывается во всех 4 темах (exhaustive switch — compile-enforced); Desktop widget спарклайнов не имеет (не читает `PopupRow`). `PopupContentBuilder.section` получил параметр `history: [UsageSample] = []` — старые вызовы компилируются без изменений. **Все конструкции `LimitsViewModel` в тестах обязаны инжектить изолированный `HistoryStore(directory:)`** — дефолт пишет в реальный Application Support (поймано на поллюции history.json тестовыми сэмплами).

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
