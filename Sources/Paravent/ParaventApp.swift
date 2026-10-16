import AppKit
import ApplicationServices
import ParaventCore
import SwiftUI

@main
enum ParaventMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        if let capture = Capture(arguments: CommandLine.arguments) {
            let delegate = CaptureDelegate(capture: capture)
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
            return
        }
        migrateFromDrawer()
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private static func migrateFromDrawer() {
        let old = Store.folder.deletingLastPathComponent().appendingPathComponent(DrawerMigration.oldFolderName, isDirectory: true)
        DrawerMigration.copyFolder(from: old, to: Store.folder)
        DrawerMigration.copyDefaults(UserDefaults.standard.persistentDomain(forName: DrawerMigration.oldDomain), to: .standard)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store(folder: Store.folder)
    private let updater = Updater(active: true)
    private let settingsSelection = SettingsSelection()
    private var statusItem: NSStatusItem!
    private var panel: PanelController!
    private var divider: DividerController!
    private var arranger: Arranger!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }

        // New items are added on the far left, where a crowded bar drops them first; seed a spot next to the system icons.
        let positionKey = "NSStatusItem Preferred Position paravent.main"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(5, forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "paravent.main"

        if let button = statusItem.button {
            let image = NSImage(named: "MenuBarIconTemplate") ?? NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: nil)
            image?.accessibilityDescription = "Paravent"
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        divider = DividerController()
        arranger = Arranger(store: store, divider: divider)

        Task {
            try? await Task.sleep(for: .seconds(1))
            await store.refresh()
            if store.modes.values.contains(where: { $0 != .visible }) { divider.collapse() }
        }

        panel = PanelController(
            store: store,
            updater: updater,
            anchor: { [weak self] in self?.buttonFrame() ?? .zero },
            onSettings: { [weak self] in self?.openSettings() },
            onUpdate: { [weak self] in self?.openSettings(.general) },
            onActivate: { [weak self] item in
                guard let arranger = self?.arranger else { return }
                Task { await arranger.activate(item) }
            }
        )
        updater.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    @objc func mouseEntered(with event: NSEvent) {
        panel.show(pinned: false)
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            if let title = Updater.menuTitle(updater.release, updater.status) {
                menu.addItem(withTitle: title, action: #selector(showUpdate), keyEquivalent: "").target = self
                menu.addItem(.separator())
            }
            menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(openSettingsAction), keyEquivalent: ",").target = self
            let toggleTitle = divider.collapsed ? String(localized: "Show Hidden Icons") : String(localized: "Hide Icons Again")
            menu.addItem(withTitle: toggleTitle, action: #selector(toggleCollapsed), keyEquivalent: "").target = self
            menu.addItem(withTitle: String(localized: "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: String(localized: "Quit Paravent"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            if let button = statusItem.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            }
        } else {
            panel.handleClick()
        }
    }

    @objc private func openSettingsAction() { openSettings() }
    @objc private func showUpdate() { openSettings(.general) }

    @objc private func checkForUpdates() {
        updater.check(manual: true)
        openSettings(.general)
    }

    @objc private func toggleCollapsed() {
        if divider.collapsed { arranger.reveal() } else { arranger.collapse() }
    }

    private func openSettings(_ tab: SettingsTab? = nil) {
        if let tab { settingsSelection.tab = tab }
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "Paravent Settings")
            window.contentViewController = NSHostingController(rootView: SettingsView(
                store: store, updater: updater, selection: settingsSelection,
                onApply: { [weak self] in
                    guard let arranger = self?.arranger else { return }
                    Task { await arranger.apply() }
                }
            ))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
            }
        }
        // An accessory app's window opens behind other apps; a regular policy while it is open lets it come forward.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
        Task { await store.refresh() }
    }

    private func buttonFrame() -> NSRect {
        guard let button = statusItem.button, let window = button.window else { return .zero }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}
