import SwiftUI
import MacLimitsTrackerCore

/// Тема Phosphor: монохромный зелёный CRT.
struct PhosphorStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel
    @State private var cursorVisible = true

    private enum Palette {
        static let bg = Color(hex: 0x050805)
        static let bright = Color(hex: 0x35E06A)
        static let mid = Color(hex: 0x1E9C48)
        static let dim = Color(hex: 0x164A26)
        static let heading = Color(hex: 0x8DFFB0)
    }

    private let mono = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            section(PopupContentBuilder.claudeSection(viewModel.claude), name: "CLAUDE CODE")
            section(PopupContentBuilder.codexSection(viewModel.codex), name: "CODEX")
            promptLine
            PopupFooter(viewModel: viewModel)
                .tint(Palette.mid)
        }
        .font(mono)
        .foregroundStyle(Palette.bright)
        .padding(16)
        .frame(minWidth: 320, idealWidth: 340)
        .background(Palette.bg)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Text("~/limits — \(PopupContentBuilder.updatedText(claude: viewModel.claude, codex: viewModel.codex).lowercased())")
                .foregroundStyle(Palette.mid)
            Spacer()
            Button {
                viewModel.refresh()
            } label: {
                Text("[r]").foregroundStyle(viewModel.isRefreshing ? Palette.dim : Palette.bright)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
        }
    }

    // Мигающий курсор — единственная анимация темы.
    private var promptLine: some View {
        HStack(spacing: 2) {
            Text("$").foregroundStyle(Palette.mid)
            Text("▮")
                .foregroundStyle(Palette.bright)
                .opacity(cursorVisible ? 1 : 0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        cursorVisible = false
                    }
                }
        }
    }

    private func section(_ s: ProviderSectionContent, name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("▸ \(name)").foregroundStyle(Palette.heading)
                if case .detail(let key, let value) = s.rows.first, key == "Plan" {
                    Text("[\(value)]").foregroundStyle(Palette.mid)
                }
                Spacer()
            }
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
        }
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
        case .error(let message):
            Text("! \(message)").foregroundStyle(Palette.heading)
        case .note(let text):
            Text(text).foregroundStyle(Palette.mid)
        }
    }
}
