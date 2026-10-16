import AppKit
import ApplicationServices

final class AXBox: @unchecked Sendable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
}

struct BarItem: Identifiable, Sendable {
    let id: String
    let name: String
    let bundleID: String
    let windowID: CGWindowID
    let pid: pid_t
    let frame: CGRect
    let axElement: AXBox?

    // The clock and the Control Center button can't be moved or hidden.
    var isPinned: Bool {
        bundleID == "com.apple.controlcenter" && (id.hasSuffix("/Clock") || id.contains("/BentoBox"))
    }

    var appIcon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
}

enum MenuBarScanner {
    private struct Extra {
        let app: NSRunningApplication
        let frame: CGRect
        let element: AXUIElement
        let identifier: String?
    }

    private struct Win {
        let id: CGWindowID
        let pid: pid_t
        let title: String
        let frame: CGRect
    }

    private static func controlCenterName(_ base: String) -> String? {
        switch base {
        case "WiFi": String(localized: "Wi-Fi")
        case "Bluetooth": String(localized: "Bluetooth")
        case "Battery": String(localized: "Battery")
        case "Clock": String(localized: "Clock")
        case "FocusModes": String(localized: "Focus")
        case "NowPlaying": String(localized: "Now Playing")
        case "BentoBox": String(localized: "Control Center")
        default: nil
        }
    }

    static func scan(preferredRowTop: Int? = nil) -> [BarItem] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        let level = Int(CGWindowLevelForKey(.statusWindow))

        // Popover windows share the status level but are tall; real items are at most menu-bar high.
        let wins: [Win] = list.compactMap { w in
            guard w[kCGWindowLayer as String] as? Int == level,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dict),
                  frame.width > 10, frame.height <= 50 else { return nil }
            return Win(id: id, pid: pid, title: w[kCGWindowName as String] as? String ?? "", frame: frame)
        }

        // Every display carries its own copy of each item. The live windows follow the active display and are the ones
        // with generic "Item-N" titles; the copies are titled with bundle ids.
        func isGeneric(_ win: Win) -> Bool { win.title.isEmpty || win.title.hasPrefix("Item-") }
        let candidates = wins.filter { !$0.title.hasPrefix("paravent.") }
        let rows = Dictionary(grouping: candidates) { Int($0.frame.minY.rounded()) }
        let liveRow = preferredRowTop.flatMap { rows[$0] == nil ? nil : $0 } ?? rows.max { a, b in
            let ca = a.value.filter(isGeneric).count, cb = b.value.filter(isGeneric).count
            return ca != cb ? ca < cb : abs(a.key) > abs(b.key)
        }?.key ?? 0
        let primary = candidates
            .filter { Int($0.frame.minY.rounded()) == liveRow }
            .sorted { $0.frame.minX < $1.frame.minX }

        var extras = accessibilityExtras()
        var ordinals: [String: Int] = [:]
        var items: [BarItem] = []

        for win in primary {
            let match = extras.enumerated()
                .filter { $0.element.frame.width > 0 && abs($0.element.frame.midY - win.frame.midY) < 30 }
                .map { (index: $0.offset, distance: abs($0.element.frame.midX - win.frame.midX)) }
                .filter { $0.distance < 14 }
                .min { $0.distance < $1.distance }
                .map { extras.remove(at: $0.index) }

            let owner = match?.app ?? NSRunningApplication(processIdentifier: win.pid)
            let bundle = owner?.bundleIdentifier ?? "pid.\(win.pid)"
            let genericTitle = win.title.isEmpty || win.title.hasPrefix("Item-")
            if match == nil, win.frame.width > 120, bundle != "com.apple.controlcenter" { continue }

            let short = win.title.replacingOccurrences(of: "com.apple.menuextra.", with: "")
            let base = short.split(separator: "-").first.map(String.init) ?? short
            let discriminator: String
            if genericTitle {
                let n = ordinals[bundle, default: 0]
                ordinals[bundle] = n + 1
                discriminator = "\(n)"
            } else {
                discriminator = short
            }
            let name = genericTitle ? (owner?.localizedName ?? win.title) : (controlCenterName(base) ?? owner?.localizedName ?? short)
            let stableID = "\(bundle)/\(discriminator)"

            items.append(BarItem(
                id: stableID,
                name: name,
                bundleID: bundle,
                windowID: win.id,
                pid: owner?.processIdentifier ?? win.pid,
                frame: win.frame,
                axElement: match.map { AXBox($0.element) }
            ))
        }
        return items
    }

    // CGWindowList reports each display's menu bar as a separate row. Anchor scans to
    // the display under the pointer so copies on an external monitor aren't mixed in.
    static func rowTop(for point: CGPoint) -> Int? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return Int(CGDisplayBounds(CGDirectDisplayID(number.uint32Value)).minY.rounded())
    }

    private static func accessibilityExtras() -> [Extra] {
        let apps = NSWorkspace.shared.runningApplications
        let lock = NSLock()
        var result: [Extra] = []
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let found = extras(of: apps[index])
            guard !found.isEmpty else { return }
            lock.lock()
            result.append(contentsOf: found)
            lock.unlock()
        }
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    private static func extras(of app: NSRunningApplication) -> [Extra] {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.4)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar else { return [] }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let children = kids as? [AXUIElement] else { return [] }
        return children.compactMap { child in
            var pos: CFTypeRef?, size: CFTypeRef?, identifier: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &pos)
            AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &size)
            AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &identifier)
            var p = CGPoint.zero, s = CGSize.zero
            guard let pos, let size,
                  AXValueGetValue(pos as! AXValue, .cgPoint, &p),
                  AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
            return Extra(app: app, frame: CGRect(origin: p, size: s), element: child,
                         identifier: identifier as? String)
        }
    }
}

enum ItemPress {
    static func position(of item: BarItem) -> CGPoint? {
        guard let box = item.axElement else { return nil }
        var value: CFTypeRef?
        AXUIElementSetMessagingTimeout(box.element, 0.3)
        var p = CGPoint.zero
        guard AXUIElementCopyAttributeValue(box.element, kAXPositionAttribute as CFString, &value) == .success,
              let value, AXValueGetValue(value as! AXValue, .cgPoint, &p) else { return nil }
        return p
    }

    static func press(_ item: BarItem) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let box = item.axElement {
                // AXPress blocks while the item's menu is open; the timeout returns control right away.
                AXUIElementSetMessagingTimeout(box.element, 1)
                AXUIElementPerformAction(box.element, kAXPressAction as CFString)
                return
            }
            let point = CGPoint(x: item.frame.midX, y: item.frame.midY)
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                    .postToPid(item.pid)
            }
        }
    }
}
