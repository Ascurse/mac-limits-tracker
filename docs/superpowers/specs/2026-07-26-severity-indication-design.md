# Severity-индикация в menu bar и desktop widget

## Цель

Показать настроенные пороги `warning`/`critical` не только в popup, но и на двух компактных поверхностях: tint иконки/текста menu bar и цвет прогресс-баров desktop widget.

## Решение

Классификация остаётся общей и чистой: для каждого окна с `usedPercent` вычисляется остаток `max(0, 100 - usedPercent)`, затем применяется `Severity.from(remainingPercent:thresholds:)`. Новый helper в core возвращает худшую severity среди окон всех состояний. Окна без данных (`usedPercent == nil`), loading и error не создают severity и не окрашивают поверхность как warning/critical; если данных нет, результатом считается `.normal`.

`MacLimitsTrackerApp` использует этот результат для label `MenuBarExtra`: `Image` и текст в каждом `MenuBarDisplayMode` получают один общий foreground tint. Текстовые значения и выбор режима не меняются. Нормальный статус использует системный tint, warning — `.orange`, critical — `.red`; существующая иконка ошибки и refresh-логика остаются без изменений.

`DesktopWidgetView` добавляет severity к внутренней модели окна и передаёт `viewModel.severityThresholds` при построении окон. В normal сохраняется accent провайдера, warning окрашивается `.orange`, critical — `.red`. Stale-ветка продолжает брать окна из last-good snapshot и сохраняет текущую opacity; loading, usage unavailable и error-ветки не меняются.

## Границы и совместимость

- Не меняются форматы menu-bar текста, порядок окон, правила stale snapshot и popup-рендеринг.
- Пороговая семантика остаётся по остатку лимита и использует пользовательские значения из `LimitsViewModel`, а не `.standard` внутри UI.
- Не добавляются зависимости и новые persistence/API-контракты.
- Окна классифицируются по данным окна, а не по позиции в массиве или label.

## Тестирование и наблюдаемая проверка

- Core tests проверяют worst severity для normal/warning/critical, custom thresholds и отсутствие usable windows.
- Существующие `MenuBarDisplayMode` tests остаются зелёными и подтверждают неизменность текстовых контрактов; отдельный pure test проверяет severity helper на смешанных Claude/Codex windows.
- Реальная macOS surface QA проверяет menu-bar label в `iconOnly`, `iconAndText`, `iconAnd5h`, `iconAnd5hWeekly` и desktop widget с normal/warning/critical окнами, включая stale snapshot. PASS — видимый tint/bar color соответствует worst severity и configured thresholds.

## Риски

Основной риск — расхождение порогов между popup и компактными поверхностями. Он закрывается единственным core helper и явной передачей `viewModel.severityThresholds` в widget; UI-тестовые сценарии отдельно проверяют custom thresholds.
