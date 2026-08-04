import SwiftUI
import MacLimitsTrackerCore

/// Поверхность, на которой рендерится сводка провайдеров: попап меню-бара
/// или desktop-виджет. Плотность — только layout, не бизнес-правила.
enum ProviderOverviewSurface {
    case menuBar
    case desktop
}

/// Чистая сводка провайдеров: входом являются готовые секции и тема;
/// transport/polling/UserDefaults сюда не попадают.
struct ProviderOverview: View {
    let sections: [ProviderSectionContent]
    let theme: AppTheme
    let surface: ProviderOverviewSurface

    var body: some View {
        switch theme {
        case .system:
            SystemOverviewBody(sections: sections, surface: surface)
        case .terminal:
            TerminalOverviewBody(sections: sections, surface: surface)
        case .phosphor:
            PhosphorOverviewBody(sections: sections, surface: surface)
        case .tui:
            TUIOverviewBody(sections: sections, surface: surface)
        }
    }
}

// Значения палитр живут в Core (`ThemePalette`) — так контраст проверяется
// тестом; здесь только обёртки hex → Color.

enum TerminalPalette {
    static let bg = Color(hex: ThemePalette.Terminal.bg)
    static let fg = Color(hex: ThemePalette.Terminal.fg)
    static let dim = Color(hex: ThemePalette.Terminal.dim)
    static let track = Color(hex: ThemePalette.Terminal.track)
    static let cyan = Color(hex: ThemePalette.Terminal.cyan)
    static let warning = Color(hex: ThemePalette.Terminal.warning)
    static let critical = Color(hex: ThemePalette.Terminal.critical)
}

enum PhosphorPalette {
    static let bg = Color(hex: ThemePalette.Phosphor.bg)
    static let bright = Color(hex: ThemePalette.Phosphor.bright)
    static let mid = Color(hex: ThemePalette.Phosphor.mid)
    static let dim = Color(hex: ThemePalette.Phosphor.dim)
    static let heading = Color(hex: ThemePalette.Phosphor.heading)
}

enum TuiPalette {
    static let bg = Color(hex: ThemePalette.Tui.bg)
    static let fg = Color(hex: ThemePalette.Tui.fg)
    static let border = Color(hex: ThemePalette.Tui.border)
    static let dim = Color(hex: ThemePalette.Tui.dim)
    static let normal = Color(hex: ThemePalette.Tui.normal)
    static let warning = Color(hex: ThemePalette.Tui.warning)
    static let critical = Color(hex: ThemePalette.Tui.critical)
}

/// Строка «ключ — значение» моноширинных тем. Пока пара помещается целиком,
/// это одна строка со значением по правому краю; когда перестаёт — значение
/// уходит на свою строку вместо того, чтобы сжиматься в многоточие.
/// Обрезание остаётся последним средством, и тогда полное значение доступно
/// в подсказке и озвучке.
struct CompactKeyValueRow: View {
    let key: String
    let value: String
    let keyColor: Color
    var valueColor: Color?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                keyText
                Spacer(minLength: 8)
                valueText
            }
            VStack(alignment: .leading, spacing: 1) {
                keyText
                valueText.lineLimit(1).truncationMode(.middle)
            }
        }
        .help(value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key)
        .accessibilityValue(value)
    }

    private var keyText: Text {
        Text(key).foregroundStyle(keyColor)
    }

    private var valueText: some View {
        let text = Text(value)
        return (valueColor.map { text.foregroundStyle($0) } ?? text)
            .monospacedDigit()
    }
}

/// Кнопка «открыть CLI провайдера» в шапке секции. Пока подпись помещается,
/// действие названо словом; когда ширины нет — остаётся иконка, но озвучка и
/// подсказка не меняются. Одна иконка без подписи читалась как украшение, и
/// смысл появлялся только при наведении (bd mac-limits-tracker-avs).
struct ProviderOpenButton: View {
    let loginHelp: LoginHelp
    let providerTitle: String
    var tint: Color?

    var body: some View {
        Button {
            openProviderCLI(loginHelp)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 3) {
                    icon
                    Text(LoginHelp.actionTitle).fixedSize()
                }
                icon
            }
            .foregroundStyle(tint ?? .accentColor)
        }
        .buttonStyle(.borderless)
        .help(loginHelp.helpText)
        .accessibilityLabel(loginHelp.accessibilityLabel(providerTitle: providerTitle))
    }

    private var icon: some View {
        Image(systemName: "arrow.up.forward.app").accessibilityHidden(true)
    }
}

/// Системная тема: текущий нативный вид сводки.
struct SystemOverviewBody: View {
    let sections: [ProviderSectionContent]
    let surface: ProviderOverviewSurface

    // Плотность: на desktop чуть просторнее. Меняет только геометрию,
    // правила контента не трогает.
    private var spacing: CGFloat { surface == .desktop ? 10 : 8 }

    var body: some View {
        ForEach(sections, id: \.descriptor.id) { s in
            Divider()
            section(s)
        }
    }

    private func section(_ s: ProviderSectionContent) -> some View {
        let accent = Color(hex: s.descriptor.accentColorHex)
        return VStack(alignment: .leading, spacing: spacing) {
            sectionLabel(s.title, color: accent,
                         loginHelp: s.descriptor.loginHelp)
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, row in
                rowView(row, accent: accent)
            }
        }
        .opacity(s.isStale ? StaleAppearance.opacity : 1)
    }

    @ViewBuilder
    private func rowView(_ row: PopupRow, accent: Color) -> some View {
        switch row {
        case .detail(let key, let value):
            detailRow(key, value)
        case .window(let w):
            detailRow("\(w.longLabel) remaining", w.remainingText)
            detailRow("\(w.longLabel) resets", w.resetText ?? "—")
        case .sparkline(let spark):
            UsageTrendView(content: spark,
                           tokens: systemTrendTokens(accent: accent),
                           variant: surface.trendVariant,
                           showHeader: false)
        case .burnRate(let burn):
            Text(burn.text)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .cost(let c):
            detailRow(c.label, c.valueText)
            Text(c.footnoteText)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        case .recovery(let content):
            Label(content.primaryText, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .help(content.diagnostic)
                .accessibilityLabel(content.primaryText)
                .accessibilityHint("Diagnostic: \(content.diagnostic)")
        case .note(let text):
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func sectionLabel(_ title: String, color: Color, loginHelp: LoginHelp?) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if let loginHelp {
                ProviderOpenButton(loginHelp: loginHelp, providerTitle: title)
                    .font(.caption)
            }
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

    private func systemTrendTokens(accent: Color) -> UsageTrendTokens {
        UsageTrendTokens(accent: accent,
                         guide: .secondary.opacity(0.25),
                         text: .primary,
                         dim: .secondary,
                         lineWidth: 2,
                         pointSize: surface == .desktop ? 8 : 5,
                         pointShape: .circle,
                         background: nil,
                         border: nil,
                         font: .caption)
    }
}

/// Тема Terminal: палитра Tokyo Night, тонкие полосы прогресса.
struct TerminalOverviewBody: View {
    let sections: [ProviderSectionContent]
    let surface: ProviderOverviewSurface

    private typealias Palette = TerminalPalette

    // Плотность: на desktop — крупнее mono и просторнее секции; только геометрия,
    // правила контента не трогает. На menuBar шрифт наследуется от shell'а (без изменений).
    private var spacing: CGFloat { surface == .desktop ? 8 : 6 }
    private var desktopFont: Font? { surface == .desktop ? .system(size: 12, design: .monospaced) : nil }

    var body: some View {
        ForEach(sections, id: \.descriptor.id) { s in
            section(s)
        }
        .font(desktopFont)
    }

    private func section(_ s: ProviderSectionContent) -> some View {
        let accent = Color(hex: s.descriptor.accentColorHex)
        return VStack(alignment: .leading, spacing: spacing) {
            HStack(spacing: 6) {
                Text("●").foregroundStyle(accent)
                Text(s.descriptor.id)
                // Значение Plan из первой detail-строки показываем рядом с именем.
                if case .detail(let key, let value) = s.rows.first, key == "Plan" {
                    Text(value).foregroundStyle(Palette.dim)
                }
                Spacer()
                if let loginHelp = s.descriptor.loginHelp {
                    ProviderOpenButton(loginHelp: loginHelp,
                                       providerTitle: s.title,
                                       tint: Palette.cyan)
                }
            }
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, row in
                rowView(row, accent: accent)
            }
        }
        .opacity(s.isStale ? StaleAppearance.opacity : 1)
    }

    @ViewBuilder
    private func rowView(_ row: PopupRow, accent: Color) -> some View {
        switch row {
        case .detail(let key, let value):
            // Plan уже показан в заголовке секции.
            if key != "Plan" {
                CompactKeyValueRow(key: key.lowercased(), value: value,
                                   keyColor: Palette.dim)
            }
        case .window(let w):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(w.shortLabel).foregroundStyle(Palette.dim)
                        .frame(width: 20, alignment: .leading)
                    bar(w, accent: accent)
                    // Процент не сжимаем: полоса растягивается, значение — нет.
                    Text(w.remainingText).monospacedDigit()
                        .fixedSize()
                        .frame(minWidth: 36, alignment: .trailing)
                }
                if let reset = w.resetText {
                    Text("resets \(reset)")
                        .foregroundStyle(Palette.dim)
                        .padding(.leading, 26)
                }
            }
        case .sparkline(let spark):
            UsageTrendView(content: spark,
                           tokens: terminalTrendTokens(accent: accent),
                           variant: surface.trendVariant,
                           showHeader: false)
                .padding(.leading, 26)
        case .burnRate(let burn):
            Text(burn.text)
                .font(.caption)
                .foregroundStyle(terminalPaceColor(burn.pace))
                .padding(.leading, 26)
        case .cost(let c):
            VStack(alignment: .leading, spacing: 2) {
                CompactKeyValueRow(key: c.label.lowercased(), value: c.valueText,
                                   keyColor: Palette.dim,
                                   valueColor: costValueColor(c.state))
                Text(c.footnoteText).foregroundStyle(Palette.dim)
            }
        case .error(let message):
            Text("✗ \(message)").foregroundStyle(Palette.critical)
        case .recovery(let content):
            Text("✗ \(content.primaryText)")
                .foregroundStyle(Palette.critical)
                .help(content.diagnostic)
                .accessibilityLabel(content.primaryText)
                .accessibilityHint("Diagnostic: \(content.diagnostic)")
        case .note(let text):
            Text(text).foregroundStyle(Palette.dim)
        }
    }

    private func costValueColor(_ state: CostRowState) -> Color {
        switch state {
        case .available:   return Palette.fg
        case .incomplete:  return Palette.warning
        case .unavailable: return Palette.dim
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
        .frame(minWidth: 24, idealWidth: 80)
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

    private func terminalPaceColor(_ pace: BurnRatePace) -> Color {
        switch pace {
        case .fast:     return Palette.critical
        case .moderate: return Palette.warning
        case .slow:     return Palette.dim
        }
    }

    private func terminalTrendTokens(accent: Color) -> UsageTrendTokens {
        UsageTrendTokens(accent: accent,
                         guide: Palette.track,
                         text: Palette.fg,
                         dim: Palette.dim,
                         lineWidth: 1,
                         pointSize: surface == .desktop ? 4 : 3,
                         pointShape: .square,
                         background: nil,
                         border: nil,
                         font: desktopFont ?? .caption)
    }
}

/// Тема Phosphor: монохромный зелёный CRT.
struct PhosphorOverviewBody: View {
    let sections: [ProviderSectionContent]
    let surface: ProviderOverviewSurface

    private typealias Palette = PhosphorPalette

    // Плотность: на desktop — крупнее mono и просторнее секции; только геометрия,
    // правила контента не трогает. На menuBar шрифт наследуется от shell'а (без изменений).
    private var spacing: CGFloat { surface == .desktop ? 6 : 4 }
    private var desktopFont: Font? { surface == .desktop ? .system(size: 12, design: .monospaced) : nil }

    var body: some View {
        ForEach(sections, id: \.descriptor.id) { s in
            section(s)
        }
        .font(desktopFont)
    }

    private func section(_ s: ProviderSectionContent) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(spacing: 6) {
                Text("▸ \(s.title.uppercased())").foregroundStyle(Palette.heading)
                if case .detail(let key, let value) = s.rows.first, key == "Plan" {
                    Text("[\(value)]").foregroundStyle(Palette.mid)
                }
                Spacer()
                if let loginHelp = s.descriptor.loginHelp {
                    Button {
                        openProviderCLI(loginHelp)
                    } label: {
                        Text("[open]").foregroundStyle(Palette.bright)
                    }
                    .buttonStyle(.plain)
                    .help(loginHelp.helpText)
                    .accessibilityLabel(loginHelp.accessibilityLabel(providerTitle: s.title))
                }
            }
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
        }
        .opacity(s.isStale ? StaleAppearance.opacity : 1)
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
                    // Цветом монохромная тема состояния не различает, поэтому у
                    // каждого — текстура полосы плюс маркер перед значением;
                    // критичное сверх того инвертировано.
                    if w.severity == .critical {
                        bar(w).foregroundStyle(Palette.bg).background(Palette.bright)
                    } else {
                        bar(w)
                    }
                    Text(w.severity.asciiMarker.isEmpty
                         ? w.remainingText
                         : "\(w.severity.asciiMarker) \(w.remainingText)")
                        .monospacedDigit()
                }
                if let reset = w.resetText {
                    Text("reset \(reset)")
                        .foregroundStyle(Palette.mid)
                        .padding(.leading, 26)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(w.longLabel), \(w.remainingText) remaining, \(w.severity.accessibilityLabel)")
        case .sparkline(let spark):
            UsageTrendView(content: spark,
                           tokens: phosphorTrendTokens,
                           variant: surface.trendVariant,
                           showHeader: false)
                .padding(.leading, 26)
        case .burnRate(let burn):
            Text(burn.text)
                .font(.caption)
                .foregroundStyle(Palette.mid)
                .padding(.leading, 26)
        case .cost(let c):
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(c.label.lowercased()).foregroundStyle(Palette.mid)
                    Spacer(minLength: 8)
                    Text(c.valueText).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(c.state == .unavailable ? Palette.mid : Palette.bright)
                }
                Text(c.footnoteText).foregroundStyle(Palette.mid)
            }
        case .error(let message):
            Text("! \(message)").foregroundStyle(Palette.heading)
        case .recovery(let content):
            Text("! \(content.primaryText)")
                .foregroundStyle(Palette.heading)
                .help(content.diagnostic)
                .accessibilityLabel(content.primaryText)
                .accessibilityHint("Diagnostic: \(content.diagnostic)")
        case .note(let text):
            Text(text).foregroundStyle(Palette.mid)
        }
    }

    private func bar(_ w: WindowContent) -> some View {
        Text(AsciiBar.render(remainingPercent: w.remainingPercent, severity: w.severity))
            .accessibilityHidden(true)
    }

    private var phosphorTrendTokens: UsageTrendTokens {
        UsageTrendTokens(accent: Palette.mid,
                         guide: Palette.dim,
                         text: Palette.bright,
                         dim: Palette.mid,
                         lineWidth: 1,
                         pointSize: surface == .desktop ? 4 : 3,
                         pointShape: .square,
                         background: nil,
                         border: nil,
                         font: desktopFont ?? .caption)
    }
}

/// Тема TUI: панели с рамками и датчиками в духе htop.
struct TUIOverviewBody: View {
    let sections: [ProviderSectionContent]
    let surface: ProviderOverviewSurface

    private typealias Palette = TuiPalette

    // Плотность: на desktop — крупнее mono и просторнее секции; только геометрия,
    // правила контента не трогает. На menuBar шрифт наследуется от shell'а (без изменений).
    private var spacing: CGFloat { surface == .desktop ? 6 : 4 }
    private var desktopFont: Font? { surface == .desktop ? .system(size: 12, design: .monospaced) : nil }

    var body: some View {
        ForEach(sections, id: \.descriptor.id) { s in
            panel(s)
        }
        .font(desktopFont)
    }

    // Панель с рамкой; заголовок врезан в верхнюю кромку — рамку рисуем
    // SwiftUI-обводкой, не символами (символьные рамки «плывут» по ширине).
    private func panel(_ s: ProviderSectionContent) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
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
                if let loginHelp = s.descriptor.loginHelp {
                    Button {
                        openProviderCLI(loginHelp)
                    } label: {
                        Text("[open]")
                    }
                    .buttonStyle(.plain)
                    .help(loginHelp.helpText)
                    .accessibilityLabel(loginHelp.accessibilityLabel(providerTitle: s.title))
                }
            }
            .padding(.horizontal, 4)
            .background(Palette.bg)
            .foregroundStyle(Palette.dim)
            .offset(x: 8, y: -8)
        }
        .padding(.top, 8)
        .opacity(s.isStale ? StaleAppearance.opacity : 1)
    }

    @ViewBuilder
    private func rowView(_ row: PopupRow) -> some View {
        switch row {
        case .detail(let key, let value):
            if key != "Plan" {
                CompactKeyValueRow(key: key.lowercased(), value: value,
                                   keyColor: Palette.dim)
            }
        case .window(let w):
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(w.shortLabel)
                        .foregroundStyle(Palette.dim)
                        .frame(width: 20, alignment: .leading)
                    gauge(w)
                    // Процент не сжимаем: датчик и так фиксированной ширины.
                    Text(w.remainingText).monospacedDigit()
                        .fixedSize()
                        .frame(minWidth: 36, alignment: .trailing)
                }
                if let reset = w.resetText {
                    Text("reset \(reset)")
                        .foregroundStyle(Palette.dim)
                        .padding(.leading, 24)
                }
            }
        case .sparkline(let spark):
            UsageTrendView(content: spark,
                           tokens: tuiTrendTokens,
                           variant: surface.trendVariant,
                           showHeader: false)
                .padding(.leading, 24)
        case .burnRate(let burn):
            Text("[\(burn.text)]")
                .font(.caption)
                .foregroundStyle(tuiPaceColor(burn.pace))
                .padding(.leading, 24)
        case .cost(let c):
            VStack(alignment: .leading, spacing: 1) {
                CompactKeyValueRow(key: c.label.lowercased(), value: c.valueText,
                                   keyColor: Palette.dim,
                                   valueColor: costValueColor(c.state))
                Text(c.footnoteText).foregroundStyle(Palette.dim)
            }
        case .error(let message):
            Text("✗ \(message)").foregroundStyle(Palette.critical)
        case .recovery(let content):
            Text("✗ \(content.primaryText)")
                .foregroundStyle(Palette.critical)
                .help(content.diagnostic)
                .accessibilityLabel(content.primaryText)
                .accessibilityHint("Diagnostic: \(content.diagnostic)")
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
        .accessibilityHidden(true)
    }

    private func severityColor(_ severity: Severity) -> Color {
        switch severity {
        case .normal:   return Palette.normal
        case .warning:  return Palette.warning
        case .critical: return Palette.critical
        }
    }

    private func tuiPaceColor(_ pace: BurnRatePace) -> Color {
        switch pace {
        case .fast:     return Palette.critical
        case .moderate: return Palette.warning
        case .slow:     return Palette.dim
        }
    }

    private func costValueColor(_ state: CostRowState) -> Color {
        switch state {
        case .available:   return Palette.fg
        case .incomplete:  return Palette.warning
        case .unavailable: return Palette.dim
        }
    }

    private var tuiTrendTokens: UsageTrendTokens {
        UsageTrendTokens(accent: Palette.normal,
                         guide: Palette.border,
                         text: Palette.fg,
                         dim: Palette.dim,
                         lineWidth: 1,
                         pointSize: surface == .desktop ? 4 : 3,
                         pointShape: .square,
                         background: nil,
                         border: nil,
                         font: desktopFont ?? .caption)
    }
}

// MARK: - Previews

/// Фикстуры превью: здоровый провайдер (2 окна + история за 24ч → спарклайн),
/// stale (свежий providerError + lastGood с окнами), error-only и loading
/// (snapshot == nil) — все четыре состояния одной сводкой.
private enum ProviderOverviewPreviewFixtures {
    static let claude = ProviderDescriptor(
        id: "claude", displayName: "Claude Code", shortName: "Claude",
        menuBarSymbol: "C", accentColorHex: 0xD97706, loginHelp: nil)
    static let codex = ProviderDescriptor(
        id: "codex", displayName: "Codex", shortName: "Codex",
        menuBarSymbol: "X", accentColorHex: 0x10A37F, loginHelp: nil)
    static let kimi = ProviderDescriptor(
        id: "kimi", displayName: "Kimi Code", shortName: "Kimi",
        menuBarSymbol: "K", accentColorHex: 0x7C5CFF, loginHelp: nil)
    static let demo = ProviderDescriptor(
        id: "demo", displayName: "Demo", shortName: "Demo",
        menuBarSymbol: "D", accentColorHex: 0x0A84FF, loginHelp: nil)

    static func sections(now: Date = Date()) -> [ProviderSectionContent] {
        PopupContentBuilder.sections(states(now: now), now: now, history: history(now: now))
    }

    private static func states(now: Date) -> [ProviderState] {
        [
            ProviderState(descriptor: claude, snapshot: healthySnapshot(now: now)),
            ProviderState(descriptor: codex,
                          snapshot: errorSnapshot(now: now),
                          lastGoodSnapshot: goodSnapshot(now: now)),
            ProviderState(descriptor: kimi, snapshot: errorSnapshot(now: now)),
            ProviderState(descriptor: demo, snapshot: nil),
        ]
    }

    private static func healthySnapshot(now: Date) -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: true, plan: "max",
            windows: [
                SnapshotWindow(windowDurationMins: 300, usedPercent: 22,
                               resetsAt: now.addingTimeInterval(2 * 3600)),
                SnapshotWindow(windowDurationMins: 10080, usedPercent: 41,
                               resetsAt: now.addingTimeInterval(3 * 24 * 3600)),
            ],
            creditsBalance: nil, rateLimitReachedType: nil,
            details: [], daysUntilRenewal: nil, renewalDate: nil,
            usageError: nil, providerError: nil, fetchedAt: now)
    }

    private static func goodSnapshot(now: Date) -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: true, plan: "plus",
            windows: [
                SnapshotWindow(windowDurationMins: 300, usedPercent: 58,
                               resetsAt: now.addingTimeInterval(3600)),
                SnapshotWindow(windowDurationMins: 10080, usedPercent: 12,
                               resetsAt: now.addingTimeInterval(4 * 24 * 3600)),
            ],
            creditsBalance: "42.00", rateLimitReachedType: nil,
            details: [], daysUntilRenewal: nil, renewalDate: nil,
            usageError: nil, providerError: nil,
            fetchedAt: now.addingTimeInterval(-3 * 3600))
    }

    private static func errorSnapshot(now: Date) -> LimitsSnapshot {
        LimitsSnapshot(
            loggedIn: true, plan: nil, windows: nil,
            creditsBalance: nil, rateLimitReachedType: nil,
            details: [], daysUntilRenewal: nil, renewalDate: nil,
            usageError: nil, providerError: "network unreachable", fetchedAt: now)
    }

    private static func history(now: Date) -> (String) -> [UsageSample] {
        { providerId in
            guard providerId == claude.id || providerId == codex.id else { return [] }

            let windowDurations = [300, 10080]
            let sampleCount = 12
            let stepHours = 2
            let stepSeconds: TimeInterval = TimeInterval(stepHours * 3600)
            let baseUsedPercent = 12.0
            let hourlyIncrement = 2.5
            let weeklyOffset = 20.0

            var samples: [UsageSample] = []
            samples.reserveCapacity(sampleCount * windowDurations.count)
            for i in 0..<sampleCount {
                let offset: TimeInterval = -Double(i) * stepSeconds
                let fetchedAt = now.addingTimeInterval(offset)
                let indexPercent = baseUsedPercent + Double(i) * hourlyIncrement
                for mins in windowDurations {
                    let windowOffset = (mins == 10080) ? weeklyOffset : 0.0
                    let usedPercent = indexPercent + windowOffset
                    samples.append(UsageSample(
                        providerId: providerId,
                        windowMins: mins,
                        fetchedAt: fetchedAt,
                        usedPercent: usedPercent,
                        resetsAt: nil
                    ))
                }
            }
            return samples
        }
    }
}

#Preview("System — menuBar") {
    ProviderOverview(sections: ProviderOverviewPreviewFixtures.sections(),
                     theme: .system, surface: .menuBar)
        .padding()
        .frame(width: 340)
}

#Preview("System — desktop") {
    ProviderOverview(sections: ProviderOverviewPreviewFixtures.sections(),
                     theme: .system, surface: .desktop)
        .padding()
        .frame(width: 480)
}

#Preview("Terminal — menuBar") {
    ProviderOverview(sections: ProviderOverviewPreviewFixtures.sections(),
                     theme: .terminal, surface: .menuBar)
        .font(Font.system(size: 11, design: .monospaced))
        .foregroundStyle(TerminalPalette.fg)
        .padding()
        .frame(width: 340)
        .background(TerminalPalette.bg)
        .preferredColorScheme(.dark)
}

#Preview("Terminal — desktop") {
    ProviderOverview(sections: ProviderOverviewPreviewFixtures.sections(),
                     theme: .terminal, surface: .desktop)
        .foregroundStyle(TerminalPalette.fg)
        .padding()
        .frame(width: 480)
        .background(TerminalPalette.bg)
        .preferredColorScheme(.dark)
}

#Preview("Phosphor — menuBar") {
    ProviderOverview(sections: ProviderOverviewPreviewFixtures.sections(),
                     theme: .phosphor, surface: .menuBar)
        .font(Font.system(size: 11, design: .monospaced))
        .foregroundStyle(PhosphorPalette.bright)
        .padding()
        .frame(width: 340)
        .background(PhosphorPalette.bg)
        .preferredColorScheme(.dark)
}

#Preview("Phosphor — desktop") {
    ProviderOverview(sections: ProviderOverviewPreviewFixtures.sections(),
                     theme: .phosphor, surface: .desktop)
        .foregroundStyle(PhosphorPalette.bright)
        .padding()
        .frame(width: 480)
        .background(PhosphorPalette.bg)
        .preferredColorScheme(.dark)
}

#Preview("TUI — menuBar") {
    ProviderOverview(sections: ProviderOverviewPreviewFixtures.sections(),
                     theme: .tui, surface: .menuBar)
        .font(Font.system(size: 11, design: .monospaced))
        .foregroundStyle(TuiPalette.fg)
        .padding()
        .frame(width: 340)
        .background(TuiPalette.bg)
        .preferredColorScheme(.dark)
}

#Preview("TUI — desktop") {
    ProviderOverview(sections: ProviderOverviewPreviewFixtures.sections(),
                     theme: .tui, surface: .desktop)
        .foregroundStyle(TuiPalette.fg)
        .padding()
        .frame(width: 480)
        .background(TuiPalette.bg)
        .preferredColorScheme(.dark)
}
