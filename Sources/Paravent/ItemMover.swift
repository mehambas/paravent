import AppKit

enum ItemMover {
    // Menu bar items are rearranged by Cmd-dragging them; there is no API for it.
    static func drag(from start: CGPoint, to end: CGPoint) async {
        await Task.detached(priority: .userInitiated) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let original = CGEvent(source: nil)?.location ?? start

            func post(_ type: CGEventType, _ point: CGPoint) {
                guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
                event.flags = .maskCommand
                event.post(tap: .cghidEventTap)
            }

            post(.leftMouseDown, start)
            usleep(80_000)
            let steps = 14
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                post(.leftMouseDragged, point)
                usleep(25_000)
            }
            usleep(80_000)
            post(.leftMouseUp, end)
            usleep(150_000)
            CGWarpMouseCursorPosition(original)
        }.value
    }
}
