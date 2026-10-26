import AppKit

@MainActor
final class DividerController {
    private static let revealedLength: CGFloat = 16
    private static let collapsedLength: CGFloat = 10000

    let item: NSStatusItem
    private(set) var collapsed = false

    init() {
        let key = "NSStatusItem Preferred Position paravent.divider"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(6, forKey: key)
        }
        item = NSStatusBar.system.statusItem(withLength: Self.revealedLength)
        item.autosaveName = "paravent.divider"
        showRevealedAppearance()
    }

    var frame: CGRect { item.button?.window?.frame ?? .zero }
    var windowID: CGWindowID { CGWindowID(truncatingIfNeeded: max(0, item.button?.window?.windowNumber ?? 0)) }

    // On modern macOS Control Center hosts the actual status-item window;
    // button.window.windowNumber can be zero and uses a different coordinate space.
    func liveWindow(rowTop: Int?) -> MenuBarWindow? {
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { info -> MenuBarWindow? in
            guard info[kCGWindowName as String] as? String == "paravent.divider",
                  let window = MenuBarWindow.read(info),
                  rowTop.map({ Int(window.frame.minY.rounded()) == $0 }) ?? true else { return nil }
            return window
        }.first
    }

    func collapse() {
        collapsed = true
        item.button?.image = nil
        item.length = Self.collapsedLength
    }

    func reveal() {
        collapsed = false
        item.length = Self.revealedLength
        showRevealedAppearance()
    }

    private func showRevealedAppearance() {
        let image = NSImage(named: "MenuBarDividerTemplate") ?? NSImage(systemSymbolName: "chevron.compact.left", accessibilityDescription: nil)
        image?.accessibilityDescription = String(localized: "Paravent divider")
        item.button?.image = image
    }
}
