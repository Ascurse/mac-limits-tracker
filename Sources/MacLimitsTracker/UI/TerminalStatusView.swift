import SwiftUI
import MacLimitsTrackerCore

/// Тема Terminal: палитра Tokyo Night, тонкие полосы прогресса.
struct TerminalStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let desktopWidgetController: DesktopWidgetController

    private enum Palette {
        static let bg = Color(hex: 0x1A1B26)
        static let fg = Color(hex: 0xC0CAF5)
        static let dim = Color(hex: 0x565F89)
        static let track = Color(hex: 0x2F334D)
        static let cyan = Color(hex: 0x7DCFFF)
        static let claude = Color(hex: 0xFF9E64)
        static let codex = Color(hex: 0x9ECE6A)
        static let warning = Color(hex: 0xE0AF68)
        static let critical = Color(hex: 0xF7768E)
    }

    private let mono = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            section(PopupContentBuilder.claudeSection(viewModel.claude), accent: Palette.claude, name: "claude", showOpenClaude: true)
            section(PopupContentBuilder.codexSection(viewModel.codex), accent: Palette.codex, name: "codex")
            Rectangle().fill(Palette.track).frame(height: 1)
            PopupFooter(viewModel: viewModel, desktopWidgetController: desktopWidgetController)
                .tint(Palette.cyan)
        }
        .font(mono)
        .foregroundStyle(Palette.fg)
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
        .background(Palette.bg)
        .environment(\.colorScheme, .dark) // системные контролы читаемы на тёмном фоне
    }

    private var header: some View {
        HStack {
            Text("limits-tracker").foregroundStyle(Palette.cyan)
            Spacer()
            Text(PopupContentBuilder.updatedText(claude: viewModel.claude, codex: viewModel.codex))
                .foregroundStyle(Palette.dim)
            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(viewModel.isRefreshing ? Palette.dim : Palette.cyan)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
        }
    }

    private func section(_ s: ProviderSectionContent, accent: Color, name: String, showOpenClaude: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("●").foregroundStyle(accent)
                Text(name)
                // Значение Plan из первой detail-строки показываем рядом с именем.
                if case .detail(let key, let value) = s.rows.first, key == "Plan" {
                    Text(value).foregroundStyle(Palette.dim)
                }
                Spacer()
                if showOpenClaude {
                    Button {
                        openClaudeCode()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundStyle(Palette.cyan)
                    }
                    .buttonStyle(.borderless)
                    .help("Open Claude Code to refresh the claude.ai login")
                    .accessibilityLabel("Open Claude Code")
                }
            }
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, row in
                rowView(row, accent: accent)
            }
        }
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
