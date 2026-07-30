# Gotchas — подводные камни

Сюда — то, что один раз уже стоило времени и не должно стоить второй раз. Особенно ценно для агента: то, что **не видно из кода** (зелёный build/тесты при сломанном рантайме, ограничения внешних API, неочевидные взаимодействия версий).

Формат:

```
## YYYY-MM-DD — Краткий заголовок

**Симптом:** как это проявляется.
**Причина:** что на самом деле происходит.
**Обход:** что делать.
**Где это в коде:** ссылки на файлы.
```

**«Где это в коде» обязательно** — это обратный индекс `файл → грабли по нему`. Перед правкой файла `X` агент делает `grep -rn "X" docs/journal/decisions.md docs/journal/gotchas.md docs/journal/glossary.md` и находит релевантную запись.

**Только суть.** Каждое поле — 1–3 предложения. Не хроника работы: без номеров веток/бидов, без пошагового пересказа отладки, без метрик «для истории» — только симптом/причина/обход и ссылка на код.

Самые свежие — сверху. Если запись частично устарела — аннотируй `[пересмотрено: YYYY-MM-DD]`; если устарела целиком (обход больше не нужен) — **удали** запись, если она не объясняет полезный контекст (почему был нужен костыль), иначе перенеси в `gotchas-archive.md` с меткой `[снято: YYYY-MM-DD]`. Указатель в активном файле не обязателен: `gotchas-archive.md` — это память для аудита людьми, агент её не читает и не грепает.

---

## 2026-07-30 — `SMAppService.requiresApproval` означает «зарегистрировано, но ждёт пользователя»

**Симптом:** Тоггл «Launch at login» включён, но приложение не запускается после входа в систему.

**Причина:** `SMAppService.mainApp.register()` может вернуть системный статус `.requiresApproval`: login item уже зарегистрирован, но macOS не активирует его до подтверждения в System Settings.

**Обход:** Считать `.requiresApproval` включённым состоянием тоггла и направлять пользователя в **System Settings → General → Login Items** для подтверждения; не хранить параллельный boolean в `UserDefaults`.

**Где это в коде:** [Sources/MacLimitsTracker/App/LaunchAtLoginManager.swift](../../Sources/MacLimitsTracker/App/LaunchAtLoginManager.swift) (`syncStatus`, системный source of truth).

## 2026-07-29 — Ad-hoc-пересборка возвращает keychain ACL-промпт; Developer ID стабилизирует доступ

**Симптом:** После каждой чистой пересборки `dist/MacLimitsTracker.app` снова появляется системный диалог с просьбой разрешить доступ к записи Keychain `Claude Code-credentials`, хотя пользователь уже нажимал «Always Allow» на предыдущем билде.

**Причина:** Ad-hoc-подпись меняется при каждой сборке, поэтому macOS считает каждый билд новым приложением и не применяет старое ACL-правило. Developer ID-подпись остаётся стабильной в рамках одного identity, поэтому «Always Allow» работает на всю сборку.

**Обход:** Для доверенной локальной ad-hoc-сборки нажимать «Always Allow» после каждой смены подписи; дистрибутив собирать через `scripts/release/sign-and-notarize.sh` со стабильной Developer ID identity.

**Где это в коде:** [make-app.sh](../../make-app.sh) (ad-hoc bundle), [scripts/release/sign-and-notarize.sh](../../scripts/release/sign-and-notarize.sh) (`sign_app`, выбор `IDENTITY`), [Sources/MacLimitsTrackerCore/Models/ClaudeModels.swift](../../Sources/MacLimitsTrackerCore/Models/ClaudeModels.swift) (`ClaudeKeychainCredentialsParser`).

## 2026-07-29 — Release-zip должен собираться после stapling, иначе ticket не попадёт в артефакт

**Симптом:** Пользователь скачивает релизный zip, Gatekeeper при офлайн-проверке не находит notarization ticket и либо падает на online-проверку, либо блокирует запуск без сети.

**Причина:** `stapler staple` прикрепляет ticket к .app внутри бандла, а не к zip. Если zip создать до stapling, внутри него окажется непрошитый .app.

**Обход:** Сначала подписать и верифицировать .app, отправить на notarization, дождаться Accepted, выполнить `stapler staple`, затем уже собирать `MacLimitsTracker.zip` для публикации. Notary-zip используется только для загрузки и отбрасывается.

**Где это в коде:** [scripts/release/sign-and-notarize.sh](../../scripts/release/sign-and-notarize.sh) (порядок `notarize_app` → `staple_app` → `release_zip`).

## 2026-07-29 — AX-автоматизация MenuBarExtra-popup'а нестабильна: toggle-клик, гонки `entire contents`, порядок окон

**Симптом:** при GUI-QA через `osascript` System Events клик по `menu bar item 1 of menu bar 2` то открывает, то закрывает popup; `entire contents of window 1` периодически возвращает пустое или частичное дерево (0 кнопок при живом popup); при открытом main window поиск кнопок popup'а в `window 1` падает, хотя popup на экране.
**Причина:** клик по menu bar item — toggle (open/close), а не «открыть»; AX-дерево SwiftUI внутри `MenuBarExtra(.window)` материализуется асинхронно после появления окна; AX-окна упорядочены front-to-back, поэтому `window 1` — это то, что сейчас key (при открытом «Limits Tracker» — main window, а не popup).
**Обход:** открытие — цикл «клик → poll до появления окна с subrole `AXSystemDialog`, до 3 попыток»; искать элементы по всем окнам с фильтром `subrole = AXSystemDialog`, а не в `window 1`; кнопки находить по `help`-атрибуту (AX `name` у SwiftUI-кнопок в popup пуст — текст лежит в дочерних `AXStaticText`); поиск — retry до ~4 с; скриншоты делать без кражи фокуса другим приложением — popup гаснет при потере key (это же и есть механизм его авто-дисмисса при открытии main/Settings окна).
**Где это в коде:** [Sources/MacLimitsTracker/UI/StatusBarView.swift](../../Sources/MacLimitsTracker/UI/StatusBarView.swift) (контент `MenuBarExtra(.window)`), [scripts/qa/lib/ax.sh](../../scripts/qa/lib/ax.sh) (поиск popup и retry), [scripts/qa/scenarios/](../../scripts/qa/scenarios/) (surface-сценарии).

## 2026-07-28 — `UserDefaults.bool(forKey:)` молча возвращает `false` для отсутствующего ключа (bd mac-limits-tracker-3ip.3)

**Симптом:** новый `AppSettingsStore.autoRefreshEnabled` читается как `false` после первого запуска (когда ключа ещё нет в defaults), тоггл «Auto-refresh» в UI показывает выключенное состояние, хотя по дизайну default = `true`.
**Причина:** `defaults.bool(forKey:)` для отсутствующего ключа возвращает `false` — отличить «не записано» от «записано false» через этот API нельзя. Для `notificationsEnabled` (default false) это незаметно; для `autoRefreshEnabled` (default true) — ломает контракт.
**Обход:** для bool-ключей с default `true` использовать `defaults.object(forKey:) as? Bool ?? true` — `object(forKey:)` возвращает `nil` для отсутствующего ключа, что позволяет применить default; для `false`-default ключей по-прежнему достаточно `bool(forKey:)`. Тот же приём уже применён в этом же файле для `severityThresholds` (для `Double`).
**Где это в коде:** [Sources/MacLimitsTrackerCore/Providers/AppSettingsStore.swift](../../Sources/MacLimitsTrackerCore/Providers/AppSettingsStore.swift) (`autoRefreshEnabled` getter с object-forKey; рядом `severityThresholds` для справки).

## 2026-07-28 — `@Published`-подписка в `init` срабатывает раньше, чем `App.task` (bd mac-limits-tracker-3ip.3)

**Симптом:** `DesktopWidgetController` после миграции на `vm.$showDesktopWidget.sink { setVisible($0) }` показывал NSPanel во время `MacLimitsTrackerApp.init` (до того, как `AppDelegate.applicationDidFinishLaunching` мог что-либо применить), либо применял состояние дважды — `sink` от первого `$showDesktopWidget` replay + явный `App.task` setVisible.
**Причина:** `@Published` через `Publisher` эмитит текущее значение новому подписчику немедленно (в `init`-объекта, если sink создан в init). `App.init` отрабатывает до того, как NSApp готов, и до того, как пользовательский flow допускает показ панели.
**Обход:** подписка с `.dropFirst()` — пропускает initial replay, реагирует только на последующие изменения из любой поверхности. Начальное состояние по-прежнему применяет `App.task` (`desktopWidgetController.setVisible(viewModel.showDesktopWidget)`), чтобы тайминг показа был управляемым (после старта сцены, а не во время init).
**Где это в коде:** [Sources/MacLimitsTracker/UI/DesktopWidgetController.swift](../../Sources/MacLimitsTracker/UI/DesktopWidgetController.swift) (init, `.dropFirst()` + `cancellables`), [Sources/MacLimitsTracker/App/MacLimitsTrackerApp.swift](../../Sources/MacLimitsTracker/App/MacLimitsTrackerApp.swift) (label `.task` — начальное применение).

## 2026-07-28 — `NSApp` is nil в `MacLimitsTrackerApp.init` (bd mac-limits-tracker-3ip.4)

**Симптом:** свежесобранный бандл крашится на старте с `Swift runtime failure: Unexpectedly found nil while implicitly unwrapping an Optional value` в `MacLimitsTrackerApp.init` → `WindowPresentationController.ensureAccessoryOnLaunch()` → `NSApp.setActivationPolicy(.accessory)`. Падение видно в `~/Library/Logs/DiagnosticReports/MacLimitsTracker-*.ips`, в `lldb --batch` — `frame #1: closure #1 in MacLimitsTrackerApp.init`.
**Причина:** SwiftUI `App.init()` отрабатывает до того, как `NSApplication.shared` создан и привязан к процессу — `NSApp` (force-unwrapped) в этот момент nil. Контроллер активации (`WindowPresentationController`) принимает closure с `NSApp.setActivationPolicy(...)`, и если кто-то вызывает `ensureAccessoryOnLaunch()` из init — closure тут же падает.
**Обход:** создавать контроллер и всю AppKit-зависимую логику в init без вызова методов, которые дёргают `NSApp`; первое касание — `AppDelegate.applicationDidFinishLaunching`, где `NSApp` гарантированно не-nil. Сам контроллер — в Core, без `import AppKit` (closure-замыкание с `Int`-маркером `.accessory/.regular`); маппинг на `NSApplication.ActivationPolicy` — в app-таргете в одном месте, и его вызов отложен на `applicationDidFinishLaunching`.
**Где это в коде:** [Sources/MacLimitsTracker/App/MacLimitsTrackerApp.swift](../../Sources/MacLimitsTracker/App/MacLimitsTrackerApp.swift) (init), [Sources/MacLimitsTracker/App/AppDelegate.swift](../../Sources/MacLimitsTracker/App/AppDelegate.swift) (`applicationDidFinishLaunching`), [Sources/MacLimitsTrackerCore/App/WindowPresentationController.swift](../../Sources/MacLimitsTrackerCore/App/WindowPresentationController.swift).

## 2026-07-26 — `LimitsViewModel` в тестах без инжекта `historyStore` пишет в реальный Application Support

**Симптом:** после `swift test` в `~/Library/Application Support/dev.ascurse.MacLimitsTracker/history.json` появляются фейковые сэмплы от StubProvider'ов.
**Причина:** дефолтный параметр `historyStore: HistoryStore = HistoryStore()` резолвится в продакшн-путь; любой тест, конструирующий VM без этого параметра и вызывающий `refresh()` с оконным снапшотом, пишет в реальный файл.
**Обход:** в тестах всегда инжектить `HistoryStore(directory:)` на temp-dir (паттерн — `HistoryStoreTests`/`LimitsViewModelHistoryTests`); `LimitsViewModelTests` и `AppSettingsStoreTests` уже переведены.
**Где это в коде:** [Sources/MacLimitsTrackerCore/LimitsViewModel.swift](../../Sources/MacLimitsTrackerCore/LimitsViewModel.swift), [Sources/MacLimitsTrackerCore/Storage/HistoryStore.swift](../../Sources/MacLimitsTrackerCore/Storage/HistoryStore.swift).

## 2026-07-25 — `existingById` не сохраняет `lastGoodSnapshot` при disable/enable провайдера

**Симптом:** после выключения и повторного включения провайдера `ProviderState.lastGoodSnapshot` сбрасывается в `nil`, хотя `applyProviderSettingsChange`/`reconcileDynamicProviders` используют `existingById`.
**Причина:** при выключении провайдер пропадает из `states`, поэтому на следующем `existingById` для него нет записи — восстанавливается только `snapshot: nil`.
**Обход:** держать отдельный словарь `lastGoodSnapshots: [String: LimitsSnapshot]` в `LimitsViewModel`, обновлять его в `refresh()` и подставлять при создании fallback-`ProviderState`.
**Где это в коде:** [Sources/MacLimitsTrackerCore/LimitsViewModel.swift](../../Sources/MacLimitsTrackerCore/LimitsViewModel.swift).

## 2026-07-25 — Data.write atomic не задаёт права для credentials

**Симптом:** credentials-файл записывается без нужных 0600-прав, несмотря на `.atomic`, или приходится вызывать `FileManager.createFile`, а `replaceItemAt` возвращает `nil` и хочется assert-ить.
**Причина:** `Data.write(to:options:.atomic)` делает swap атомарно, но права нового файла наследуются от temp-файла с umask по умолчанию; сама API не позволяет указать `posixPermissions`.
**Обход:** для credentials создавать temp-файл через `FileManager.createFile(attributes: [.posixPermissions: 0o600])`, затем `FileManager.replaceItemAt(..., withItemAt: temp)` — его `nil`-возврат при успехе норма, не assert-ить.
**Где это в коде:** [Sources/MacLimitsTrackerCore/Providers/KimiTokenRefresher.swift](../../Sources/MacLimitsTrackerCore/Providers/KimiTokenRefresher.swift).

## 2026-07-24 — VerifyCli молча виснет после пересборки: keychain-prompt на GUI

**Симптом:** свежесобранный VerifyCli (release) не печатает ничего и не завершается; при kill часть вывода «теряется» ещё и из-за block-буферизации stdout в пайпе.
**Причина:** ad-hoc-подпись меняется при каждой пересборке → keychain ACL записи `Claude Code-credentials` не узнаёт бинарь, и `SecItemCopyMatching` блокируется в ожидании GUI-диалога разрешения (видно в `sample <pid>`: стек в `CSSM_DecryptDataFinal` → `mach_msg` к securityd). Первый провайдер в цикле — Claude, поэтому не печатается даже его заголовок.
**Обход:** разрешить диалог («Always Allow») — или учитывать при диагностике «зависаний» CLI, что это не код, а keychain-prompt на экране пользователя.
**Где это в коде:** [Sources/VerifyCli/main.swift](../../Sources/VerifyCli/main.swift), чтение keychain — `ClaudeKeychainCredentialsParser` в [Sources/MacLimitsTrackerCore/Models/ClaudeModels.swift](../../Sources/MacLimitsTrackerCore/Models/ClaudeModels.swift).

## 2026-07-24 — repeatForever-анимация в onAppear замирает в окне MenuBarExtra

**Симптом:** мигающий элемент попапа (CRT-курсор в теме Phosphor) периодически замирает после циклов открытия/закрытия окна.
**Причина:** `withAnimation(.repeatForever)` в `onAppear` рассинхронизируется с жизненным циклом вью внутри `MenuBarExtra(.window)`: окно при закрытии гасит анимацию, но при переоткрытии `onAppear` может не перевызваться — `@State` остаётся в конечном положении без работающей анимации. Воспроизведение тайминг-зависимое, синтетическими AX-кликами не ловится.
**Обход:** для looping-анимаций — `phaseAnimator` (macOS 14+): перезапуск управляется SwiftUI по появлению вью, `@State` не нужен.
**Где это в коде:** [Sources/MacLimitsTracker/UI/PhosphorStatusView.swift](../../Sources/MacLimitsTracker/UI/PhosphorStatusView.swift).

## 2026-07-24 — gh release create падает, если релиз с таким тегом уже существует

**Симптом:** Release-workflow падает на шаге публикации с «a release with the same tag name already exists», хотя сборка и zip прошли успешно.
**Причина:** `gh release create` неидемпотентен; релиз мог быть создан вручную (UI/`gh`) до пуша тега — тогда одноимённый релиз уже есть, и create завершается с exit 1.
**Обход:** шаг публикации create-or-upload: `gh release view "$GITHUB_REF_NAME"` — релиз есть → `gh release upload --clobber`, нет → `gh release create`.
**Где это в коде:** [.github/workflows/release.yml](../../.github/workflows/release.yml).

## 2026-07-23 — VerifyCli: ложный abort «pointer being freed was not allocated» в debug-сборке

**Симптом:** `swift run VerifyCli` (debug) падает с abort про освобождение невыделенного указателя при выходе из процесса, хотя вся полезная работа уже выполнена.
**Причина:** ложное срабатывание nano-malloc-проверки в debug-сборке; это не баг кода проекта.
**Обход:** запускать только `swift run -c release VerifyCli` — в release проблема не проявляется.
**Где это в коде:** [Sources/VerifyCli/main.swift](../../Sources/VerifyCli/main.swift).

## 2026-07-23 — Окна лимитов различаются по длительности, а не по позиции в ответе API

**Симптом:** если различать 5-часовое и недельное окна по порядку следования в ответе API, метки окон периодически перепутываются.
**Причина:** порядок окон в ответе API не гарантирован.
**Обход:** различать окна по `windowDurationMins` (300 = 5h, 10080 = weekly) через `RateLimitWindowLabel`; `SnapshotWindow.usedPercent == nil` означает «слот заявлен, данных нет», а не «слота нет».
**Где это в коде:** [Sources/MacLimitsTrackerCore/Models/LimitsSnapshot.swift](../../Sources/MacLimitsTrackerCore/Models/LimitsSnapshot.swift), [Sources/MacLimitsTrackerCore/Providers/SnapshotMapping.swift](../../Sources/MacLimitsTrackerCore/Providers/SnapshotMapping.swift).

## 2026-07-23 — Kimi resetTime с микросекундами не парсится дефолтным ISO8601DateFormatter

**Симптом:** тесты зелёные (образец без дробей), но в живом рантайме у Kimi-окон `resetsAt == nil` — даты сброса молча пропадают.
**Причина:** `GET /coding/v1/usages` отдаёт `resetTime` с микросекундами (`"2026-07-23T13:15:06.269279Z"`); `ISO8601DateFormatter()` по умолчанию дробные секунды не парсит и возвращает `nil`.
**Обход:** парсить сначала форматтером с `.withFractionalSeconds`, затем обычным (поля без дробей тоже встречаются). См. `KimiUsagesParser.parseISO8601`.
**Где это в коде:** [Sources/MacLimitsTrackerCore/Models/KimiModels.swift](../../Sources/MacLimitsTrackerCore/Models/KimiModels.swift).
