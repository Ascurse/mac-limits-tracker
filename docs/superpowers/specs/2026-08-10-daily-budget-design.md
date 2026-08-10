# Дневной ориентир недельного лимита

## Цель

Показывать в menu-bar popup необязательный ориентир: какой процент остатка
weekly-лимита можно равномерно потратить до конца текущего локального дня,
не опережая время сброса weekly-окна.

## Границы

В первый scope входят:

- только weekly-окно (`windowDurationMins == 10080`);
- все четыре темы menu-bar popup;
- обычное desktop-окно через тот же `ProviderOverview`/`PopupContentBuilder`;
- глобальная настройка `Show daily budget`, сохранённая в `UserDefaults`;
- чистый расчёт в Core и presentation-контракт для UI.

Не входят:

- прогноз для rolling 5h-окна;
- desktop widget;
- изменение API или расчётов провайдеров;
- замена существующего burn rate/time-to-exhaustion из `qne`.

## Расчёт

`DailyBudgetCalculator` получает `remainingPercent`, `resetAt`, `now` и
инжектированный `Calendar`.

```text
usableUntil = min(endOfLocalDay, resetAt)
budgetPercent = remainingPercent
  * (usableUntil - now)
  / (resetAt - now)
```

`remainingPercent` ограничивается диапазоном `0...100`. Результат отсутствует,
если нет `resetAt`, reset уже наступил, weekly-окна нет, либо stale-данные не
могут считаться свежим основанием для ориентира. Если остаток равен нулю,
валидный результат равен `0%`.

`Calendar.current` используется в приложении, а календарь передаётся явно в
чистую функцию для тестов, включая границы локального дня и переходы времени.

## Presentation

Добавляется `DailyBudgetContent` и `PopupRow.dailyBudget`. Строка вставляется
сразу после weekly `PopupRow.window` и имеет нейтральный copy вида
`Today pace: ~5% of weekly limit`: это ориентир, а не обещанный лимит. Общий
builder используется четырьмя menu-bar темами и обычным desktop-окном.

`PopupContentBuilder.section` и `.sections` получают `showDailyBudget` и
`calendar` с текущими default-значениями. При выключенной настройке строка не
создаётся; отсутствие данных также не создаёт шумную ошибку.

## Настройка

`AppSettingsStore` получает ключ `showDailyBudget` с default `true`, а
`LimitsViewModel` — published-проекцию и `setShowDailyBudget(_:)` по паттерну
`showUsageTrends`. `DisplaySettingsSection` показывает toggle с устойчивыми
label/accessibility label. Изменение настройки только меняет presentation и
персистентность, не запускает fetch или сетевой запрос.

## Проверка

- unit-тесты калькулятора: обычный день, reset до полуночи, отсутствие/past
  reset, нулевой и clamped остаток, игнорирование 5h, DST/calendar boundary;
- persistence-тесты `AppSettingsStore` и `LimitsViewModel`: default, round-trip,
  загрузка, setter и отсутствие refresh;
- `PopupContentBuilder`-тесты: weekly visible, toggle hidden, invalid/stale
  omitted, 5h omitted;
- manual/AX QA: переключить настройку, проверить все четыре темы, обычное
  desktop-окно и persistence после relaunch.
