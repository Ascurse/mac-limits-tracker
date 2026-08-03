import SwiftUI
import MacLimitsTrackerCore

/// Геометрический вариант блока тренда. Меняет только высоту графика —
/// порядок элементов и семантика между поверхностями одинаковые.
enum UsageTrendVariant: Equatable {
    case compact
    case regular
}

extension ProviderOverviewSurface {
    var trendVariant: UsageTrendVariant {
        switch self {
        case .menuBar: return .compact
        case .desktop: return .regular
        }
    }
}

/// Форма маркера точки — токен темы.
enum UsageTrendPointShape: Equatable {
    case circle
    case square
}

/// Токены темы для UsageTrendView — единственное, чем различаются темы.
/// Семантику (шкала, подписи, порядок элементов) токены изменить не могут.
struct UsageTrendTokens {
    var accent: Color
    var guide: Color
    var text: Color
    var dim: Color
    var lineWidth: CGFloat
    var pointSize: CGFloat
    var pointShape: UsageTrendPointShape
    var background: Color?
    var border: Color?
    var font: Font
}

/// Единый блок тренда для всех четырёх тем. Принимает контракт gld.1
/// (SparklineContent) и токены темы; view-state строит UsageTrendPresentationPolicy,
/// поэтому геометрия, шкала 0...100, подписи и состояния нехватки данных
/// идентичны у всех тем.
///
/// Анатомия блока (одинаковая везде):
/// 1. header (опционально — в ProviderOverview подавлен, т.к. window-строка уже
///    показывает label/current/severity): shortLabel + metricLabel + severityCue + currentText;
/// 2. plot: фиксированный домен 0...100 с подписанными направляющими, линия/маркеры
///    или placeholder состояния (empty/loading);
/// 3. note: fallbackText для sparse/gap/stale, когда точки всё же показаны;
/// 4. period labels: диапазон тренда («7d» + даты начала/конца).
struct UsageTrendView: View {
    let state: UsageTrendViewState
    let tokens: UsageTrendTokens
    let variant: UsageTrendVariant
    let showHeader: Bool

    init(content: SparklineContent, tokens: UsageTrendTokens, variant: UsageTrendVariant,
         showHeader: Bool = true) {
        self.state = UsageTrendPresentationPolicy.viewState(for: content)
        self.tokens = tokens
        self.variant = variant
        self.showHeader = showHeader
    }

    private var plotHeight: CGFloat { variant == .regular ? 44 : 28 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showHeader { headerView }
            plotArea
            if let note = state.noteText, !state.segments.isEmpty {
                noteRow(note)
            }
            periodRow
        }
        .background(tokens.background ?? .clear)
        .overlay(borderOverlay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.accessibilityValue)
    }

    private var headerView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(state.shortLabel) \(state.metricLabel)")
                .foregroundStyle(tokens.dim)
            Spacer(minLength: 8)
            if !state.severityCue.isEmpty {
                Text(state.severityCue)
                    .foregroundStyle(tokens.accent)
            }
            Text(state.currentText)
                .monospacedDigit()
                .foregroundStyle(tokens.text)
        }
        .font(tokens.font)
    }

    @ViewBuilder
    private var plotArea: some View {
        if state.segments.isEmpty {
            placeholder
        } else {
            plot
        }
    }

    private var placeholder: some View {
        Text(state.noteText ?? "—")
            .font(tokens.font)
            .foregroundStyle(tokens.dim)
            .frame(maxWidth: .infinity)
            .frame(height: plotHeight)
    }

    private func noteRow(_ note: String) -> some View {
        Text(note)
            .font(tokens.font)
            .foregroundStyle(tokens.dim)
    }

    private var periodRow: some View {
        HStack {
            Text(state.trendRangeLabel)
            Spacer()
            Text(state.periodStartLabel)
            Text("–")
            Text(state.periodEndLabel)
        }
        .font(tokens.font)
        .foregroundStyle(tokens.dim)
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if let border = tokens.border {
            RoundedRectangle(cornerRadius: 2)
                .stroke(border, lineWidth: 1)
        }
    }

    // Canvas вместо Swift Charts: фиксированные домены, направляющие и
    // дисконтинуити на разрывах детерминированы, без серийных сюрпризов Charts
    // и без автомасштаба.
    private var plot: some View {
        Canvas { context, size in
            drawGuides(context: context, size: size)
            drawSegments(context: context, size: size)
        }
        .frame(height: plotHeight)
    }

    private func yPosition(_ percent: Double, in size: CGSize) -> CGFloat {
        size.height * (1 - CGFloat(percent - state.yDomain.lowerBound)
                       / CGFloat(state.yDomain.upperBound - state.yDomain.lowerBound))
    }

    private func xPosition(_ time: Date, in size: CGSize) -> CGFloat {
        let total = state.xDomain.upperBound.timeIntervalSince(state.xDomain.lowerBound)
        guard total > 0 else { return 0 }
        return size.width * CGFloat(time.timeIntervalSince(state.xDomain.lowerBound) / total)
    }

    private func drawGuides(context: GraphicsContext, size: CGSize) {
        for guide in state.scaleGuides {
            let y = yPosition(guide, in: size)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(tokens.guide),
                           style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))

            let label = Text(guide.formatted(.number.precision(.fractionLength(0))))
                .font(tokens.font)
                .foregroundStyle(tokens.dim)
            let anchor: UnitPoint = guide == state.yDomain.upperBound ? .topLeading
                : guide == state.yDomain.lowerBound ? .bottomLeading : .leading
            context.draw(context.resolve(label), at: CGPoint(x: 2, y: y), anchor: anchor)
        }
    }

    private func drawSegments(context: GraphicsContext, size: CGSize) {
        for segment in state.segments {
            let centers = segment.map { CGPoint(x: xPosition($0.time, in: size),
                                                y: yPosition($0.remainingPercent, in: size)) }
            if state.showsLine, centers.count > 1 {
                var path = Path()
                path.addLines(centers)
                context.stroke(path, with: .color(tokens.accent),
                               style: StrokeStyle(lineWidth: tokens.lineWidth, lineCap: .round, lineJoin: .round))
            }
            for center in centers {
                drawPoint(context: context, at: center)
            }
        }
    }

    private func drawPoint(context: GraphicsContext, at center: CGPoint) {
        let side = tokens.pointSize
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        let path = tokens.pointShape == .circle ? Path(ellipseIn: rect) : Path(rect)
        context.fill(path, with: .color(tokens.accent))
    }
}
