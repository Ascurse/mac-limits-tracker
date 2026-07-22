import SwiftUI
import MacLimitsTrackerCore

/// Тема TUI: панели с рамками и датчиками в духе htop.
struct TUIStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let desktopWidgetController: DesktopWidgetController

    private enum Palette {
        static let bg = Color(hex: 0x101216)
        static let fg = Color(hex: 0xD0D5DD)
        static let border = Color(hex: 0x3A4150)
        static let dim = Color(hex: 0x5A6374)
        static let normal = Color(hex: 0x9ECE6A)
        static let warning = Color(hex: 0xE0AF68)
        static let critical = Color(hex: 0xF7768E)
    }

    private let mono = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ForEach(viewModel.states) { state in
                panel(PopupContentBuilder.section(state))
            }
            PopupFooter(viewModel: viewModel, desktopWidgetController: desktopWidgetController)
                .tint(Palette.normal)
        }
        .font(mono)
        .foregroundStyle(Palette.fg)
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
        .background(Palette.bg)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Text(PopupContentBuilder.updatedText(states: viewModel.states))
                .foregroundStyle(Palette.dim)
            Spacer()
            Button {
                viewModel.refresh()
            } label: {
                keyBadge("F5 refresh")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
        }
    }

    private func keyBadge(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Palette.border)
            .foregroundStyle(Palette.fg)
    }

    // Панель с рамкой; заголовок врезан в верхнюю кромку — рамку рисуем
    // SwiftUI-обводкой, не символами (символьные рамки «плывут» по ширине).
    private func panel(_ s: ProviderSectionContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
                    .accessibilityLabel("Open Claude Code")
                }
            }
            .padding(.horizontal, 4)
            .background(Palette.bg)
            .foregroundStyle(Palette.dim)
            .offset(x: 8, y: -8)
        }
        .padding(.top, 8)
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

    private func severityColor(_ severity: Severity) -> Color {
        switch severity {
        case .normal:   return Palette.normal
        case .warning:  return Palette.warning
        case .critical: return Palette.critical
        }
    }
}
