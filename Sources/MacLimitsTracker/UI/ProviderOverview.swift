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
            // PointMark обязателен: одиночный LineMark с одной точкой ничего не рисует.
            Chart(spark.points, id: \.time) { point in
                LineMark(x: .value("Time", point.time), y: .value("Used", point.usedPercent))
                PointMark(x: .value("Time", point.time), y: .value("Used", point.usedPercent))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .foregroundStyle(accent)
            .frame(height: sparklineHeight)
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
            Text(AsciiSparkline.render(usedPercents: spark.points.map(\.usedPercent)))
                .foregroundStyle(accent)
                .padding(.leading, 26)
        case .error(let message):
            Text("✗ \(message)").foregroundStyle(Palette.critical)
        case .note(let text):
            Text(text).foregroundStyle(Palette.dim)
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
            Text(AsciiSparkline.render(usedPercents: spark.points.map(\.usedPercent)))
                .foregroundStyle(Palette.mid)
                .padding(.leading, 26)
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
    }

    // Спарклайн [▁▂▄█…] в стиле датчика: заполнено = использовано.
    private func sparklineGauge(_ spark: SparklineContent) -> some View {
        (
            Text("[")
            + Text(AsciiSparkline.render(usedPercents: spark.points.map(\.usedPercent)))
                .foregroundStyle(Palette.normal)
            + Text("]")
        )
        .foregroundStyle(Palette.dim)
        .padding(.leading, 24)
    }

    private func severityColor(_ severity: Severity) -> Color {
        switch severity {
        case .normal:   return Palette.normal
        case .warning:  return Palette.warning
        case .critical: return Palette.critical
        }
    }
}

