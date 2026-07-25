import SwiftUI
import MacLimitsTrackerCore

/// Тема Phosphor: монохромный зелёный CRT.
struct PhosphorStatusView: View {
    @ObservedObject var viewModel: LimitsViewModel
    let desktopWidgetController: DesktopWidgetController

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
            ForEach(viewModel.states) { state in
                section(PopupContentBuilder.section(state, thresholds: viewModel.severityThresholds))
            }
            promptLine
            PopupFooter(viewModel: viewModel, desktopWidgetController: desktopWidgetController)
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
            Text("~/limits — \(PopupContentBuilder.updatedText(states: viewModel.states).lowercased())")
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

    // Мигающий курсор — единственная анимация темы. phaseAnimator, а не
    // repeatForever в onAppear: looping-анимация привязана к жизненному циклу
    // вью и корректно перезапускается после переоткрытия окна MenuBarExtra —
    // repeatForever в onAppear при этом рассинхронизировался и курсор замирал.
    private var promptLine: some View {
        HStack(spacing: 2) {
            Text("$").foregroundStyle(Palette.mid)
            Text("▮")
                .foregroundStyle(Palette.bright)
                .phaseAnimator([false, true]) { content, phase in
                    content.opacity(phase ? 1 : 0)
                } animation: { _ in
                    .easeInOut(duration: 0.6)
                }
        }
    }

    private func section(_ s: ProviderSectionContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
        case .error(let message):
            Text("! \(message)").foregroundStyle(Palette.heading)
        case .note(let text):
            Text(text).foregroundStyle(Palette.mid)
        }
    }
}
