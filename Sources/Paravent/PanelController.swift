import AppKit
import SwiftUI

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private let host: FirstMouseHostingView<PanelView>
    private let store: Store
    private let anchor: () -> NSRect

    private var pinned = false
    private var outsideSince: Date?
    private var pollTimer: Timer?
    private var clickMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init(store: Store, updater: Updater, anchor: @escaping () -> NSRect, onSettings: @escaping () -> Void,
         onUpdate: @escaping () -> Void, onActivate: @escaping (BarItem) -> Void) {
        self.store = store
        self.anchor = anchor
        panel = FloatingPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)

        host = FirstMouseHostingView(rootView: PanelView(store: store, updater: updater, onPress: { _ in }, onSettings: onSettings, onUpdate: onUpdate))
        panel.contentView = host
        host.rootView = PanelView(
            store: store,
            updater: updater,
            onPress: { [weak self] item in
                self?.hide()
                onActivate(item)
            },
            onSettings: { [weak self] in
                self?.hide()
                onSettings()
            },
            onUpdate: { [weak self] in
                self?.hide()
                onUpdate()
            }
        )
    }

    func show(pinned: Bool) {
        if panel.isVisible {
            if pinned { self.pinned = true }
            return
        }
        self.pinned = pinned
        outsideSince = nil
        layout()
        panel.orderFrontRegardless()
        startWatching()
        Task {
            await store.refresh()
            layout()
        }
    }

    func hide() {
        panel.orderOut(nil)
        pinned = false
        pollTimer?.invalidate()
        pollTimer = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    func handleClick() {
        if !panel.isVisible {
            show(pinned: true)
        } else if !pinned {
            pinned = true
        } else {
            hide()
        }
    }

    private func layout() {
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let a = anchor()
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: a.midX, y: a.midY)) } ?? NSScreen.main
        var x = a.midX - size.width / 2
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        panel.setFrame(NSRect(x: x, y: a.minY - size.height - 6, width: size.width, height: size.height), display: true)
    }

    private func startWatching() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.pinned else { return }
                let mouse = NSEvent.mouseLocation
                if !self.panel.frame.contains(mouse) && !self.anchor().contains(mouse) { self.hide() }
            }
        }
    }

    private func tick() {
        guard !pinned else { return }
        let mouse = NSEvent.mouseLocation
        let inside = anchor().insetBy(dx: -4, dy: -4).contains(mouse) || panel.frame.insetBy(dx: -8, dy: -8).contains(mouse)
        if inside {
            outsideSince = nil
        } else if let since = outsideSince {
            if Date().timeIntervalSince(since) > 0.35 { hide() }
        } else {
            outsideSince = Date()
        }
    }
}
