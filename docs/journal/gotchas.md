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