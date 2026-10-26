import AppKit

struct MenuBarWindow: Sendable {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect

    static func read(id: CGWindowID) -> MenuBarWindow? {
        guard id != 0,
              let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]],
              let info = list.first(where: { $0[kCGWindowNumber as String] as? CGWindowID == id }) else { return nil }
        return read(info)
    }

    static func read(_ info: [String: Any]) -> MenuBarWindow? {
        guard info[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
              let id = info[kCGWindowNumber as String] as? CGWindowID,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds),
              frame.width > 0, frame.height > 0, frame.height <= 50 else { return nil }
        return MenuBarWindow(id: id, pid: pid, frame: frame)
    }
}

enum ItemMover {
    // A crowded menu bar retains windows that cannot receive physical mouse hits.
    // Preserve the real window number through AppKit and route the event to its
    // window-host process at the session tap, rather than hit-testing the desktop.
    @MainActor
    static func drag(windowID: CGWindowID, to end: CGPoint) async {
        guard let window = MenuBarWindow.read(id: windowID) else {
            Log.write("drag skipped: missing window \(windowID)")
            return
        }
        let start = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let number = Int.random(in: 1...Int(Int32.max))
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> CGEvent? {
            guard let event = NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: Int(window.id),
                context: nil, eventNumber: number, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1)?.cgEvent else { return nil }
            event.location = point
            event.flags = .maskCommand
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.id))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.id))
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(window.pid))
            return event
        }
        guard let down = event(.leftMouseDown, start), let up = event(.leftMouseUp, end) else { return }
        var moves: [CGEvent] = []
        for i in 1...20 {
            let t = CGFloat(i) / 20
            guard let move = event(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t,
                                                            y: start.y + (end.y - start.y) * t)) else { return }
            moves.append(move)
        }
        await Task.detached(priority: .userInitiated) {
            let original = CGEvent(source: nil)?.location ?? start
            down.post(tap: .cgSessionEventTap)
            usleep(100_000)
            for move in moves {
                move.post(tap: .cgSessionEventTap)
                usleep(25_000)
            }
            up.post(tap: .cgSessionEventTap)
            usleep(150_000)
            CGWarpMouseCursorPosition(original)
        }.value
    }
}
