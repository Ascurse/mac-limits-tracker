import AppKit
import Combine
import SwiftUI
import MacLimitsTrackerCore

/// Окно десктоп-виджета: non-activating NSPanel на уровне обоев, видимый на всех Spaces.
@MainActor
final class DesktopWidgetController {
    private var panel: NSPanel?
    private let viewModel: LimitsViewModel
    private var cancellables: Set<AnyCancellable> = []

    private static let autosaveName = NSWindow.FrameAutosaveName("DesktopWidget")

    var isVisible: Bool { panel?.isVisible ?? false }

    init(viewModel: LimitsViewModel) {
        self.viewModel = viewModel

        // Начальное состояние применяет App (.task) — подписка с dropFirst()
        // реагирует только на последующие изменения из любой поверхности.
        viewModel.$showDesktopWidget
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.setVisible($0) }
            .store(in: &cancellables)
    }

    func show() {
        if panel == nil { panel = makePanel() }
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func setVisible(_ visible: Bool) {
        visible ? show() : hide()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        // Чуть выше уровня обоев: панель лежит под обычными окнами.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: DesktopWidgetView(viewModel: viewModel))

        if !panel.setFrameUsingName(Self.autosaveName) {
            positionDefault(panel)
        }
        panel.setFrameAutosaveName(Self.autosaveName)
        return panel
    }

    /// Дефолт — правый верхний угол основного экрана (под меню-баром).
    private func positionDefault(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24
        )
        panel.setFrameOrigin(origin)
    }
}
