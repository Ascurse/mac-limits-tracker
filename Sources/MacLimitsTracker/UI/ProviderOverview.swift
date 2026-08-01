import SwiftUI
import Charts
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

enum TerminalPalette {
    static let bg = Color(hex: 0x1A1B26)
    static let fg = Color(hex: 0xC0CAF5)
    static let dim = Color(hex: 0x565F89)
    static let track = Color(hex: 0x2F334D)
    static let cyan = Color(hex: 0x7DCFFF)
    static let warning = Color(hex: 0xE0AF68)
    static let critical = Color(hex: 0xF7768E)
}

enum PhosphorPalette {
    static let bg = Color(hex: 0x050805)
    static let bright = Color(hex: 0x35E06A)
    static let mid = Color(hex: 0x1E9C48)
    static let dim = Color(hex: 0x164A26)
    static let heading = Color(hex: 0x8DFFB0)
}

enum TuiPalette {
    static let bg = Color(hex: 0x101216)
    static let fg = Color(hex: 0xD0D5DD)
    static let border = Color(hex: 0x3A4150)
    static let dim = Color(hex: 0x5A6374)
    static let normal = Color(hex: 0x9ECE6A)
    static let warning = Color(hex: 0xE0AF68)
    static let critical = Color(hex: 0xF7768E)
}

/// Системная тема: текущий нативный вид сводки.
struct SystemOverviewBody: View {
    let sections: [ProviderSectionContent]
    let surface: ProviderOverviewSurface

    // Плотность: на desktop чуть просторнее. Меняет только геометрию,
    // правила контента не трогает.
    private var spacing: CGFloat { surface == .desktop ? 10 : 8 }
    private var sparklineHeight: CGFloat { surface == .desktop ? 44 : 28 }

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
        .opacity(s.isStale ? 0.55 : 1)
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
            VStack(alignment: .leading, spacing: 2) {
                // PointMark обязателен: одиночный LineMark с одной точкой ничего не рисует.
                Chart(spark.points, id: \.time) { point in
                    LineMark(x: .value("Time", point.time), y: .value("Used", point.usedPercent))
                    PointMark(x: .value("Time", point.time), y: .value("Used", point.usedPercent))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .foregroundStyle(accent)
                .frame(height: sparklineHeight)
                // Подпись диапазона: "7d" слева, дни начала/конца справа.
                HStack {
                    Text("7d")
                    Spacer()
                    Text(spark.rangeStart, format: .dateTime.month(.abbreviated).day())
                    Text("–")
                    Text(spark.rangeEnd, format: .dateTime.month(.abbreviated).day())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
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
                Button {
                    openProviderCLI(loginHelp)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help(loginHelp.helpText)
                .accessibilityLabel("Open \(title)")
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
                    Button {
                        openProviderCLI(loginHelp)
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundStyle(Palette.cyan)
                    }
                    .buttonStyle(.borderless)
                    .help(loginHelp.helpText)
                    .accessibilityLabel("Open \(s.title)")
                }
            }
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, row in
                rowView(row, accent: accent)
            }
        }
        .opacity(s.isStale ? 0.55 : 1)
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
        case .sparkline(let spark):
            (Text("7d ").foregroundStyle(Palette.dim)
             + Text(AsciiSparkline.render(spark)))
                .foregroundStyle(accent)
                .padding(.leading, 26)
        case .burnRate(let burn):
            Text(burn.text)
                .font(.caption)
                .foregroundStyle(terminalPaceColor(burn.pace))
                .padding(.leading, 26)
        case .cost(let c):
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(c.label.lowercased()).foregroundStyle(Palette.dim)
                    Spacer(minLength: 8)
                    Text(c.valueText).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(costValueColor(c.state))
                }
                Text(c.footnoteText).foregroundStyle(Palette.dim)
            }
        case .error(let message):
            Text("✗ \(message)").foregroundStyle(Palette.critical)
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
                    .accessibilityLabel("Open \(s.title)")
                }
            }
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
        }
        .opacity(s.isStale ? 0.55 : 1)
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
        case .sparkline(let spark):
            (Text("7d ").foregroundStyle(Palette.dim)
             + Text(AsciiSparkline.render(spark)))
                .foregroundStyle(Palette.mid)
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
        case .note(let text):
            Text(text).foregroundStyle(Palette.mid)
        }
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
                    .accessibilityLabel("Open \(s.title)")
                }
            }
            .padding(.horizontal, 4)
            .background(Palette.bg)
            .foregroundStyle(Palette.dim)
            .offset(x: 8, y: -8)
        }
        .padding(.top, 8)
        .opacity(s.isStale ? 0.55 : 1)
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
        case .sparkline(let spark):
            sparklineGauge(spark)
        case .burnRate(let burn):
            Text("[\(burn.text)]")
                .font(.caption)
                .foregroundStyle(tuiPaceColor(burn.pace))
                .padding(.leading, 24)
        case .cost(let c):
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(c.label.lowercased()).foregroundStyle(Palette.dim)
                    Spacer(minLength: 8)
                    Text(c.valueText).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(costValueColor(c.state))
                }
                Text(c.footnoteText).foregroundStyle(Palette.dim)
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
        .accessibilityHidden(true)
    }

    // Спарклайн [▁▂▄█…] 7d в стиле датчика: заполнено = использовано, ширина 24 глифа.
    private func sparklineGauge(_ spark: SparklineContent) -> some View {
        (
            Text("[")
            + Text(AsciiSparkline.render(spark, width: 24))
                .foregroundStyle(Palette.normal)
            + Text("]")
            + Text(" 7d")
        )
        .foregroundStyle(Palette.dim)
        .padding(.leading, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("7-day usage trend")
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
