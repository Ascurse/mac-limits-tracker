# Glossary — доменный словарь

Бизнес-термины, аббревиатуры и проектные имена, которых нет в коде явно. Если разработчик / AI впервые видит слово — оно должно быть здесь.

Формат: `**Термин** — определение. Где встречается.` Одна строка на термин, без истории изменений.

Термин ушёл из продукта/кода — **удаляй**, не архивируй: глоссарий должен отражать текущее состояние домена, а не его историю.

---

## Бизнес-домен

- **Провайдер (лимитов)** — источник данных о лимитах одного ИИ-инструмента (Claude Code, Codex или Kimi Code); в коде — тип, реализующий `LimitsProvider`. Встречается: `Sources/MacLimitsTrackerCore/Providers/`.
- **Окно (лимитов)** — период действия лимита: 5-часовое (300 мин) или недельное (10080 мин). Встречается: `SnapshotWindow`, `RateLimitWindowLabel`.

## Технические аббревиатуры

- **bd** — beads, локальный трекер задач проекта (Dolt DB + `bd` CLI). Встречается: `.beads/`, `AGENTS.md`.

## Архитектурные термины

- **Surface (поверхность)** — один из четырёх UI-контекстов приложения: menu-bar popup, singleton desktop window, native Settings или desktop widget; они используют общий `LimitsViewModel`, но сохраняют разные lifecycle/layout. Встречается: `MacLimitsTrackerApp`, `ProviderOverviewSurface`, `DesktopWidgetController`.
- **Hybrid launch mode** — режим unbundled `swift run`: процесс стартует как `.accessory`, временно становится `.regular`, пока открыт desktop window или Settings, затем возвращается в menu-bar-only. Встречается: `WindowPresentationController.LaunchMode.hybrid`.
- **Persistent-regular launch mode** — режим bundled `.app`: процесс остаётся `.regular` с Dock/Cmd-Tab на протяжении всей жизни, не теряя `MenuBarExtra`. Встречается: `WindowPresentationController.LaunchMode.persistentRegular`.

## Проектные имена / кодовые названия

- **VerifyCli** — диагностический CLI, печатает реальные снапшоты лимитов по всем провайдерам; запускать только в release. Встречается: `Sources/VerifyCli/`.

## Внешние системы

- **Claude Code CLI / Codex CLI / Kimi Code CLI** — консольные инструменты, чьи локальные credentials или live limits использует приложение; кнопки «открыть CLI» в попапе ведут к ним.
